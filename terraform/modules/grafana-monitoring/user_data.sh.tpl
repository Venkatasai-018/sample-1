#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/user-data.log) 2>&1
echo "=== Starting Grafana setup at $(date) ==="

# -----------------------------------------------------------------------------
# System Updates
# -----------------------------------------------------------------------------
echo "=== Updating system packages ==="
dnf update -y

# -----------------------------------------------------------------------------
# Install Docker
# -----------------------------------------------------------------------------
echo "=== Installing Docker ==="
dnf install -y docker

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# -----------------------------------------------------------------------------
# Create Grafana directories
# -----------------------------------------------------------------------------
echo "=== Creating Grafana directories ==="
mkdir -p /opt/grafana/data
mkdir -p /opt/grafana/provisioning/datasources
mkdir -p /opt/grafana/provisioning/dashboards
chmod -R 777 /opt/grafana/data

# -----------------------------------------------------------------------------
# Configure CloudWatch datasource
# -----------------------------------------------------------------------------
echo "=== Configuring CloudWatch datasource ==="
cat > /opt/grafana/provisioning/datasources/cloudwatch.yaml <<'EOF'
apiVersion: 1

datasources:
  - name: CloudWatch
    type: cloudwatch
    access: proxy
    isDefault: true
    jsonData:
      authType: default
      defaultRegion: ${aws_region}
    editable: true
EOF

# -----------------------------------------------------------------------------
# Configure dashboard provisioning
# -----------------------------------------------------------------------------
cat > /opt/grafana/provisioning/dashboards/default.yaml <<'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    folderUid: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

mkdir -p /opt/grafana/dashboards

# -----------------------------------------------------------------------------
# Create ASG monitoring dashboard
# -----------------------------------------------------------------------------
cat > /opt/grafana/dashboards/asg-monitoring.json <<'DASHBOARD'
{
  "annotations": {
    "list": []
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 10,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "percent"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 1,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "mode": "single",
          "sort": "none"
        }
      },
      "targets": [
        {
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "dimensions": {
            "AutoScalingGroupName": "$asg_name"
          },
          "expression": "",
          "id": "",
          "matchExact": true,
          "metricEditorMode": 0,
          "metricName": "CPUUtilization",
          "metricQueryType": 0,
          "namespace": "AWS/EC2",
          "period": "60",
          "queryMode": "Metrics",
          "refId": "A",
          "region": "default",
          "sqlExpression": "",
          "statistic": "Average"
        }
      ],
      "title": "ASG CPU Utilization",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 10,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              }
            ]
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 0
      },
      "id": 2,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "mode": "single",
          "sort": "none"
        }
      },
      "targets": [
        {
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "dimensions": {
            "AutoScalingGroupName": "$asg_name"
          },
          "expression": "",
          "id": "",
          "matchExact": true,
          "metricEditorMode": 0,
          "metricName": "GroupInServiceInstances",
          "metricQueryType": 0,
          "namespace": "AWS/AutoScaling",
          "period": "60",
          "queryMode": "Metrics",
          "refId": "A",
          "region": "default",
          "sqlExpression": "",
          "statistic": "Average"
        }
      ],
      "title": "ASG Instance Count",
      "type": "timeseries"
    }
  ],
  "refresh": "30s",
  "schemaVersion": 38,
  "style": "dark",
  "tags": ["${environment}", "asg", "cloudwatch"],
  "templating": {
    "list": [
      {
        "current": {},
        "datasource": {
          "type": "cloudwatch",
          "uid": "cloudwatch"
        },
        "definition": "dimension_values(default,AWS/AutoScaling,GroupInServiceInstances,AutoScalingGroupName)",
        "hide": 0,
        "includeAll": false,
        "label": "ASG Name",
        "multi": false,
        "name": "asg_name",
        "options": [],
        "query": "dimension_values(default,AWS/AutoScaling,GroupInServiceInstances,AutoScalingGroupName)",
        "refresh": 1,
        "regex": "",
        "skipUrlSync": false,
        "sort": 1,
        "type": "query"
      }
    ]
  },
  "time": {
    "from": "now-6h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "ASG Monitoring - ${environment}",
  "uid": "asg-monitoring-${environment}",
  "version": 1,
  "weekStart": ""
}
DASHBOARD

# -----------------------------------------------------------------------------
# Run Grafana Docker container
# -----------------------------------------------------------------------------
echo "=== Starting Grafana container ==="
docker run -d \
  --name grafana \
  --restart always \
  -p ${grafana_port}:3000 \
  -e "GF_SECURITY_ADMIN_USER=${grafana_admin_user}" \
  -e "GF_SECURITY_ADMIN_PASSWORD=${grafana_admin_password}" \
  -e "GF_USERS_ALLOW_SIGN_UP=false" \
  -e "GF_SERVER_ROOT_URL=%(protocol)s://%(domain)s:%(http_port)s/" \
  -e "GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource" \
  -v /opt/grafana/data:/var/lib/grafana \
  -v /opt/grafana/provisioning:/etc/grafana/provisioning \
  -v /opt/grafana/dashboards:/var/lib/grafana/dashboards \
  grafana/grafana:${grafana_version}

# Wait for Grafana to start
echo "=== Waiting for Grafana to start ==="
for i in {1..30}; do
  if curl -s http://localhost:${grafana_port}/api/health | grep -q "ok"; then
    echo "Grafana is healthy!"
    break
  fi
  echo "Waiting for Grafana... attempt $i"
  sleep 5
done

echo "=== Grafana setup complete at $(date) ==="
echo "Access Grafana at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):${grafana_port}"
