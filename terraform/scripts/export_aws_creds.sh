#!/bin/bash
# export_aws_creds.sh

# Usage: source ./scripts/export_aws_creds.sh terraform-user

PROFILE=${1:-default}
CREDS_FILE="$HOME/.aws/credentials"

if [[ ! -f "$CREDS_FILE" ]]; then
  echo "ERROR: $CREDS_FILE not found"
  exit 1
fi

# Parse the credentials file for the given profile
export AWS_ACCESS_KEY_ID=$(awk -v profile="[$PROFILE]" '
  $0 == profile { found=1; next }
  found && /^\[/ { found=0 }
  found && /aws_access_key_id/ { print $3 }
' "$CREDS_FILE")

export AWS_SECRET_ACCESS_KEY=$(awk -v profile="[$PROFILE]" '
  $0 == profile { found=1; next }
  found && /^\[/ { found=0 }
  found && /aws_secret_access_key/ { print $3 }
' "$CREDS_FILE")

export AWS_SESSION_TOKEN=$(awk -v profile="[$PROFILE]" '
  $0 == profile { found=1; next }
  found && /^\[/ { found=0 }
  found && /aws_session_token/ { print $3 }
' "$CREDS_FILE")

if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
  echo "ERROR: Profile [$PROFILE] not found or has no credentials"
  exit 1
fi

echo "Exported credentials for profile: $PROFILE"
echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:0:8}****"  # partial print for safety