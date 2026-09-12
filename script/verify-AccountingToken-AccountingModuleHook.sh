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
    echo "Missing ${contract_path}"
    echo "Initialize/update submodules, then retry:"
    echo "  git submodule update --init --recursive lib/yieldnest-flex-strategy"
    exit 1
  fi
done

ACCOUNTING_TOKEN_IMPL="${ACCOUNTING_TOKEN_IMPL:-0x24961c22b646a06b734107f65a9f5c078c10d761}"
ACCOUNTING_TOKEN_TRACKED_ASSET="${ACCOUNTING_TOKEN_TRACKED_ASSET:-0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48}"

ACCOUNTING_MODULE_HOOK="${ACCOUNTING_MODULE_HOOK:-0x183E0214a8545FD70885784fC5E9D4e7f4787386}"
ACCOUNTING_MODULE_HOOK_VAULT="${ACCOUNTING_MODULE_HOOK_VAULT:-0xd70b45f02ae3EAc4356faf363321Fdf219002828}"
ACCOUNTING_MODULE_HOOK_FLEX_STRATEGY="${ACCOUNTING_MODULE_HOOK_FLEX_STRATEGY:-0xd70b45f02ae3EAc4356faf363321Fdf219002828}"

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
