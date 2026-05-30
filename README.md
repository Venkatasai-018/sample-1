name: Deploy to EC2

on:
  push:
    branches:
      - main
      - develop
      - qa
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        default: 'dev'
        type: choice
        options:
          - dev
          - qa
          - prod
      node_version:
        description: 'Node.js version'
        required: false
        default: '20'

env:
  APP_DIR: /home/appuser/app
  NVM_DIR: /opt/nvm
  APP_PORT: 3001

jobs:
  deploy:
    runs-on: self-hosted
    environment: ${{ github.event.inputs.environment || (github.ref == 'refs/heads/main' && 'prod') || (github.ref == 'refs/heads/qa' && 'qa') || 'dev' }}
    
    steps:
      - name: Determine environment
        id: env
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            echo "environment=${{ github.event.inputs.environment }}" >> $GITHUB_OUTPUT
            echo "node_version=${{ github.event.inputs.node_version || '20' }}" >> $GITHUB_OUTPUT
          elif [ "${{ github.ref }}" == "refs/heads/main" ]; then
            echo "environment=prod" >> $GITHUB_OUTPUT
            echo "node_version=20" >> $GITHUB_OUTPUT
          elif [ "${{ github.ref }}" == "refs/heads/qa" ]; then
            echo "environment=qa" >> $GITHUB_OUTPUT
            echo "node_version=20" >> $GITHUB_OUTPUT
          else
            echo "environment=dev" >> $GITHUB_OUTPUT
            echo "node_version=20" >> $GITHUB_OUTPUT
          fi

      - name: Set environment file name
        id: envfile
        run: |
          ENV="${{ steps.env.outputs.environment }}"
          if [ "$ENV" == "dev" ]; then
            echo "env_file=.env.dev" >> $GITHUB_OUTPUT
          elif [ "$ENV" == "qa" ]; then
            echo "env_file=.env.qa" >> $GITHUB_OUTPUT
          else
            echo "env_file=.env.production" >> $GITHUB_OUTPUT
          fi

      - name: System updates and dependencies
        run: |
          echo "=== Deployment started at $(date -u) ==="
          sudo dnf update -y
          sudo dnf install -y git tar gzip jq

      - name: Verify AWS CLI
        run: aws --version

      - name: Install Node.js via nvm
        run: |
          export HOME="/root"
          export NVM_DIR="${{ env.NVM_DIR }}"
          sudo mkdir -p "$NVM_DIR"
          sudo chown -R $(whoami):$(whoami) "$NVM_DIR"
          
          # Install nvm
          curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | NVM_DIR="$NVM_DIR" PROFILE=/dev/null bash
          
          # Load nvm and install node
          source "$NVM_DIR/nvm.sh"
          nvm install ${{ steps.env.outputs.node_version }}
          nvm alias default ${{ steps.env.outputs.node_version }}
          nvm use default
          
          # Create symlinks
          NODE_VERSION=${{ steps.env.outputs.node_version }}
          sudo ln -sf "$NVM_DIR/versions/node/v${NODE_VERSION}/bin/node" /usr/local/bin/node
          sudo ln -sf "$NVM_DIR/versions/node/v${NODE_VERSION}/bin/npm" /usr/local/bin/npm
          sudo ln -sf "$NVM_DIR/versions/node/v${NODE_VERSION}/bin/npx" /usr/local/bin/npx
          
          # Make nvm accessible to appuser
          sudo chmod -R 755 "$NVM_DIR"
          
          node --version
          npm --version

      - name: Install PM2
        run: |
          source "${{ env.NVM_DIR }}/nvm.sh"
          npm install -g pm2
          NODE_VERSION=${{ steps.env.outputs.node_version }}
          sudo ln -sf "${{ env.NVM_DIR }}/versions/node/v${NODE_VERSION}/bin/pm2" /usr/local/bin/pm2

      - name: Create app user
        run: |
          if ! id "appuser" &>/dev/null; then
            sudo useradd -r -m -d /home/appuser -s /bin/bash appuser
          fi

      - name: Stop existing PM2 processes
        continue-on-error: true
        run: |
          sudo -u appuser bash -c 'source /opt/nvm/nvm.sh && pm2 stop all && pm2 delete all' || true

      - name: Clone or update application
        run: |
          APP_DIR="${{ env.APP_DIR }}"
          
          if [ -d "$APP_DIR/.git" ]; then
            echo "Updating existing repository..."
            cd "$APP_DIR"
            sudo -u appuser git fetch origin
            sudo -u appuser git reset --hard origin/${{ github.ref_name }}
          else
            echo "Removing old directory if exists..."
            sudo rm -rf "$APP_DIR"
            
            echo "Cloning private repository..."
            sudo -u appuser git clone https://x-access-token:${{ secrets.GIT_PAT }}@github.com/Unsubscribe-ai/landing-page.git "$APP_DIR"
            cd "$APP_DIR"
            sudo -u appuser git checkout ${{ github.ref_name }}
          fi

      - name: Write environment file from Secrets Manager
        if: ${{ vars.ENV_SECRET_ARN != '' }}
        run: |
          APP_DIR="${{ env.APP_DIR }}"
          ENV_FILE="$APP_DIR/${{ steps.envfile.outputs.env_file }}"
          
          ENV_JSON=$(aws secretsmanager get-secret-value \
            --secret-id "${{ vars.ENV_SECRET_ARN }}" \
            --region "${{ vars.AWS_REGION || 'us-east-1' }}" \
            --query 'SecretString' \
            --output text)
          
          echo "$ENV_JSON" | jq -r 'to_entries[] | "\(.key)=\(.value)"' | sudo tee "$ENV_FILE" > /dev/null
          sudo chown appuser:appuser "$ENV_FILE"
          sudo chmod 600 "$ENV_FILE"
          
          echo ".env file written to $ENV_FILE ($(wc -l < "$ENV_FILE") vars)"

      - name: Install dependencies and build
        run: |
          APP_DIR="${{ env.APP_DIR }}"
          cd "$APP_DIR"
          sudo -u appuser bash -c 'source /opt/nvm/nvm.sh && cd /home/appuser/app && npm ci && npm run build'

      - name: Create PM2 ecosystem config
        run: |
          APP_DIR="${{ env.APP_DIR }}"
          ENV="${{ steps.env.outputs.environment }}"
          
          cat << 'PMEOF' | sudo tee "$APP_DIR/ecosystem.config.js" > /dev/null
          module.exports = {
            apps: [{
              name: "landing-page",
              script: "npm",
              args: "start",
              cwd: "/home/appuser/app",
              instances: 1,
              autorestart: true,
              max_restarts: 10,
              min_uptime: "10s",
              max_memory_restart: "512M",
              env: {
                NODE_ENV: "${{ steps.env.outputs.environment }}",
                PORT: "${{ env.APP_PORT }}"
              }
            }]
          };
          PMEOF
          
          sudo chown appuser:appuser "$APP_DIR/ecosystem.config.js"

      - name: Start app with PM2
        run: |
          sudo -u appuser bash -c 'source /opt/nvm/nvm.sh && cd /home/appuser/app && pm2 start ecosystem.config.js && pm2 save'

      - name: Configure PM2 startup
        run: |
          sudo env PATH=$PATH:/usr/local/bin pm2 startup systemd -u appuser --hp /home/appuser

      - name: Install and configure Nginx
        run: |
          sudo dnf install -y nginx
          
          cat << 'NGEOF' | sudo tee /etc/nginx/conf.d/landing-page.conf > /dev/null
          server {
            listen 80;
            server_name _;
          
            location / {
              proxy_pass http://127.0.0.1:${{ env.APP_PORT }};
              proxy_http_version 1.1;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
            }
          }
          NGEOF
          
          sudo rm -f /etc/nginx/conf.d/default.conf
          sudo sed -i '/^    server {/,/^    }/d' /etc/nginx/nginx.conf
          sudo systemctl enable nginx
          sudo systemctl restart nginx

      - name: Configure SSL (dev/qa only)
        if: ${{ steps.env.outputs.environment != 'prod' }}
        run: |
          sudo dnf install -y certbot python3-certbot-nginx
          
          ENV="${{ steps.env.outputs.environment }}"
          if [ "$ENV" == "dev" ]; then
            LANDING_DOMAIN="dev.getunsubscribe.com"
          elif [ "$ENV" == "qa" ]; then
            LANDING_DOMAIN="qa.getunsubscribe.com"
          fi
          
          sudo sed -i "s/server_name _;/server_name ${LANDING_DOMAIN};/" /etc/nginx/conf.d/landing-page.conf
          sudo systemctl restart nginx
          
          sudo certbot --nginx \
            -d ${LANDING_DOMAIN} \
            --non-interactive \
            --agree-tos \
            -m ${{ vars.CERTBOT_EMAIL || 'simi@getunsubscribe.com' }} \
            --redirect
          
          sudo systemctl restart nginx

      - name: Configure CloudWatch agent
        run: |
          sudo dnf install -y amazon-cloudwatch-agent
          
          PROJECT="${{ vars.PROJECT_NAME || 'app' }}"
          ENV="${{ steps.env.outputs.environment }}"
          
          cat << CWEOF | sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null
          {
            "logs": {
              "logs_collected": {
                "files": {
                  "collect_list": [
                    {
                      "file_path": "/home/appuser/.pm2/logs/landing-page-out.log",
                      "log_group_name": "/ec2/${PROJECT}-${ENV}/landing-page",
                      "log_stream_name": "{instance_id}/stdout",
                      "retention_in_days": 30
                    },
                    {
                      "file_path": "/home/appuser/.pm2/logs/landing-page-error.log",
                      "log_group_name": "/ec2/${PROJECT}-${ENV}/landing-page",
                      "log_stream_name": "{instance_id}/stderr",
                      "retention_in_days": 30
                    },
                    {
                      "file_path": "/var/log/user-data.log",
                      "log_group_name": "/ec2/${PROJECT}-${ENV}/landing-user-data",
                      "log_stream_name": "{instance_id}",
                      "retention_in_days": 14
                    }
                  ]
                }
              }
            }
          }
          CWEOF
          
          sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
            -a fetch-config -m ec2 \
            -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

      - name: Verify deployment
        run: |
          echo "=== Deployment completed at $(date -u) ==="
          echo "Checking application status..."
          sudo -u appuser bash -c 'source /opt/nvm/nvm.sh && pm2 status'
          
          # Wait for app to start
          sleep 5
          
          # Health check
          curl -f http://localhost:${{ env.APP_PORT }} || echo "Warning: Health check failed, app may still be starting"

      - name: Deployment summary
        run: |
          echo "========================================"
          echo "Deployment Summary"
          echo "========================================"
          echo "Environment: ${{ steps.env.outputs.environment }}"
          echo "Branch: ${{ github.ref_name }}"
          echo "Commit: ${{ github.sha }}"
          echo "Node.js: ${{ steps.env.outputs.node_version }}"
          echo "App Port: ${{ env.APP_PORT }}"
          echo "========================================"
