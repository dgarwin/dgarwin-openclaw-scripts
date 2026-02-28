#!/bin/bash
# backup-google-auth.sh - Export Google OAuth tokens to S3 for disaster recovery
# Run this manually after authenticating with Google services via gogcli

set -e

REGION="${AWS_REGION:-us-east-2}"
BUCKET="openclaw-state-backup"
KEYRING_DIR="$HOME/.local/share/keyrings"

echo "Backing up Google OAuth tokens to S3..."

if [ ! -d "$KEYRING_DIR" ]; then
  echo "No keyring directory found at $KEYRING_DIR"
  exit 1
fi

# Create tarball of keyring
BACKUP_FILE="/tmp/google-keyring-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$BACKUP_FILE" -C "$HOME/.local/share" keyrings/

# Upload to S3
aws s3 cp "$BACKUP_FILE" "s3://$BUCKET/google-keyring-latest.tar.gz" --region "$REGION"

echo "Backup complete: $BACKUP_FILE -> s3://$BUCKET/google-keyring-latest.tar.gz"
rm "$BACKUP_FILE"
