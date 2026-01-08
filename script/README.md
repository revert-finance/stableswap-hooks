# StableSwap Factory Deployment

Deploy StableSwapHooksFactory with the **same address across all chains** using CREATE2.

## Quick Start

### 1. Setup Keystore

```bash
cast wallet import myaccount --interactive
```

### 2. Deploy Factory

```bash
./script/deploy-factory.sh \
  -c polygon \
  --account myaccount \
  --sender 0x... \
  --rpc-url https://... \
  --verify
```

### 3. Deploy on Multiple Chains

Deploy with the **same account** to get the **same factory address** everywhere:

```bash
# Polygon
./script/deploy-factory.sh -c polygon --account myaccount --sender 0xYourAddr --rpc-url https://polygon-rpc.com -v

# Base
./script/deploy-factory.sh -c base --account myaccount --sender 0xYourAddr --rpc-url https://base-rpc.com -v

**Result**: Same factory address on all chains! 🎉

## Configuration Options

### Via Command Line

```bash
./script/deploy-factory.sh \
  -c <chain> \
  --account <keystore-name> \
  --sender <address> \
  --rpc-url <url> \
  --pool-manager <address> \
  --owner <address> \
  --protocol-collector <address> \
  --hook-collector <address> \
  --verify
```

### Via .env File

Create `.env` in the project root:

```bash
# RPC URLs
POLYGON_RPC_URL=https://...
BASE_RPC_URL=https://...
ARBITRUM_RPC_URL=https://...

# Factory Configuration
POOL_MANAGER=0x...
FACTORY_OWNER=0x...
PROTOCOL_FEE_COLLECTOR=0x...
HOOK_FEE_COLLECTOR=0x...
```

Then deploy:

```bash
./script/deploy-factory.sh -c polygon --account myaccount --sender 0xAddr -v
```

## Arguments

```
Required:
  -c, --chain <chain>              Chain ID or name
  -a, --account <name>             Keystore account
  -s, --sender <address>           Sender address

Network:
  -r, --rpc-url <url>              RPC URL (or <CHAIN>_RPC_URL in .env)

Configuration (can be in .env):
  --pool-manager <address>         PoolManager address
  --owner <address>                Factory owner
  --protocol-collector <address>   Protocol fee collector
  --hook-collector <address>       Hook fee collector

Options:
  -v, --verify                     Verify on block explorer
  --simulate                       Dry run without broadcasting
```


## Supported Chains

**Mainnets**: Ethereum (1), Arbitrum (42161), Optimism (10), Base (8453), Polygon (137), BSC (56), Avalanche (43114), Celo (42220)

**Testnets**: Sepolia (11155111), Base Sepolia (84532), Arbitrum Sepolia (421614), Optimism Sepolia (11155420)

**Local**: Anvil (31337)

## Examples

### Deploy on Testnets

```bash
# Sepolia
./script/deploy-factory.sh \
  -c sepolia \
  --account testaccount \
  --sender 0xYourAddress \
  --rpc-url https://sepolia.infura.io/v3/KEY \
  --pool-manager 0xSepoliaPoolManager \
  --owner 0xYourAddress \
  --protocol-collector 0xYourAddress \
  --hook-collector 0xYourAddress \
  -v
```

### Multi-Chain with .env

```bash
# .env
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/KEY
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
POOL_MANAGER=0xPoolManager
FACTORY_OWNER=0xYourAddress
PROTOCOL_FEE_COLLECTOR=0xYourAddress
HOOK_FEE_COLLECTOR=0xYourAddress

# Deploy on multiple chains
./script/deploy-factory.sh -c sepolia --account myaccount --sender 0xAddr -v
./script/deploy-factory.sh -c base-sepolia --account myaccount --sender 0xAddr -v
```

### Simulate Before Deploy

```bash
# Dry run
./script/deploy-factory.sh -c polygon --account myaccount --sender 0xAddr --simulate

# Review, then deploy
./script/deploy-factory.sh -c polygon --account myaccount --sender 0xAddr -v
```

## Troubleshooting

### Different addresses on different chains?

Ensure:
1. Same **sender address** on all chains
2. Same **constructor parameters** (PoolManager, owner, collectors)
3. Same **salt** in `DeployFactoryCreate2.s.sol`

### Change the deployment salt

Edit `script/DeployFactoryCreate2.s.sol`:

```solidity
bytes32 public constant SALT = keccak256("StableSwapHooksFactory.v2");
```

### Verify address before deploying

```bash
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --sig "computeAddress()" \
  --rpc-url $RPC_URL
```

## Direct Forge Usage

Skip the bash wrapper and call forge directly:

```bash
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --rpc-url https://polygon-rpc.com \
  --account myaccount \
  --sender 0xYourAddress \
  --broadcast \
  --verify
```

## Security

- **Keystore**: Use `cast wallet import` for encrypted key storage
- **Test first**: Deploy on testnets before mainnet
- **Multisig**: Use multisig address for factory owner in production
- **Verify**: Always use `--verify` flag

## Project Structure

```
script/
├── config/
│   └── ChainConfig.sol          # Chain configurations
├── DeployFactoryCreate2.s.sol   # CREATE2 deployment script
├── deploy-factory.sh            # Bash wrapper
└── README.md                    # This file
```
