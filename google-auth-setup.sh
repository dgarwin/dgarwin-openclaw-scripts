#!/bin/bash
# google-auth-setup.sh - One-time Google OAuth setup via Discord
# Runs 5 minutes after OpenClaw starts to initiate Google auth if needed

export GOG_KEYRING_PASSWORD="openclaw-google-auth"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

REGION="${AWS_REGION:-us-east-2}"

# Check if already authenticated
if gog auth list 2>/dev/null | grep -q "garwinopenclaw@gmail.com"; then
  echo "Google auth already configured."
  exit 0
fi

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

# Start the manual auth and capture the URL (timeout after 5 seconds)
echo "Starting Google OAuth flow..."
AUTH_OUTPUT=$(timeout 5s bash -c 'gog auth add garwinopenclaw@gmail.com --services user --manual <<< ""' 2>&1 || true)

# Extract the authorization URL
AUTH_URL=$(echo "$AUTH_OUTPUT" | grep -oP 'https://accounts\.google\.com[^ ]+' | head -1)

if [ -z "$AUTH_URL" ]; then
  echo "Failed to generate auth URL"
  exit 1
fi

# Create message for Discord
MESSAGE="🔐 **Google OAuth Setup Required**

New OpenClaw instance needs Google authentication.

**Step 1:** Visit this URL:
$AUTH_URL

**Step 2:** After authorizing, copy the redirect URL from your browser.

**Step 3:** Send me the redirect URL and I'll complete the setup."

# Send via openclaw CLI
export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
openclaw message send --channel discord --target user:364155628756926466 --message "$MESSAGE"

echo "✅ Auth URL sent to Discord"
echo "Auth URL: $AUTH_URL"
