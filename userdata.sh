#!/bin/bash
# userdata.sh - Main OpenClaw setup script, sourced from GitHub by the EC2 bootstrap.
# Runs as root. Expects OPENCLAW_REGION, OPENCLAW_STACK_NAME, and GH_PAT to be set in the environment.
exec >> /var/log/openclaw-setup.log 2>&1

echo "=== userdata.sh started: $(date) ==="

export DEBIAN_FRONTEND=noninteractive

REGION="${OPENCLAW_REGION:-us-east-2}"
STACK_NAME="${OPENCLAW_STACK_NAME:-openclaw}"

# Clone the config repo (contains workspace .md files and openclaw.json)
if [ ! -d /opt/openclaw-repo ]; then
  echo "[0/6] Cloning openclaw repository..."
  git clone "https://dgarwin:$GH_PAT@github.com/dgarwin/dgarwin-openclaw.git" /opt/openclaw-repo
fi

# ---------------------------------------------------------------------------
# 1. Get secrets from SSM
# ---------------------------------------------------------------------------
echo "[1/9] Fetching secrets from SSM..."

export ANTHROPIC_KEY=$(aws ssm get-parameter \
  --name "/openclaw/anthropic-key" \
  --with-decryption \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text)

export DISCORD_TOKEN=$(aws ssm get-parameter \
  --name "/openclaw/discord-token" \
  --with-decryption \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text)

export GOG_KEYRING_PASSWORD=$(aws ssm get-parameter \
  --name "/openclaw/google-keyring" \
  --with-decryption \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text)

export GH_PAT=$(aws ssm get-parameter \
  --name "/openclaw/github-pat" \
  --with-decryption \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text)

# Read existing gateway token, or create a new one if absent
export GATEWAY_TOKEN=$(aws ssm get-parameter \
  --name "/openclaw/gateway-token" \
  --with-decryption \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || echo "")

if [ -z "$GATEWAY_TOKEN" ]; then
  echo "  Gateway token not found — generating a new one..."
  export GATEWAY_TOKEN=$(openssl rand -hex 24)
  aws ssm put-parameter \
    --name "/openclaw/gateway-token" \
    --value "$GATEWAY_TOKEN" \
    --type "SecureString" \
    --region "$REGION" \
    --overwrite
  echo "  Gateway token saved to SSM."
else
  echo "  Existing gateway token found — reusing it."
fi

# ---------------------------------------------------------------------------
# 2. Set up GitHub auth for ubuntu user
# ---------------------------------------------------------------------------
echo "[2/9] Configuring GitHub auth for ubuntu..."

sudo -u ubuntu mkdir -p /home/ubuntu/.config/gh
cat > /home/ubuntu/.config/gh/hosts.yml << GHEOF
github.com:
    users:
        dgarwin:
            oauth_token: $GH_PAT
    git_protocol: https
    oauth_token: $GH_PAT
    user: dgarwin
GHEOF
chmod 600 /home/ubuntu/.config/gh/hosts.yml
chown -R ubuntu:ubuntu /home/ubuntu/.config/gh

sudo -u ubuntu git config --global credential.helper store
printf 'https://dgarwin:%s@github.com\n' "$GH_PAT" > /home/ubuntu/.git-credentials
chmod 600 /home/ubuntu/.git-credentials
chown ubuntu:ubuntu /home/ubuntu/.git-credentials

# ---------------------------------------------------------------------------
# 3. Clone / update the OpenClaw repo for ubuntu
# ---------------------------------------------------------------------------
echo "[3/9] Syncing OpenClaw repository..."

if [ -d /home/ubuntu/openclaw-repo/.git ]; then
  sudo -u ubuntu git -C /home/ubuntu/openclaw-repo pull
else
  sudo -u ubuntu git clone https://github.com/dgarwin/dgarwin-openclaw.git /home/ubuntu/openclaw-repo

# Configure git user for commits
sudo -u ubuntu git config --global user.name "David Garwin"
sudo -u ubuntu git config --global user.email "dgarwin@gmail.com"
fi

# ---------------------------------------------------------------------------
# 4. Install Go and gogcli for Google Drive access
# ---------------------------------------------------------------------------
echo "[4/9] Installing Go and gogcli..."

# Install Go
GO_VERSION="1.22.0"
GO_ARCH="arm64"  # Adjust if using x86_64: GO_ARCH="amd64"

if [ ! -d /usr/local/go ]; then
  cd /tmp
  wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
  tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
  rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
fi

export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/ubuntu/.bashrc

# Install build tools for gogcli
apt-get update -qq
apt-get install -y -qq build-essential git

# Build and install gogcli
if [ ! -f /usr/local/bin/gog ]; then
  cd /tmp
  rm -rf /tmp/gogcli
  git clone --depth 1 https://github.com/steipete/gogcli.git
  cd gogcli
  make
  cp bin/gog /usr/local/bin/
  chmod +x /usr/local/bin/gog
  cd /tmp
  rm -rf /tmp/gogcli
fi

# ---------------------------------------------------------------------------
# Configure Google OAuth credentials from SSM
# ---------------------------------------------------------------------------
sudo -u ubuntu mkdir -p /home/ubuntu/.config/gogcli

GOOGLE_OAUTH_JSON=$(aws ssm get-parameter \
  --name "/openclaw/google" \
  --with-decryption \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || echo "")

if [ -n "$GOOGLE_OAUTH_JSON" ]; then
  # Extract client_id and client_secret from the JSON
  echo "$GOOGLE_OAUTH_JSON" | python3 -c 'import json, sys; data = json.load(sys.stdin); creds = data.get("installed", data); print(json.dumps({"client_id": creds["client_id"], "client_secret": creds["client_secret"]}, indent=2))' > /home/ubuntu/.config/gogcli/credentials.json
  
  chmod 600 /home/ubuntu/.config/gogcli/credentials.json
  chown -R ubuntu:ubuntu /home/ubuntu/.config/gogcli
  
  # Set keyring password in environment for ubuntu user
  if ! grep -q "GOG_KEYRING_PASSWORD" /home/ubuntu/.bashrc; then
    echo 'export GOG_KEYRING_PASSWORD="$GOG_KEYRING_PASSWORD"' >> /home/ubuntu/.bashrc
  fi
  
  echo "  Google OAuth credentials configured from SSM."
else
  echo "  Warning: Google OAuth credentials not found in SSM (/openclaw/google). Skipping gogcli auth setup."
fi

echo "  Go and gogcli installed successfully."

# ---------------------------------------------------------------------------
# 5. Install Node.js via NVM (as ubuntu)
# ---------------------------------------------------------------------------
echo "[5/9] Installing Node.js..."

sudo -u ubuntu bash << 'UBUNTU_SCRIPT'
set -e
cd ~

for i in 1 2 3; do
  curl -fsSo- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash && break
  echo "NVM install attempt $i/3 failed, retrying..."
  sleep 5
done

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

nvm install 22
nvm use 22
nvm alias default 22

if ! grep -q 'NVM_DIR' ~/.bashrc; then
  echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
  echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> ~/.bashrc
fi

npm config set registry https://registry.npmjs.org/
npm install -g openclaw@latest --timeout=300000 || {
  npm cache clean --force
  npm install -g openclaw@latest --timeout=300000
}
UBUNTU_SCRIPT

# ---------------------------------------------------------------------------
# 6. Configure AWS region for ubuntu
# ---------------------------------------------------------------------------
echo "[6/9] Configuring AWS for ubuntu..."
sudo -u ubuntu aws configure set region "$REGION"
sudo -u ubuntu aws configure set output json

# ---------------------------------------------------------------------------
# 7. Build openclaw.json — copy from repo, inject secrets
# ---------------------------------------------------------------------------
echo "[7/9] Configuring openclaw.json..."

sudo -u ubuntu mkdir -p /home/ubuntu/.openclaw

cp /home/ubuntu/openclaw-repo/openclaw.json /home/ubuntu/.openclaw/openclaw.json

# Determine actual UI root path (depends on installed node version)
NVM_DIR="/home/ubuntu/.nvm"
UI_ROOT_PATH=""
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
  NODE_VERSION=$(node --version 2>/dev/null | cut -d v -f 2 || echo "")
  if [ -n "$NODE_VERSION" ]; then
    UI_ROOT_PATH="/home/ubuntu/.nvm/versions/node/v${NODE_VERSION}/lib/node_modules/openclaw/dist/control-ui"
  fi
fi

python3 << PYEOF
import json, os

with open('/home/ubuntu/.openclaw/openclaw.json', 'r') as f:
    config = json.load(f)

# Gateway token
config.setdefault('gateway', {}).setdefault('auth', {})['token'] = os.environ.get('GATEWAY_TOKEN', '')

# Anthropic API key
config.setdefault('models', {}).setdefault('providers', {}).setdefault('anthropic', {})['apiKey'] = os.environ.get('ANTHROPIC_KEY', '')

# Discord token
config.setdefault('channels', {}).setdefault('discord', {})['token'] = os.environ.get('DISCORD_TOKEN', '')

# Bedrock base URL (region-specific)
region = os.environ.get('REGION', 'us-east-2')
bedrock = config.get('models', {}).get('providers', {}).get('amazon-bedrock', {})
if bedrock:
    bedrock['baseUrl'] = f'https://bedrock-runtime.{region}.amazonaws.com'

# UI root path
ui_root = os.environ.get('UI_ROOT_PATH', '')
if ui_root:
    config.setdefault('gateway', {}).setdefault('controlUi', {})['root'] = ui_root

with open('/home/ubuntu/.openclaw/openclaw.json', 'w') as f:
    json.dump(config, f, indent=2)

print('openclaw.json configured successfully.')
PYEOF

chmod 600 /home/ubuntu/.openclaw/openclaw.json
chown ubuntu:ubuntu /home/ubuntu/.openclaw/openclaw.json
chmod 755 /home/ubuntu/.openclaw
chown ubuntu:ubuntu /home/ubuntu/.openclaw

# ---------------------------------------------------------------------------
# 8. Copy .md workspace files from repo
# ---------------------------------------------------------------------------
echo "[8/9] Loading workspace .md files from repo..."

sudo -u ubuntu mkdir -p /home/ubuntu/.openclaw/workspace

for md_file in AGENTS.md SOUL.md TOOLS.md IDENTITY.md USER.md HEARTBEAT.md BOOTSTRAP.md MEMORY.md; do
  if [ -f "/home/ubuntu/openclaw-repo/$md_file" ]; then
    cp "/home/ubuntu/openclaw-repo/$md_file" "/home/ubuntu/.openclaw/workspace/$md_file"
    echo "  Copied $md_file"
  fi
done

chown -R ubuntu:ubuntu /home/ubuntu/.openclaw/workspace

# Also copy to the path openclaw expects for template resolution
sudo -u ubuntu mkdir -p /home/ubuntu/docs/reference/templates
for md_file in AGENTS.md SOUL.md TOOLS.md IDENTITY.md USER.md HEARTBEAT.md BOOTSTRAP.md MEMORY.md; do
  if [ -f "/home/ubuntu/openclaw-repo/$md_file" ]; then
    cp "/home/ubuntu/openclaw-repo/$md_file" "/home/ubuntu/docs/reference/templates/$md_file"
  fi
done
chown -R ubuntu:ubuntu /home/ubuntu/docs

# Import cron jobs if they exist
if [ -f "/home/ubuntu/openclaw-repo/cron-jobs.json" ]; then
  sudo -u ubuntu mkdir -p /home/ubuntu/.openclaw/cron
  cp /home/ubuntu/openclaw-repo/cron-jobs.json /home/ubuntu/.openclaw/cron/jobs.json
  chown ubuntu:ubuntu /home/ubuntu/.openclaw/cron/jobs.json
  echo "  Imported cron jobs from repo"
fi

# ---------------------------------------------------------------------------
# 9. Install systemd service
# ---------------------------------------------------------------------------
echo "[9/9] Installing openclaw systemd service..."

cat > /etc/systemd/system/openclaw.service << 'SVCEOF'
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=ubuntu
Environment=HOME=/home/ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/bin/bash -c 'source /home/ubuntu/.nvm/nvm.sh && exec openclaw gateway'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable openclaw
systemctl start openclaw

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 9.5. Install Google OAuth setup timer (runs 5min after boot)
# ---------------------------------------------------------------------------
echo "[9.5/10] Installing Google OAuth setup timer..."

cat > /etc/systemd/system/google-auth-setup.service << GOOGLEEOF
[Unit]
Description=Google OAuth Setup Check
After=openclaw.service
Requires=openclaw.service

[Service]
Type=oneshot
User=ubuntu
Environment=HOME=/home/ubuntu
Environment=GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
WorkingDirectory=/home/ubuntu
ExecStart=/bin/bash /opt/openclaw-scripts/google-auth-setup.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
GOOGLEEOF

cat > /etc/systemd/system/google-auth-setup.timer << 'TIMEREOF'
[Unit]
Description=Google OAuth Setup Check Timer
Requires=openclaw.service

[Timer]
OnBootSec=5min
Unit=google-auth-setup.service

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable google-auth-setup.timer
systemctl start google-auth-setup.timer

echo "  Google OAuth setup timer installed, enabled, and started"

# 10. Write access instructions
# ---------------------------------------------------------------------------
echo "[10/10] Writing access instructions..."

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" \
  http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")

cat > /home/ubuntu/ACCESS_INSTRUCTIONS.txt << INSTRUCTIONS
========================================
OpenClaw Access Guide
========================================

STEP 1: Port Forwarding (run on LOCAL computer)
aws ssm start-session \\
  --target $INSTANCE_ID \\
  --region $REGION \\
  --document-name AWS-StartPortForwardingSession \\
  --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'

STEP 2: Get Gateway Token
aws ssm get-parameter \\
  --name "/openclaw/gateway-token" \\
  --region $REGION \\
  --with-decryption \\
  --query 'Parameter.Value' \\
  --output text

STEP 3: Open Browser
http://localhost:18789/?token=$GATEWAY_TOKEN
========================================
INSTRUCTIONS

chown ubuntu:ubuntu /home/ubuntu/ACCESS_INSTRUCTIONS.txt

# ---------------------------------------------------------------------------
# Run setup.sh from openclaw-repo (installs skills, applies config)
# ---------------------------------------------------------------------------
echo "[Final] Running OpenClaw repository setup..."
if [ -f /opt/openclaw-repo/setup.sh ]; then
  bash /opt/openclaw-repo/setup.sh
else
  echo "⚠️  Warning: setup.sh not found in openclaw-repo, skipping"
fi

echo "=== userdata.sh complete: $(date) ==="
