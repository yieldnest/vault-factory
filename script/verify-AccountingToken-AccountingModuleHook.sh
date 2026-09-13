#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLEX_STRATEGY_ROOT="${FLEX_STRATEGY_ROOT:-${ROOT_DIR}/lib/yieldnest-flex-strategy}"
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

RPC_URL="${ETH_RPC_URL:-${ETH_MAINNET_RPC_URL:-${MAINNET_RPC_URL:-}}}"

CHAIN_ID="${CHAIN_ID:-1}"
COMPILER_VERSION="${COMPILER_VERSION:-0.8.28}"
OPTIMIZER_RUNS="${OPTIMIZER_RUNS:-100}"
EVM_VERSION="${EVM_VERSION:-cancun}"
WATCH_FLAG=("--watch")
if [ "${VERIFY_WATCH:-true}" = "false" ]; then
  WATCH_FLAG=()
fi

ACCOUNTING_TOKEN_CONTRACT="src/AccountingToken.sol:AccountingToken"
ACCOUNTING_MODULE_HOOK_CONTRACT="src/hooks/AccountingModuleHook.sol:AccountingModuleHook"

for contract_path in "${ACCOUNTING_TOKEN_CONTRACT%%:*}" "${ACCOUNTING_MODULE_HOOK_CONTRACT%%:*}"; do
  if [ ! -f "${FLEX_STRATEGY_ROOT}/${contract_path}" ]; then
    echo "Missing ${FLEX_STRATEGY_ROOT}/${contract_path}"
    echo "Initialize/update submodules, then retry:"
    echo "  git submodule update --init --recursive lib/yieldnest-flex-strategy"
    exit 1
  fi
done

json_address() {
  local key="$1"
  jq -er --arg key "$key" '.[$key] // empty' "$DEPLOYMENT_FILE"
}

require_rpc() {
  if [ -z "${RPC_URL}" ]; then
    echo "ETH_RPC_URL, ETH_MAINNET_RPC_URL, or MAINNET_RPC_URL is required to derive ${1}"
    exit 1
  fi
}

proxy_implementation() {
  local proxy="$1"
  local slot="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
  local raw
  require_rpc "proxy implementation"
  raw="$(cast storage "$proxy" "$slot" --rpc-url "$RPC_URL")"
  raw="${raw#0x}"
  printf '0x%s\n' "${raw: -40}"
}

ACCOUNTING_TOKEN_PROXY="$(json_address accountingToken)"
ACCOUNTING_TOKEN_IMPL="${ACCOUNTING_TOKEN_IMPL:-$(json_address accountingTokenImplementation 2>/dev/null || true)}"
if [ -z "${ACCOUNTING_TOKEN_IMPL}" ]; then
  ACCOUNTING_TOKEN_IMPL="$(proxy_implementation "$ACCOUNTING_TOKEN_PROXY")"
fi

ACCOUNTING_TOKEN_TRACKED_ASSET="${ACCOUNTING_TOKEN_TRACKED_ASSET:-$(json_address baseAsset 2>/dev/null || true)}"
if [ -z "${ACCOUNTING_TOKEN_TRACKED_ASSET}" ]; then
  require_rpc "accounting token tracked asset"
  ACCOUNTING_TOKEN_TRACKED_ASSET="$(cast call "$ACCOUNTING_TOKEN_IMPL" "TRACKED_ASSET()(address)" --rpc-url "$RPC_URL")"
fi

ACCOUNTING_MODULE_HOOK="${ACCOUNTING_MODULE_HOOK:-$(json_address accountingModuleHook)}"
ACCOUNTING_MODULE_HOOK_VAULT="${ACCOUNTING_MODULE_HOOK_VAULT:-$(json_address accountingModuleHookVault 2>/dev/null || json_address flexStrategy)}"
ACCOUNTING_MODULE_HOOK_FLEX_STRATEGY="${ACCOUNTING_MODULE_HOOK_FLEX_STRATEGY:-$(json_address flexStrategy)}"

echo "Verifying AccountingToken implementation: ${ACCOUNTING_TOKEN_IMPL}"
forge verify-contract "${ACCOUNTING_TOKEN_IMPL}" \
  "${ACCOUNTING_TOKEN_CONTRACT}" \
  --root "${FLEX_STRATEGY_ROOT}" \
  --chain-id "${CHAIN_ID}" \
  --compiler-version "${COMPILER_VERSION}" \
  --optimizer-runs "${OPTIMIZER_RUNS}" \
  --evm-version "${EVM_VERSION}" \
  --etherscan-api-key "${ETHERSCAN_API_KEY}" \
  --constructor-args "$(cast abi-encode 'constructor(address)' "${ACCOUNTING_TOKEN_TRACKED_ASSET}")" \
  "${WATCH_FLAG[@]}"

echo "Verifying AccountingModuleHook: ${ACCOUNTING_MODULE_HOOK}"
forge verify-contract "${ACCOUNTING_MODULE_HOOK}" \
  "${ACCOUNTING_MODULE_HOOK_CONTRACT}" \
  --root "${FLEX_STRATEGY_ROOT}" \
  --chain-id "${CHAIN_ID}" \
  --compiler-version "${COMPILER_VERSION}" \
  --optimizer-runs "${OPTIMIZER_RUNS}" \
  --evm-version "${EVM_VERSION}" \
  --etherscan-api-key "${ETHERSCAN_API_KEY}" \
  --constructor-args "$(cast abi-encode 'constructor(address,address)' "${ACCOUNTING_MODULE_HOOK_VAULT}" "${ACCOUNTING_MODULE_HOOK_FLEX_STRATEGY}")" \
  "${WATCH_FLAG[@]}"
