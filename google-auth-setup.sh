#!/bin/bash
# google-auth-setup.sh - One-time Google OAuth setup prompt
# Runs after OpenClaw starts to check if Google auth is configured

export GOG_KEYRING_PASSWORD="openclaw-google-auth"

# Check if already authenticated
if /usr/local/bin/gog auth list 2>/dev/null | grep -q "garwinopenclaw@gmail.com"; then
  exit 0
fi

# Not authenticated - send prompt message
echo "Google authentication setup required for Drive/Docs/Gmail access."
echo "Run: gog auth add garwinopenclaw@gmail.com --services user --manual"
