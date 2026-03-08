#!/bin/bash
# google-auth-setup.sh - One-time Google OAuth setup via Discord
# Runs 5 minutes after OpenClaw starts to initiate Google auth if needed

export GOG_KEYRING_PASSWORD="openclaw-google-auth"
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

# Function to send auth message for an account
send_auth_message() {
  local ACCOUNT=$1
  local SERVICES=$2
  
  echo "Starting Google OAuth flow for $ACCOUNT..."
  AUTH_OUTPUT=$(timeout 5s bash -c "gog auth add $ACCOUNT --services $SERVICES --manual <<< \"\"" 2>&1 || true)
  
  AUTH_URL=$(echo "$AUTH_OUTPUT" | grep -oP 'https://accounts\.google\.com[^ ]+' | head -1)
  
  if [ -z "$AUTH_URL" ]; then
    echo "Failed to generate auth URL for $ACCOUNT"
    return 1
  fi
  
  MESSAGE="🔐 **Google OAuth Setup Required: $ACCOUNT**

New OpenClaw instance needs Google authentication.

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
  send_auth_message "garwinopenclaw@gmail.com" "drive,docs,sheets,calendar,gmail"
fi

# Set up davidgarwin@gmail.com for tasks readonly if needed
if ! gog auth list 2>/dev/null | grep -q "davidgarwin@gmail.com"; then
  # Note: Using full scope URL for read-only tasks access
  # The send_auth_message function will need to handle this differently
  echo "Starting Google OAuth flow for davidgarwin@gmail.com (tasks readonly)..."
  AUTH_OUTPUT=$(timeout 5s bash -c "gog auth add davidgarwin@gmail.com --scopes https://www.googleapis.com/auth/tasks.readonly --manual <<< \"\"" 2>&1 || true)
  
  AUTH_URL=$(echo "$AUTH_OUTPUT" | grep -oP 'https://accounts\.google\.com[^ ]+' | head -1)
  
  if [ -n "$AUTH_URL" ]; then
    MESSAGE="🔐 **Google OAuth Setup Required: davidgarwin@gmail.com (Read-Only Tasks)**

New OpenClaw instance needs Google Tasks authentication (read-only).

**Step 1:** Visit the URL below

**Step 2:** After authorizing, copy the redirect URL from your browser.

**Step 3:** Send me the redirect URL and I'll complete the setup.
$AUTH_URL"
    
    export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
    openclaw message send --channel discord --target user:364155628756926466 --message "$MESSAGE"
    
    echo "✅ Auth URL sent to Discord for davidgarwin@gmail.com"
    echo "Auth URL: $AUTH_URL"
  else
    echo "Failed to generate auth URL for davidgarwin@gmail.com"
  fi
fi
