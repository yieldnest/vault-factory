#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ -f ".env" ]; then
  set -a
  # shellcheck disable=SC1091
  source ".env"
  set +a
fi

if [ -f "../yieldnest-vault/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "../yieldnest-vault/.env"
  set +a
fi

if [ -z "${ETHERSCAN_API_KEY:-}" ]; then
  echo "ETHERSCAN_API_KEY is required"
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <deployment-json>"
  echo "Example: CHAIN_ID=1 $0 deployments/rwa-vault-1.json"
  exit 1
fi

DEPLOYMENT_FILE="$1"
if [ ! -f "${DEPLOYMENT_FILE}" ]; then
  echo "Deployment file not found: ${DEPLOYMENT_FILE}"
  exit 1
fi

CHAIN_ID="${CHAIN_ID:-1}"
COMPILER_VERSION="${COMPILER_VERSION:-0.8.30}"
OPTIMIZER_RUNS="${OPTIMIZER_RUNS:-200}"
EVM_VERSION="${EVM_VERSION:-cancun}"
WATCH_FLAG=("--watch")
if [ "${VERIFY_WATCH:-true}" = "false" ]; then
  WATCH_FLAG=()
fi

TIMELOCK_CONTRACT="lib/yieldnest-vault/lib/openzeppelin-contracts/contracts/governance/TimelockController.sol:TimelockController"
DEFAULT_CONTROLLER="0x0e46F77dbe0b6e9782bDe5596cdAb025C222cC5d"

json_address() {
  local key="$1"
  jq -er --arg key "$key" '.[$key] // empty' "$DEPLOYMENT_FILE"
}

TIMELOCK="${TIMELOCK:-$(json_address timelock)}"
TIMELOCK_ADMIN="${TIMELOCK_ADMIN:-${DEFAULT_CONTROLLER}}"
TIMELOCK_PROPOSER="${TIMELOCK_PROPOSER:-${DEFAULT_CONTROLLER}}"
TIMELOCK_MIN_DELAY="${TIMELOCK_MIN_DELAY:-15}"

PROPOSERS="[${TIMELOCK_PROPOSER},${TIMELOCK_ADMIN}]"
EXECUTORS="[${TIMELOCK_PROPOSER},${TIMELOCK_ADMIN}]"

echo "Verifying TimelockController: ${TIMELOCK}"
echo "  minDelay: ${TIMELOCK_MIN_DELAY}"
echo "  admin:    ${TIMELOCK_ADMIN}"
echo "  proposer: ${TIMELOCK_PROPOSER}"

forge verify-contract "${TIMELOCK}" \
  "${TIMELOCK_CONTRACT}" \
  --chain-id "${CHAIN_ID}" \
  --compiler-version "${COMPILER_VERSION}" \
  --optimizer-runs "${OPTIMIZER_RUNS}" \
  --evm-version "${EVM_VERSION}" \
  --etherscan-api-key "${ETHERSCAN_API_KEY}" \
  --constructor-args "$(cast abi-encode 'constructor(uint256,address[],address[],address)' "${TIMELOCK_MIN_DELAY}" "${PROPOSERS}" "${EXECUTORS}" "${TIMELOCK_ADMIN}")" \
  "${WATCH_FLAG[@]}"
