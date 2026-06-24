#!/bin/bash
###############################################################################
# Monitoring bootstrap for the landing-page EC2 (nginx + PM2 + app on host).
# Use with Terraform:  user_data = templatefile("$${path.module}/userdata.sh.tpl", {
#                          site_url               = "https://your-site.example.com/health"
#                          grafana_admin_password = var.grafana_admin_password
#                        })
#
# Terraform template variables (filled by templatefile at plan/apply):
#   ${site_url}                 - public URL Blackbox will probe
#   ${grafana_admin_password}   - Grafana admin password
#
# NOTE: this file is a Terraform template. Terraform replaces $${...}.
#       Bash variables therefore use the plain $VAR form (no braces) so
#       Terraform does not try to interpolate them.
###############################################################################
set -euxo pipefail

############################ 0. Install Docker ################################
if command -v dnf >/dev/null 2>&1; then
  dnf install -y docker jq
elif command -v amazon-linux-extras >/dev/null 2>&1; then
  amazon-linux-extras install docker -y
  yum install -y jq
else
  yum install -y docker jq || (apt-get update -y && apt-get install -y docker.io jq)
fi
systemctl enable --now docker
usermod -aG docker ec2-user || true

mkdir -p /opt/monitoring /var/lib/node_exporter
chmod 777 /var/lib/node_exporter

############################ Config files #####################################
# prometheus.yml  (host networking -> everything is on localhost)
cat > /opt/monitoring/prometheus.yml <<EOF
global:
  scrape_interval: 30s
scrape_configs:
  - job_name: 'node'
    static_configs: [{ targets: ['localhost:9100'] }]

  - job_name: 'nginx'
    static_configs: [{ targets: ['localhost:9113'] }]

  - job_name: 'blackbox-http'
    metrics_path: /probe
    params: { module: [http_2xx] }
    static_configs:
      - targets: ['${site_url}']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115
EOF

# promtail-config.yml  (ships nginx + pm2 logs to local Loki)
cat > /opt/monitoring/promtail-config.yml <<EOF
server:
  http_listen_port: 9080
positions:
  filename: /tmp/positions.yaml
clients:
  - url: http://localhost:3100/loki/api/v1/push
scrape_configs:
  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels: { job: nginx, __path__: /var/log/nginx/*.log }
  - job_name: pm2
    static_configs:
      - targets: [localhost]
        labels: { job: pm2, __path__: /home/ec2-user/.pm2/logs/*.log }
  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels: { job: syslog, __path__: /var/log/messages }
EOF

############################ PM2 metrics script ###############################
cat > /usr/local/bin/pm2_metrics.sh <<'PMEOF'
#!/bin/bash
OUT=/var/lib/node_exporter/pm2.prom
pm2 jlist 2>/dev/null | jq -r '.[] |
  "pm2_process_up{name=\""+.name+"\"} "+(if .pm2_env.status=="online" then "1" else "0" end),
  "pm2_process_restarts{name=\""+.name+"\"} "+((.pm2_env.restart_time//0)|tostring),
  "pm2_process_cpu{name=\""+.name+"\"} "+((.monit.cpu//0)|tostring),
  "pm2_process_memory_bytes{name=\""+.name+"\"} "+((.monit.memory//0)|tostring)' > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
PMEOF
chmod +x /usr/local/bin/pm2_metrics.sh

# run the script every minute as the app user (so it sees the PM2 daemon)
echo '* * * * * ec2-user /usr/local/bin/pm2_metrics.sh' > /etc/cron.d/pm2_metrics
chmod 644 /etc/cron.d/pm2_metrics

###############################################################################
# IMAGES TO RUN  (all use --network host because the app/nginx live on host)
###############################################################################

#### Tier 1 — Foundation: Prometheus + Grafana + node_exporter ################
docker run -d --restart unless-stopped --name prometheus --network host \
  -v /opt/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus

docker run -d --restart unless-stopped --name grafana --network host \
  -e GF_SECURITY_ADMIN_PASSWORD='${grafana_admin_password}' \
  grafana/grafana

docker run -d --restart unless-stopped --name node-exporter --network host \
  -v /proc:/host/proc:ro -v /sys:/host/sys:ro -v /:/rootfs:ro \
  -v /var/lib/node_exporter:/var/lib/node_exporter:ro \
  prom/node-exporter \
  --path.rootfs=/host \
  --collector.textfile.directory=/var/lib/node_exporter

#### Tier 2 — Site up/down: Blackbox exporter #################################
docker run -d --restart unless-stopped --name blackbox --network host \
  prom/blackbox-exporter

#### Tier 3 — nginx metrics: nginx-prometheus-exporter ########################
# Requires nginx stub_status on 127.0.0.1:8080 (see note below).
docker run -d --restart unless-stopped --name nginx-exporter --network host \
  nginx/nginx-prometheus-exporter \
  --nginx.scrape-uri=http://127.0.0.1:8080/stub_status

#### Tier 4 — PM2 metrics ######################################################
# Handled by the cron script above -> node_exporter textfile collector.

#### Tier 5 — Logs (advanced): Loki + Promtail ###############################
docker run -d --restart unless-stopped --name loki --network host \
  grafana/loki

docker run -d --restart unless-stopped --name promtail --network host \
  -v /opt/monitoring/promtail-config.yml:/etc/promtail/config.yml \
  -v /var/log:/var/log:ro \
  -v /home/ec2-user/.pm2/logs:/home/ec2-user/.pm2/logs:ro \
  grafana/promtail -config.file=/etc/promtail/config.yml

###############################################################################
# POST-INSTALL (manual, one-time):
#  1. Add nginx stub_status so Tier 3 works:
#       server { listen 127.0.0.1:8080;
#         location /stub_status { stub_status; allow 127.0.0.1; deny all; } }
#     then: nginx -s reload
#  2. Grafana:  http://<this-ec2>:3000  (admin / the password above)
#       - Add data source Prometheus -> http://localhost:9090
#       - Add data source Loki       -> http://localhost:3100
#       - Import the site-health dashboard JSON
#  3. Security group: expose 3000 (Grafana) only to your IP. Keep
#     9090/9100/9113/9115/3100 closed to the internet (host-local only).
###############################################################################