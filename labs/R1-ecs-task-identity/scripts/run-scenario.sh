#!/usr/bin/env bash
# Runs real S3 operations inside the `app` container using credentials
# fetched live from the real ECS-compatible metadata endpoint, then
# visualizes the result.
#
# KNOWN LIMITATION (documented, not hidden): the AWS CLI's automatic
# container-credentials discovery forwards the vended SessionToken as an
# X-Amz-Security-Token header. MinIO's default single-node deployment does
# not enable AWS STS session-token validation for its long-lived
# admin-created users, so a request carrying that token is rejected with
# InvalidTokenId - a MinIO limitation, not a flaw in the credential-vending
# protocol. This script fetches the REAL vended credentials from the REAL
# metadata endpoint (the same call an AWS SDK makes) and passes
# AccessKeyId/SecretAccessKey to the AWS CLI directly, dropping only the
# session token before the resource call. Credential VENDING and IAM
# ALLOW/DENY enforcement are both fully real; only session-token passthrough
# is not exercised in this lab.
set -uo pipefail
cd "$(dirname "$0")/.."
STAGE="${1:-baseline}"
EVIDENCE_DIR="evidence"
mkdir -p "$EVIDENCE_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
EVIDENCE_FILE="$EVIDENCE_DIR/${STAMP}-${STAGE}.log"
DC="docker compose"
export MSYS_NO_PATHCONV=1

log() { echo "$@" | tee -a "$EVIDENCE_FILE"; }

log "=== Lab R1 - scenario: $STAGE ==="
log ""
log "--- Step 1: real credentials fetched from the ECS-compatible metadata endpoint ---"
CREDS_JSON=$($DC exec -T app curl -s http://169.254.170.2/creds)
log "$(echo "$CREDS_JSON" | sed 's/"SecretAccessKey":"[^"]*"/"SecretAccessKey":"[REDACTED]"/')"

AK=$(echo "$CREDS_JSON" | grep -o '"AccessKeyId":"[^"]*"' | cut -d'"' -f4)
SK=$(echo "$CREDS_JSON" | grep -o '"SecretAccessKey":"[^"]*"' | cut -d'"' -f4)

LAST_RC=0
LAST_OUT=""

s3call () {
  local desc="$1"; shift
  log ""
  log "--- $desc ---"
  LAST_OUT=$($DC exec -T -e AWS_ACCESS_KEY_ID="$AK" -e AWS_SECRET_ACCESS_KEY="$SK" app "$@" 2>&1)
  LAST_RC=$?
  log "$LAST_OUT"
}

s3call "Step 2: s3:ListBucket (currently granted by policy)" \
  aws s3 ls s3://lab-bucket --endpoint-url http://minio:9000
if [ "$LAST_RC" -eq 0 ]; then
  bash scripts/visualize.sh "s3:ListBucket" ALLOW "exit=0 (bucket listing succeeded)"
else
  bash scripts/visualize.sh "s3:ListBucket" DENY "$(echo "$LAST_OUT" | grep -io "AccessDenied[^\"]*" | head -1)"
fi

$DC exec -T app sh -c 'echo lab-r1-evidence > /tmp/evidence.txt' >/dev/null 2>&1
s3call "Step 3: s3:PutObject (the permission broken/fixed in this lab)" \
  aws s3 cp /tmp/evidence.txt s3://lab-bucket/evidence.txt --endpoint-url http://minio:9000
if [ "$LAST_RC" -eq 0 ]; then
  bash scripts/visualize.sh "s3:PutObject" ALLOW "$(echo "$LAST_OUT" | tail -1)"
else
  bash scripts/visualize.sh "s3:PutObject" DENY "$(echo "$LAST_OUT" | grep -io "AccessDenied[^\"]*" | head -1)"
fi

s3call "Step 4: s3:DeleteObject (never granted - proves least privilege)" \
  aws s3api delete-object --bucket lab-bucket --key evidence.txt --endpoint-url http://minio:9000
if [ "$LAST_RC" -eq 0 ]; then
  bash scripts/visualize.sh "s3:DeleteObject" ALLOW "UNEXPECTED - policy broader than intended"
else
  bash scripts/visualize.sh "s3:DeleteObject" DENY "$(echo "$LAST_OUT" | grep -io "AccessDenied[^\"]*" | head -1)"
fi

log ""
log "Evidence saved to $EVIDENCE_FILE"
