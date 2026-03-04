#!/bin/bash
# sync-memory.sh - Sync workspace .md files and cron jobs to git repo
set -e

WORKSPACE_DIR="/home/ubuntu/.openclaw/workspace"
REPO_DIR="/opt/openclaw-repo"
OPENCLAW_DIR="/home/ubuntu/.openclaw"

cd "$REPO_DIR"

# Copy updated .md files from workspace to repo
cp "$WORKSPACE_DIR"/*.md "$REPO_DIR/" 2>/dev/null || true

# Copy memory/ folder if it exists
cp "$WORKSPACE_DIR"/memory/*.md "$REPO_DIR/memory" 2>/dev/null || true

# Copy cron jobs
if [ -f "$OPENCLAW_DIR/cron/jobs.json" ]; then
  cp "$OPENCLAW_DIR/cron/jobs.json" "$REPO_DIR/cron-jobs.json"
fi

# Check if there are any changes
if git diff --quiet && git diff --cached --quiet; then
  echo "No changes to commit"
  exit 0
fi

# Commit and push changes
git add *.md cron-jobs.json memory/ 2>/dev/null || git add *.md cron-jobs.json
git commit -m "Auto-sync workspace memory files - $(date -u +%Y-%m-%d)"
git push

# Get gateway token from SSM
GATEWAY_TOKEN=$(aws ssm get-parameter \
  --name "/openclaw/gateway-token" \
  --with-decryption \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null)

if [ -z "$GATEWAY_TOKEN" ]; then
  echo "ERROR: No gateway token found"
  exit 1
fi

MESSAGE="Successfully pushed MD files and cron to git!"

export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
openclaw message send --channel discord --target user:364155628756926466 --message "$MESSAGE"


echo "MD files and cron jobs synced to GitHub"
