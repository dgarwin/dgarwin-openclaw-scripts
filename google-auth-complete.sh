#!/bin/bash
# google-auth-complete.sh - Complete Google OAuth by pasting redirect URL
# Usage: bash google-auth-complete.sh <account-email> '<redirect-url>'

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <account-email> '<redirect-url>'"
  echo "Example: $0 garwinopenclaw@gmail.com 'http://localhost/?code=...'"
  echo "Example: $0 davidgarwin@gmail.com 'http://localhost/?code=...'"
  exit 1
fi

ACCOUNT="$1"
REDIRECT_URL="$2"

export GOG_KEYRING_PASSWORD="openclaw-google-auth"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Determine services based on account
if [[ "$ACCOUNT" == "davidgarwin@gmail.com" ]]; then
  SERVICES="tasks"
else
  SERVICES="drive,docs,sheets,calendar,gmail"
fi

# Run the auth command and pipe in the redirect URL
echo "$REDIRECT_URL" | gog auth add "$ACCOUNT" --services "$SERVICES" --manual

if [ $? -eq 0 ]; then
  echo "✅ Google authentication successful for $ACCOUNT!"
  gog auth list
else
  echo "❌ Authentication failed for $ACCOUNT"
  exit 1
fi
