#!/bin/bash
# Deploy StableSwapHooksFactory using CREATE2 for deterministic cross-chain addresses

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 -c <chain> --account <name> --sender <address> [options]"
    echo ""
    echo "Required:"
    echo "  -c, --chain <chain>              Chain ID or name"
    echo "  -a, --account <name>             Forge keystore account"
    echo "  -s, --sender <address>           Sender address"
    echo ""
    echo "Network:"
    echo "  -r, --rpc-url <url>              RPC URL (or use <CHAIN>_RPC_URL in .env)"
    echo ""
    echo "Configuration (required, can be in .env):"
    echo "  --pool-manager <address>         PoolManager address"
    echo "  --owner <address>                Factory owner"
    echo "  --protocol-collector <address>   Protocol fee collector"
    echo "  --hook-collector <address>       Hook fee collector"
    echo ""
    echo "Options:"
    echo "  -v, --verify                     Verify on block explorer"
    echo "      --simulate                   Dry run"
    echo "  -h, --help                       Show help"
    echo ""
    echo "Example:"
    echo "  $0 -c polygon --account newAccount --sender 0xa1b08Ea3F43c8B74464197CF2a3E8855Dedf240B --rpc-url https://1rpc.io/matic --verify"
    exit 1
}

CHAIN=""
RPC_URL=""
ACCOUNT=""
SENDER=""
POOL_MANAGER=""
FACTORY_OWNER=""
PROTOCOL_FEE_COLLECTOR=""
HOOK_FEE_COLLECTOR=""
VERIFY=true
SIMULATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--chain) CHAIN="$2"; shift 2 ;;
        -r|--rpc-url) RPC_URL="$2"; shift 2 ;;
        -a|--account) ACCOUNT="$2"; shift 2 ;;
        -s|--sender) SENDER="$2"; shift 2 ;;
        --pool-manager) POOL_MANAGER="$2"; shift 2 ;;
        --owner) FACTORY_OWNER="$2"; shift 2 ;;
        --protocol-collector) PROTOCOL_FEE_COLLECTOR="$2"; shift 2 ;;
        --hook-collector) HOOK_FEE_COLLECTOR="$2"; shift 2 ;;
        -v|--verify) VERIFY=true; shift ;;
        --simulate) SIMULATE=true; shift ;;
        -h|--help) usage ;;
        *) echo -e "${RED}Unknown: $1${NC}"; usage ;;
    esac
done

[ -z "$CHAIN" ] && { echo -e "${RED}Chain required${NC}"; usage; }
[ -z "$ACCOUNT" ] && { echo -e "${RED}Account required${NC}"; usage; }
[ -z "$SENDER" ] && { echo -e "${RED}Sender required${NC}"; usage; }

# Load .env if exists
[ -f .env ] && { set -a; source .env; set +a; }

# Get RPC URL
if [ -z "$RPC_URL" ]; then
    CHAIN_UPPER=$(echo "$CHAIN" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    RPC_VAR="${CHAIN_UPPER}_RPC_URL"
    RPC_URL="${!RPC_VAR}"
    [ -z "$RPC_URL" ] && { echo -e "${RED}RPC required: --rpc-url or ${RPC_VAR}${NC}"; exit 1; }
fi

# Get config from args or env, args replace .env if provided
POOL_MANAGER="${POOL_MANAGER:-${POOL_MANAGER}}"
FACTORY_OWNER="${FACTORY_OWNER:-${FACTORY_OWNER}}"
PROTOCOL_FEE_COLLECTOR="${PROTOCOL_FEE_COLLECTOR:-${PROTOCOL_FEE_COLLECTOR}}"
HOOK_FEE_COLLECTOR="${HOOK_FEE_COLLECTOR:-${HOOK_FEE_COLLECTOR}}"

[ -z "$POOL_MANAGER" ] && { echo -e "${RED}Pool manager required: --pool-manager or POOL_MANAGER in .env${NC}"; exit 1; }
[ -z "$FACTORY_OWNER" ] && { echo -e "${RED}Owner required: --owner or FACTORY_OWNER in .env${NC}"; exit 1; }
[ -z "$PROTOCOL_FEE_COLLECTOR" ] && { echo -e "${RED}Protocol collector required${NC}"; exit 1; }
[ -z "$HOOK_FEE_COLLECTOR" ] && { echo -e "${RED}Hook collector required${NC}"; exit 1; }

# Export for forge
export POOL_MANAGER FACTORY_OWNER PROTOCOL_FEE_COLLECTOR HOOK_FEE_COLLECTOR

echo -e "${GREEN}Deploying StableSwapHooksFactory (CREATE2)${NC}"
echo "Chain: $CHAIN"
echo "RPC: $RPC_URL"
echo "Account: $ACCOUNT"
echo "Sender: $SENDER"
echo ""

FORGE_CMD="forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --rpc-url $RPC_URL \
  --account $ACCOUNT \
  --sender $SENDER"

[ "$SIMULATE" = false ] && FORGE_CMD="$FORGE_CMD --broadcast"
[ "$VERIFY" = true ] && FORGE_CMD="$FORGE_CMD --verify"

echo -e "${YELLOW}Executing...${NC}"
echo ""
eval $FORGE_CMD

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo -e "${YELLOW}Note: Same sender + same config = same address on all chains!${NC}"
    [ "$SIMULATE" = true ] && echo -e "${YELLOW}(Simulation - use without --simulate to deploy)${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
    exit 1
fi
