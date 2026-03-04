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

echo "Memory files and cron jobs synced to GitHub"
