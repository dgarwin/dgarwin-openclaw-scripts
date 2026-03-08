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

# Determine services/scopes based on account
if [[ "$ACCOUNT" == "davidgarwin@gmail.com" ]]; then
  # Use explicit scope for read-only tasks
  echo "$REDIRECT_URL" | gog auth add "$ACCOUNT" --scopes https://www.googleapis.com/auth/tasks.readonly --manual
else
  # Use service shortcuts for full access
  echo "$REDIRECT_URL" | gog auth add "$ACCOUNT" --services drive,docs,sheets,calendar,gmail --manual
fi

if [ $? -eq 0 ]; then
  echo "✅ Google authentication successful for $ACCOUNT!"
  gog auth list
else
  echo "❌ Authentication failed for $ACCOUNT"
  exit 1
fi
