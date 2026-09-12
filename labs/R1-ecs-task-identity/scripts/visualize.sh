#!/usr/bin/env bash
# Smallest-possible visual layer (built only after confirming no suitable
# existing tool exists — see labs/R1-ecs-task-identity/README.md "Reuse Audit").
# Prints an ANSI flow diagram of: Container -> Metadata Endpoint -> Task
# Credentials -> IAM Evaluation -> ALLOW/DENY -> AWS API result.
#
# Usage: visualize.sh "<action>" <ALLOW|DENY> "<detail>"

ACTION="$1"
RESULT="$2"
DETAIL="$3"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; DIM='\033[2m'; RESET='\033[0m'; BOLD='\033[1m'

echo ""
echo -e "${BOLD}  [Container: app]${RESET}"
echo -e "        |"
echo -e "        v"
echo -e "  ${CYAN}[Metadata Endpoint  169.254.170.2/v3/creds]${RESET}"
echo -e "        |"
echo -e "        v"
echo -e "  ${CYAN}[Task Credentials   TASKROLEACCESSKEY01]${RESET}"
echo -e "        |"
echo -e "        v"
echo -e "  ${YELLOW}[IAM Policy Evaluation: ${ACTION}]${RESET}"
echo -e "        |"
if [ "$RESULT" = "ALLOW" ]; then
  echo -e "        +----------------------+"
  echo -e "        |                      |"
  echo -e "        v                      v"
  echo -e "   ${GREEN}${BOLD}[ALLOW]${RESET}                  [DENY]"
  echo -e "        |"
  echo -e "        v"
  echo -e "  ${GREEN}[MinIO S3 API]${RESET}"
  echo -e "        |"
  echo -e "        v"
  echo -e "  ${GREEN}${BOLD}[SUCCESS]${RESET}  ${DIM}${DETAIL}${RESET}"
else
  echo -e "        +----------------------+"
  echo -e "        |                      |"
  echo -e "        v                      v"
  echo -e "     [ALLOW]                ${RED}${BOLD}[DENY]${RESET}"
  echo -e "                                |"
  echo -e "                                v"
  echo -e "                          ${RED}${BOLD}[AccessDenied]${RESET}  ${DIM}${DETAIL}${RESET}"
fi
echo ""
