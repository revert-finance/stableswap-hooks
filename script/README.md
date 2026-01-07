# StableSwap Deployment Tools

Tooling for deploying and managing StableSwap hooks across multiple chains.

## Overview

- **Forge Scripts**: Solidity scripts for factory and hook deployment
- **TypeScript CLI**: Utilities for bytecode validation and chain management
- **Bash Wrappers**: User-friendly deployment scripts with multiple auth methods
- **Multi-Chain Support**: Pre-configured for Uniswap v4 compatible chains

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast)
- [Node.js](https://nodejs.org/) v18+ (for CLI tools)
- Account with ETH for gas on target chain
- Access to RPC endpoints

## Quick Start

### 1. Install Dependencies

```bash
# Install Forge dependencies
forge install

# Install CLI tools
cd script/tools
npm install
npm run build
cd ../..
```

### 2. Configure Environment

```bash
cp .env.deployment.example .env
# Edit .env with your configuration
```

Example `.env`:

```bash
# RPC URLs
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
BASE_RPC_URL=https://mainnet.base.org

# Factory Config
POOL_MANAGER=0x...
FACTORY_OWNER=0x...
PROTOCOL_FEE_COLLECTOR=0x...
HOOK_FEE_COLLECTOR=0x...

# Hook Config
FACTORY_ADDRESS=0x...
CURRENCIES=0xTokenA,0xTokenB
RATE_ORACLES=0x0,0x0
RATE_ORACLE_SELECTORS=0x00000000,0x00000000
LP_FEE_PERCENTAGE=300
BASE_AMP=100
```

### 3. Setup Keystore (Recommended)

Create an encrypted keystore for secure deployments:

```bash
# Create new keystore
cast wallet import myaccount --interactive

# List keystores
cast wallet list

# Use in deployment
./script/deploy-factory.sh -c sepolia --account myaccount --sender 0xYourAddress
```

### 4. Deploy

```bash
# Deploy factory
./script/deploy-factory.sh -c sepolia --account myaccount --sender 0xYourAddress -v

# Deploy hook
./script/deploy-hook.sh -c sepolia --account myaccount --sender 0xYourAddress -i
```

## Authentication Methods

### 1. Keystore (Recommended)

Most secure method using encrypted keystores:

```bash
# Create keystore
cast wallet import myaccount --interactive

# Deploy with keystore
./script/deploy-factory.sh -c sepolia \
  --account myaccount \
  --sender 0xYourAddress \
  -v
```

### 2. Interactive

Prompts for private key during deployment (not stored):

```bash
./script/deploy-factory.sh -c sepolia -v
# Will prompt: "Enter private key:"
```

### 3. Hardware Wallet

Use with Ledger/Trezor via forge:

```bash
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $SEPOLIA_RPC_URL \
  --ledger \
  --sender 0xYourAddress \
  --broadcast
```

## CLI Tools

### Installation

```bash
cd script/tools
npm install
npm run build
```

### Commands

#### Calculate Creation Code Hash

```bash
npm run cli bytecode-hash
```

Required when deploying factory.

#### List Supported Chains

```bash
npm run cli list-chains
npm run cli list-chains --mainnet
npm run cli list-chains --testnet
```

#### Validate Currency Addresses

```bash
npm run cli validate-currencies 0xTokenA 0xTokenB 0xTokenC
```

Currencies must be sorted in ascending order for Uniswap v4.

#### Sort Currency Addresses

```bash
npm run cli sort-currencies 0xTokenC 0xTokenA 0xTokenB
```

Outputs correctly sorted addresses for `.env` file.

#### Decode Hook Permissions

```bash
npm run cli hook-permissions 0xHookAddress
```

Shows which hook functions are enabled for an address.

#### Generate .env Template

```bash
npm run cli generate-env --chain sepolia
```

## Deployment Scripts

### Deploy Factory

```bash
./script/deploy-factory.sh -c <chain> [options]

Options:
  -c, --chain <chain>        Chain ID or name (required)
  -r, --rpc-url <url>        RPC URL (overrides .env)
  -a, --account <name>       Forge keystore account name
  -s, --sender <address>     Sender address (required with --account)
  -v, --verify               Verify contract on block explorer
  --simulate                 Simulate without broadcasting
```

**Required Environment Variables:**
- `POOL_MANAGER` (or use chain default)
- `FACTORY_OWNER`
- `PROTOCOL_FEE_COLLECTOR`
- `HOOK_FEE_COLLECTOR`

### Deploy Hook

```bash
./script/deploy-hook.sh -c <chain> [options]

Options:
  -c, --chain <chain>        Chain ID or name (required)
  -r, --rpc-url <url>        RPC URL (overrides .env)
  -a, --account <name>       Forge keystore account name
  -s, --sender <address>     Sender address (required with --account)
  -i, --initialize           Initialize pools after deployment
  --simulate                 Simulate without broadcasting
```

**Required Environment Variables:**
- `FACTORY_ADDRESS`
- `CURRENCIES` (comma-separated, sorted ascending)
- `RATE_ORACLES` (comma-separated)
- `RATE_ORACLE_SELECTORS` (comma-separated)
- `LP_FEE_PERCENTAGE`
- `BASE_AMP`

## Supported Chains

**Mainnets:**
- Ethereum (1)
- Arbitrum (42161)
- Optimism (10)
- Base (8453)
- Polygon (137)
- BSC (56)
- Avalanche (43114)
- Celo (42220)

**Testnets:**
- Sepolia (11155111)
- Base Sepolia (84532)
- Arbitrum Sepolia (421614)
- Optimism Sepolia (11155420)

**Local:**
- Anvil (31337)

## Examples

### Example 1: Factory Deployment

```bash
# 1. Configure .env
cat > .env << EOF
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
POOL_MANAGER=0xSepoliaPoolManager
FACTORY_OWNER=0xYourAddress
PROTOCOL_FEE_COLLECTOR=0xYourAddress
HOOK_FEE_COLLECTOR=0xYourAddress
EOF

# 2. Create keystore
cast wallet import myaccount --interactive

# 3. Deploy factory
./script/deploy-factory.sh -c sepolia \
  --account myaccount \
  --sender 0xYourAddress \
  -v
```

### Example 2: Two-Currency Stablecoin Pool

```bash
# 1. Validate and sort currencies
cd script/tools
npm run cli sort-currencies 0xUSDC 0xUSDT
cd ../..

# 2. Update .env
cat >> .env << EOF
FACTORY_ADDRESS=0xYourFactoryAddress
CURRENCIES=0xUSDC,0xUSDT
RATE_ORACLES=0x0,0x0
RATE_ORACLE_SELECTORS=0x00000000,0x00000000
LP_FEE_PERCENTAGE=300
BASE_AMP=100
EOF

# 3. Deploy hook with pool initialization
./script/deploy-hook.sh -c sepolia \
  --account myaccount \
  --sender 0xYourAddress \
  -i
```

### Example 3: Three-Currency LST Pool

```bash
# 1. Sort currencies
cd script/tools
npm run cli sort-currencies 0xWETH 0xstETH 0xwstETH
cd ../..

# 2. Configure with rate oracle for wstETH
cat >> .env << EOF
CURRENCIES=0xWETH,0xstETH,0xwstETH
RATE_ORACLES=0x0,0x0,0xWstETHOracle
RATE_ORACLE_SELECTORS=0x00000000,0x00000000,0x12345678
LP_FEE_PERCENTAGE=400
BASE_AMP=50
EOF

# 3. Simulate first to verify
./script/deploy-hook.sh -c ethereum \
  --account myaccount \
  --sender 0xYourAddress \
  --simulate

# 4. Deploy for real
./script/deploy-hook.sh -c ethereum \
  --account myaccount \
  --sender 0xYourAddress
```

## Troubleshooting

### "No RPC URL found"

Add RPC URL to `.env`:
```bash
<CHAIN_NAME>_RPC_URL=https://...
```

Check configured chains:
```bash
cd script/tools && npm run cli list-chains
```

### "Currencies are NOT sorted correctly"

Use CLI to sort:
```bash
cd script/tools
npm run cli sort-currencies 0xA 0xB 0xC
```

### "InvalidCreationCode" error

Recalculate creation code hash:
```bash
cd script/tools
npm run cli bytecode-hash
```

Deploy new factory with correct hash.

### Hook address permissions incorrect

The deployment script automatically mines a valid salt. If you see this error:
1. Verify factory was deployed with correct creation code hash
2. Check bytecode matches factory deployment

Verify permissions:
```bash
cd script/tools
npm run cli hook-permissions 0xHookAddress
```

### "Account not found"

List available keystores:
```bash
cast wallet list
```

Create new keystore:
```bash
cast wallet import myaccount --interactive
```

## Advanced Usage

### Direct Forge Script Usage

For more control, call forge directly:

```bash
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $SEPOLIA_RPC_URL \
  --account myaccount \
  --sender 0xYourAddress \
  --broadcast \
  --verify
```

### Custom Amplification Ramping

After deployment, the factory owner can ramp amplification:

```bash
cast send $HOOK_ADDRESS \
  "rampAmp(uint256,uint256)" \
  200 $(($(date +%s) + 86400)) \
  --rpc-url $RPC_URL \
  --account myaccount
```

### Update Fee Percentages

Factory owner can update fees:

```bash
# Protocol fee (10% of LP fees)
cast send $HOOK_ADDRESS \
  "setProtocolFeePercentage(uint256)" \
  100000 \
  --rpc-url $RPC_URL \
  --account myaccount

# Hook fee (20% of LP fees)
cast send $HOOK_ADDRESS \
  "setHookFeePercentage(uint256)" \
  200000 \
  --rpc-url $RPC_URL \
  --account myaccount
```

## Security Best Practices

1. **Never commit private keys** - Use keystore or interactive mode
2. **Test on testnets first** - Deploy to Sepolia/Base Sepolia before mainnet
3. **Simulate transactions** - Use `--simulate` flag to verify before broadcasting
4. **Verify contracts** - Always use `-v` flag to verify on block explorers
5. **Use multisig for production** - Set factory owner to a multisig address
6. **Audit rate oracles** - Review custom oracle contracts before using

## Adding New Chains

To add support for a new chain:

1. **Update `script/config/ChainConfig.sol`:**

```solidity
function _yourChain() private pure returns (Config memory) {
    return Config({
        chainId: YOUR_CHAIN_ID,
        name: "your-chain",
        poolManager: address(0),
        testnet: false
    });
}

// Add to getConfig():
if (chainId == YOUR_CHAIN_ID) return _yourChain();

// Add to isSupported():
|| chainId == YOUR_CHAIN_ID
```

2. **Update `script/tools/src/types.ts`:**

```typescript
YOUR_CHAIN_ID: {
  chainId: YOUR_CHAIN_ID,
  name: "your-chain",
  testnet: false
},
```

3. **Add RPC URL to `.env`:**

```bash
YOUR_CHAIN_RPC_URL=https://...
```

## Additional Resources

- [Uniswap v4 Documentation](https://docs.uniswap.org/contracts/v4/overview)
- [Foundry Book](https://book.getfoundry.sh/)
- [Cast Wallet Guide](https://book.getfoundry.sh/reference/cast/cast-wallet)
- [Project README](../README.md)
