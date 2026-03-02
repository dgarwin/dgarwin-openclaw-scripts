#!/bin/bash
# google-auth-complete.sh - Complete Google OAuth by pasting redirect URL
# Usage: bash google-auth-complete.sh '<redirect-url>'

if [ -z "$1" ]; then
  echo "Usage: $0 '<redirect-url>'"
  exit 1
fi

export GOG_KEYRING_PASSWORD="openclaw-google-auth"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Run the auth command and pipe in the redirect URL
echo "$1" | gog auth add garwinopenclaw@gmail.com --services user --manual

if [ $? -eq 0 ]; then
  echo "✅ Google authentication successful!"
  gog auth list
else
  echo "❌ Authentication failed"
  exit 1
fi
