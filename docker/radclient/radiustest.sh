#!/bin/bash

echo ""
echo ""
echo "############################ RADIUS Test Client  ##############################"
echo "#                                                                             #"
echo "# This script will send a RADIUS authentication request using the radclient   #"
echo "# utility.                                                                    #"
echo "#                                                                             #"
echo "# Press Enter to use default values shown in [brackets].                      #"
echo "#                                                                             #"
echo "# To remove the cached parameters, delete the file /tmp/.radius.env           #"
echo "#                                                                             #"
echo "###############################################################################"
echo ""
echo ""

[ -f /tmp/.radius.env ] && source /tmp/.radius.env


# Use existing RADIUS_ env vars or fallback hardcoded defaults
: "${RADIUS_USERNAME:=testuser@atko.email}"
: "${RADIUS_PASSWORD:=testpassword}"
: "${RADIUS_SERVER_ADDRESS:=radius-agent}"
: "${RADIUS_SERVER_PORT:=1812}"
: "${RADIUS_SERVER_SECRET:=test123}"

# Prompt for user input with current RADIUS_ env vars as defaults
read -p "User-Name [$RADIUS_USERNAME]: " input
RADIUS_USERNAME=${input:-$RADIUS_USERNAME}

read -p "User-Password [$RADIUS_PASSWORD]: " input
RADIUS_PASSWORD=${input:-$RADIUS_PASSWORD}

read -p "Radius Server Address [$RADIUS_SERVER_ADDRESS]: " input
RADIUS_SERVER_ADDRESS=${input:-$RADIUS_SERVER_ADDRESS}

read -p "Radius Server Port [$RADIUS_SERVER_PORT]: " input
RADIUS_SERVER_PORT=${input:-$RADIUS_SERVER_PORT}

read -p "Radius Server Secret [$RADIUS_SERVER_SECRET]: " input
RADIUS_SERVER_SECRET=${input:-$RADIUS_SERVER_SECRET}

RADIUS_USER_IP=$(curl -s http://checkip.amazonaws.com)
# Alternative DEFAULT_LOCAL_IP=$(curl -s https://1.1.1.1/cdn-cgi/trace | grep '^ip=' | cut -d= -f2)
read -p "IP Address (NAS-IP-Address) [$RADIUS_USER_IP]: " input
RADIUS_NAS_IP=${input:-$RADIUS_USER_IP}

# Save variables to a file for later sourcing
cat <<EOF > /tmp/.radius.env
export RADIUS_USERNAME="$RADIUS_USERNAME"
export RADIUS_PASSWORD="$RADIUS_PASSWORD"
export RADIUS_SERVER_ADDRESS="$RADIUS_SERVER_ADDRESS"
export RADIUS_SERVER_PORT="$RADIUS_SERVER_PORT"
export RADIUS_SERVER_SECRET="$RADIUS_SERVER_SECRET"
EOF

echo ""
echo "Sending RADIUS authentication request..."
echo ""


# Send first request
output=$(printf 'User-Name = "%s"
User-Password = "%s"
NAS-IP-Address = %s
' "$RADIUS_USERNAME" "$RADIUS_PASSWORD" "$RADIUS_NAS_IP" | \
  docker-compose exec -T radclient radclient -x "$RADIUS_SERVER_ADDRESS:$RADIUS_SERVER_PORT" auth "$RADIUS_SERVER_SECRET")

# Show initial response
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
    docker-compose exec -T radclient radclient -x "$RADIUS_SERVER_ADDRESS:$RADIUS_SERVER_PORT" auth "$RADIUS_SERVER_SECRET")
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