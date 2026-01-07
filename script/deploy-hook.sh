#!/bin/bash
# Deploy StableSwapHooks via factory

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Display usage
usage() {
    echo "Usage: $0 -c <chain> [options]"
    echo ""
    echo "Options:"
    echo "  -c, --chain <chain>        Chain ID or name (required)"
    echo "  -r, --rpc-url <url>        RPC URL (overrides .env)"
    echo "  -a, --account <name>       Forge keystore account name"
    echo "  -s, --sender <address>     Sender address (required with --account)"
    echo "  -i, --initialize           Initialize pools after deployment"
    echo "  --simulate                 Simulate deployment without broadcasting"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Authentication (choose one):"
    echo "  1. Keystore: --account <name> --sender <address>"
    echo "  2. Interactive: Will prompt for private key"
    echo ""
    echo "Required environment variables in .env:"
    echo "  FACTORY_ADDRESS            StableSwapHooksFactory address"
    echo "  CURRENCIES                 Comma-separated currency addresses (sorted)"
    echo "  RATE_ORACLES               Comma-separated rate oracle addresses"
    echo "  RATE_ORACLE_SELECTORS      Comma-separated function selectors"
    echo "  LP_FEE_PERCENTAGE          LP fee percentage (e.g., 300 for 0.03%)"
    echo "  BASE_AMP                   Initial amplification coefficient"
    echo ""
    echo "Optional environment variables:"
    echo "  INITIALIZE_POOLS           Set to 'true' to initialize pools"
    echo "  SQRT_PRICE_X96             Initial sqrt price (default: 1<<96)"
    echo ""
    echo "Examples:"
    echo "  $0 -c sepolia --account myaccount --sender 0x123... -i"
    echo "  $0 -c base --simulate"
    exit 1
}

# Parse arguments
CHAIN=""
RPC_URL=""
ACCOUNT=""
SENDER=""
INITIALIZE=false
SIMULATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--chain)
            CHAIN="$2"
            shift 2
            ;;
        -r|--rpc-url)
            RPC_URL="$2"
            shift 2
            ;;
        -a|--account)
            ACCOUNT="$2"
            shift 2
            ;;
        -s|--sender)
            SENDER="$2"
            shift 2
            ;;
        -i|--initialize)
            INITIALIZE=true
            shift
            ;;
        --simulate)
            SIMULATE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$CHAIN" ]; then
    echo -e "${RED}Error: Chain is required${NC}"
    usage
fi

# Load .env file
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo -e "${YELLOW}Warning: .env file not found${NC}"
fi

# Validate required env vars
required_vars=("FACTORY_ADDRESS" "CURRENCIES" "RATE_ORACLES" "RATE_ORACLE_SELECTORS" "LP_FEE_PERCENTAGE" "BASE_AMP")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: $var not set in .env${NC}"
        exit 1
    fi
done

# Set initialize flag if -i option used
if [ "$INITIALIZE" = true ]; then
    export INITIALIZE_POOLS=true
fi

# Determine RPC URL
if [ -z "$RPC_URL" ]; then
    CHAIN_UPPER=$(echo "$CHAIN" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    RPC_VAR="${CHAIN_UPPER}_RPC_URL"
    RPC_URL="${!RPC_VAR}"

    if [ -z "$RPC_URL" ]; then
        echo -e "${RED}Error: No RPC URL found. Set ${RPC_VAR} in .env or use --rpc-url${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Deploying StableSwapHooks${NC}"
echo "Chain: $CHAIN"
echo "RPC URL: $RPC_URL"
echo "Factory: $FACTORY_ADDRESS"
echo "Currencies: $CURRENCIES"
echo "LP Fee: $LP_FEE_PERCENTAGE"
echo "Base Amp: $BASE_AMP"
echo "Initialize Pools: ${INITIALIZE_POOLS:-false}"
echo ""

# Build forge command
FORGE_CMD="forge script script/DeployHook.s.sol:DeployHook"
FORGE_CMD="$FORGE_CMD --rpc-url $RPC_URL"

# Add authentication
if [ -n "$ACCOUNT" ]; then
    if [ -z "$SENDER" ]; then
        echo -e "${RED}Error: --sender required when using --account${NC}"
        exit 1
    fi
    FORGE_CMD="$FORGE_CMD --account $ACCOUNT --sender $SENDER"
else
    FORGE_CMD="$FORGE_CMD --interactive"
fi

if [ "$SIMULATE" = false ]; then
    FORGE_CMD="$FORGE_CMD --broadcast"
fi

# Execute deployment
echo -e "${YELLOW}Running forge script...${NC}"
echo ""
eval $FORGE_CMD

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Deployment successful!${NC}"

    if [ "$SIMULATE" = true ]; then
        echo -e "${YELLOW}Note: This was a simulation. Remove --simulate to broadcast.${NC}"
    fi
else
    echo ""
    echo -e "${RED}✗ Deployment failed${NC}"
    exit 1
fi
