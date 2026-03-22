#!/bin/bash
# google-auth-setup.sh - One-time Google OAuth setup

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

# Set up garwinopenclaw@gmail.com if needed
if ! gog auth list 2>/dev/null | grep -q "garwinopenclaw@gmail.com"; then
  gog auth add "garwinopenclaw@gmail.com" --services "drive,docs,sheets,calendar,gmail"  --step 1 --remote
fi

# Set up davidgarwin@gmail.com for tasks readonly if needed
if ! gog auth list 2>/dev/null | grep -q "davidgarwin@gmail.com"; then
  gog auth add "davidgarwin@gmail.com" --services "tasks" --readonly --step 1 --remote
fi
