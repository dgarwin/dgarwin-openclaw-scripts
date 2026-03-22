#!/bin/bash
# google-auth-setup.sh - One-time Google OAuth setup via Discord
# Runs 5 minutes after OpenClaw starts to initiate Google auth if needed

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

REGION="${AWS_REGION:-us-east-2}"

# Check if already authenticated
ALREADY_AUTHED=0
if gog auth list 2>/dev/null | grep -q "garwinopenclaw@gmail.com"; then
  ALREADY_AUTHED=$((ALREADY_AUTHED + 1))
fi
if gog auth list 2>/dev/null | grep -q "davidgarwin@gmail.com"; then
  ALREADY_AUTHED=$((ALREADY_AUTHED + 1))
fi

if [ "$ALREADY_AUTHED" -eq 2 ]; then
  echo "Google auth already configured for both accounts."
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

export GOG_KEYRING_PASSWORD=$(aws ssm get-parameter \
  --name "/openclaw/google-keyring" \
  --with-decryption \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text)

if [ -z "$GOG_KEYRING_PASSWORD" ]; then
  echo "ERROR: No google keyring pw found"
  exit 1
fi

# Function to send auth message for an account
send_auth_message() {
  local ACCOUNT=$1
  local SERVICES=$2
  local READONLY_FLAG=$3
  local DESCRIPTION=$4
  
  echo "Starting Google OAuth flow for $ACCOUNT..."
  
  if [ -n "$READONLY_FLAG" ]; then
    AUTH_OUTPUT=$(timeout 5s bash -c "gog auth add $ACCOUNT --services $SERVICES --readonly --manual --remote<<< \"\"" 2>&1 || true)
  else
    AUTH_OUTPUT=$(timeout 5s bash -c "gog auth add $ACCOUNT --services $SERVICES --manual --remote<<< \"\"" 2>&1 || true)
  fi
  
  AUTH_URL=$(echo "$AUTH_OUTPUT" | grep -oP 'https://accounts\.google\.com[^ ]+' | head -1)
  
  if [ -z "$AUTH_URL" ]; then
    echo "Failed to generate auth URL for $ACCOUNT"
    return 1
  fi
  
  MESSAGE="🔐 **Google OAuth Setup Required: $ACCOUNT**

$DESCRIPTION

**Step 1:** Visit the URL below

**Step 2:** After authorizing, copy the redirect URL from your browser.

**Step 3:** Send me the redirect URL and I'll complete the setup.
$AUTH_URL"
  
  export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
  openclaw message send --channel discord --target user:364155628756926466 --message "$MESSAGE"
  
  echo "✅ Auth URL sent to Discord for $ACCOUNT"
  echo "Auth URL: $AUTH_URL"
}

# Set up garwinopenclaw@gmail.com if needed
if ! gog auth list 2>/dev/null | grep -q "garwinopenclaw@gmail.com"; then
  send_auth_message "garwinopenclaw@gmail.com" "drive,docs,sheets,calendar,gmail" "" "New OpenClaw instance needs Google authentication."
fi

# Set up davidgarwin@gmail.com for tasks readonly if needed
if ! gog auth list 2>/dev/null | grep -q "davidgarwin@gmail.com"; then
  send_auth_message "davidgarwin@gmail.com" "tasks" "--readonly" "New OpenClaw instance needs Google Tasks authentication (read-only)."
fi
