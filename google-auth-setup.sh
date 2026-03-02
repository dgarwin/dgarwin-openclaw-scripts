#!/bin/bash
# google-auth-setup.sh - One-time Google OAuth setup via Discord
# Runs 5 minutes after OpenClaw starts to initiate Google auth if needed

export GOG_KEYRING_PASSWORD="openclaw-google-auth"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Check if already authenticated
if gog auth list 2>/dev/null | grep -q "garwinopenclaw@gmail.com"; then
  echo "Google auth already configured."
  exit 0
fi

# Start the manual auth and capture the URL (timeout after 5 seconds)
echo "Starting Google OAuth flow..."
AUTH_OUTPUT=$(timeout 5s bash -c 'gog auth add garwinopenclaw@gmail.com --services user --manual <<< ""' 2>&1 || true)

# Extract the authorization URL
AUTH_URL=$(echo "$AUTH_OUTPUT" | grep -oP 'https://accounts\.google\.com[^ ]+' | head -1)

if [ -z "$AUTH_URL" ]; then
  echo "Failed to generate auth URL. Output was:"
  echo "$AUTH_OUTPUT"
  exit 1
fi

# Create message for Discord
MESSAGE="🔐 **Google OAuth Setup Required**

New OpenClaw instance detected. Please complete Google authentication:

**Step 1:** Visit this URL:
$AUTH_URL

**Step 2:** After authorizing, you'll be redirected to a localhost URL that won't load. Copy the entire URL from your browser's address bar.

**Step 3:** Send me the redirect URL and I'll complete the setup for you.

This enables Google Drive, Docs, Gmail, and Calendar access."

echo "$MESSAGE"
echo ""
echo "Auth URL: $AUTH_URL"
