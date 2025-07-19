#!/bin/bash
#
# Author: Fabio Grasso <fabio.grasso@okta.com>
# License: Apache-2.0
# Version: 1.0.0
# Description: Script to test a RADIUS authentication within the Okta RADIUS Agent,
#              using radclient CLI, and parsing the response to ask additional input
#              if requested by the RADIUS server (i.e. choose the MFA factor)
#
# Usage: ./test.sh
#
# -----------------------------------------------------------------------------

echo ""
echo "############################ RADIUS Test Client ##############################"
echo "#                                                                             #"
echo "# This script sends a RADIUS authentication request using radclient.          #"
echo "#                                                                             #"
echo "###############################################################################"
echo ""

# Set default parameters
"${RADIUS_SERVER:=okta-radius-agent}"
"${RADIUS_PORT:=1812}"
"${RADIUS_SECRET:=test123}"

# Prompt user
[ -f /tmp/.radius.env ] && source /tmp/.radius.env # Load cached values if available
: "${RADIUS_USERNAME:=testuser@atko.email}"
: "${RADIUS_PASSWORD:=testpassword}"

read -p "User-Name [$RADIUS_USERNAME]: " input
RADIUS_USERNAME=${input:-$RADIUS_USERNAME}

read -p "User-Password [$RADIUS_PASSWORD]: " input
RADIUS_PASSWORD=${input:-$RADIUS_PASSWORD}

RADIUS_USER_IP=$(curl -s http://checkip.amazonaws.com || echo "127.0.0.1")
read -p "IP Address (NAS-IP-Address) [$RADIUS_USER_IP]: " input
RADIUS_NAS_IP=${input:-$RADIUS_USER_IP}

# Save vars
cat <<EOF > /tmp/.radius.env
export RADIUS_USERNAME="$RADIUS_USERNAME"
export RADIUS_PASSWORD="$RADIUS_PASSWORD"
EOF

echo ""
echo "Sending RADIUS authentication request..."
echo ""

output=$(printf 'User-Name = "%s"
User-Password = "%s"
NAS-IP-Address = %s
' "$RADIUS_USERNAME" "$RADIUS_PASSWORD" "$RADIUS_NAS_IP" | \
  radclient -x "$RADIUS_SERVER:$RADIUS_PORT" auth "$RADIUS_SECRET")

echo -e "\n\033[1;36mRaw server response:\033[0m"
echo "$output"


# MFA Challenge loop
while echo "$output" | grep -q "Access-Challenge"; do
  echo ""
  echo -e "\n\033[1;36mOutcome:\033[0m Multi-factor challenge received."

  # Extract State
  STATE=$(echo "$output" | grep State | awk '{print $3}' | tail -n 1)

  # Extract Reply-Message (may span multiple lines)
  REPLY_MSG=$(echo "$output" | awk -F'Reply-Message = ' '/Reply-Message/ {gsub(/^"|"$/, "", $2); print $2}' | sed 's/\\n/\n/g') || true
  if [[ -n "$REPLY_MSG" ]]; then
    echo -e "\n\033[1;36mServer reply:\033[0m $REPLY_MSG\n"
  fi

  # Prompt user
  while true; do
    read -p "Enter your response based on the server's instructions: " MFA_RESPONSE
    if [[ -n "$MFA_RESPONSE" ]]; then
        break
    else
        echo "Response cannot be empty. Please try again."
    fi
  done

  echo ""
  echo "Sending RADIUS response with MFA input..."
  echo ""
  output=$(printf 'User-Name = "%s"
User-Password = "%s"
State = "%s"
NAS-IP-Address = %s
' "$RADIUS_USERNAME" "$MFA_RESPONSE" "$STATE" "$RADIUS_NAS_IP" | \
    radclient -x "$RADIUS_SERVER:$RADIUS_PORT" auth "$RADIUS_SECRET")
  echo -e "\n\033[1;36mRaw server response:\033[0m"
  echo "$output"
done

# Extract Reply-Message
REPLY_MSG=$(echo "$output" | awk -F'Reply-Message = ' '/Reply-Message/ {gsub(/^"|"$/, "", $2); print $2}' | sed 's/\\n/\n/g') || true

if [[ -n "$REPLY_MSG" ]]; then
  echo -e "\n\033[1;36mServer reply:\033[0m $REPLY_MSG"
  echo -ne "\n\033[1;36mFinal outcome:\033[0m "
  # Check final outcome
  if echo "$REPLY_MSG" | grep -qiE "authentication failed|access denied"; then
    echo -e "\033[1;31m❌ Authentication failed.\033[0m"
  elif echo "$REPLY_MSG" | grep -qi "welcome"; then
    echo -e "\033[1;32m✅ Authentication succeeded.\033[0m"
  else
    echo -e "\033[1;33m⚠️ Authentication outcome unclear.\033[0m"
  fi
else
  echo -e "\033[1;33m⚠️ No Reply-Message found in the response.\033[0m"
fi
echo ""
echo ""