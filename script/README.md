# StableSwap Factory Deployment

Deploy StableSwapHooksFactory with the **same address across all chains** using CREATE2.

## Quick Start

### 1. Setup Account

Choose one of the following methods:

#### Option A: Keystore (Software Wallet)

```bash
cast wallet import myaccount --interactive
```

#### Option B: Ledger (Hardware Wallet)

```bash
# Connect your Ledger, unlock it, and open the Ethereum app
#o
forge script --ledger --sender 0xYourLedgerAddress
```

### 2. Configure Environment

Create `.env` in the project root:

```bash
# Network
RPC_URL=https://polygon-rpc.com
ETHERSCAN_API_KEY=your_api_key

# Factory Configuration (required)
POOL_MANAGER=0x...
FACTORY_OWNER=0x...
PROTOCOL_FEE_COLLECTOR=0x...
HOOK_FEE_COLLECTOR=0x...
```

### 3. Deploy Factory

#### Using Keystore

```bash
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --rpc-url $RPC_URL \
  --account myaccount \
  --sender 0xYourAddress \
  --broadcast \
  --verify
```

#### Using Ledger

```bash
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --rpc-url $RPC_URL \
  --ledger \
  --sender 0xYourLedgerAddress \
  --broadcast \
  --verify
```

### 4. Deploy on Multiple Chains

Deploy with the **same sender address** to get the **same factory address** everywhere:

```bash
# Polygon
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --rpc-url https://polygon-rpc.com \
  --account myaccount \
  --sender 0xYourAddr \
  --broadcast \
  --verify

# Base
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --rpc-url https://mainnet.base.org \
  --account myaccount \
  --sender 0xYourAddr \
  --broadcast \
  --verify

# Arbitrum
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --rpc-url https://arb1.arbitrum.io/rpc \
  --account myaccount \
  --sender 0xYourAddr \
  --broadcast \
  --verify
```

**Result**: Same factory address on all chains! 🎉

## Configuration

### Environment Variables

The deployment script reads configuration from `.env`:

```bash
# Required
RPC_URL=https://...                  # RPC endpoint for the target chain
ETHERSCAN_API_KEY=...                # Block explorer API key for verification

POOL_MANAGER=0x...                   # PoolManager address (see supported chains)
FACTORY_OWNER=0x...                  # Address that will own the factory
PROTOCOL_FEE_COLLECTOR=0x...         # Address for protocol fees
HOOK_FEE_COLLECTOR=0x...             # Address for hook fees
```

Note: `POOL_MANAGER` can be omitted if deploying to a supported chain - addresses are pre-configured in `ChainConfig.sol`.

### Supported Chains

PoolManager addresses are pre-configured in `ChainConfig.sol`:

**Mainnets**: 
- Ethereum (1): `0x000000000004444c5dc75cB358380D2e3dE08A90`
- Arbitrum (42161): `0x360e68faccca8ca495c1b759fd9eee466db9fb32`
- Optimism (10): `0x9a13f98cb987694c9f086b1f5eb990eea8264ec3`
- Base (8453): `0x498581ff718922c3f8e6a244956af099b2652b2b`
- Polygon (137): `0x67366782805870060151383f4bbff9dab53e5cd6`
- BSC (56): `0x28e2ea090877bf75740558f6bfb36a5ffee9e9df`
- Avalanche (43114): `0x06380c0e0912312b5150364b9dc4542ba0dbbc85`
- Celo (42220): `0x288dc841A52FCA2707c6947B3A777c5E56cd87BC`

**Testnets**: 
- Sepolia (11155111): `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`
- Base Sepolia (84532): `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408`
- Arbitrum Sepolia (421614): `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`

**Local**: Anvil (31337)

## Deployment Commands

### Basic Deployment

```bash
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --rpc-url $RPC_URL \
  --account <ACCOUNT_NAME> \
  --sender <ADDRESS> \
  --broadcast \
  --verify
```

### Simulate Before Deploy

Remove `--broadcast` to simulate without deploying:

```bash
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --rpc-url $RPC_URL \
  --account myaccount \
  --sender 0xYourAddr
```

### Compute Address Without Deploying

```bash
forge script script/DeployFactoryCreate2.s.sol:DeployFactoryCreate2 \
  --sig "computeAddress()" \
  --rpc-url $RPC_URL
```

## Troubleshooting

### Different addresses on different chains?

Ensure:
1. **Same sender address** on all chains
2. **Same constructor parameters** (from `.env`)
3. **Same salt** in `DeployFactoryCreate2.s.sol`

### Change the deployment salt

Edit `script/DeployFactoryCreate2.s.sol`:

```solidity
bytes32 public constant SALT = keccak256("StableSwapHooksFactory.v2");
```

### Missing environment variables?

The script will fail with clear error messages:

```
Error: PoolManager address not configured
Error: Factory owner not configured
Error: Protocol fee collector not configured
Error: Hook fee collector not configured
```

Make sure all required variables are set in `.env`.

### Verification failed?

Ensure `ETHERSCAN_API_KEY` is set in `.env` with the correct API key for your target chain:

- Ethereum: [etherscan.io/apis](https://etherscan.io/apis)
- Polygon: [polygonscan.com/apis](https://polygonscan.com/apis)
- Base: [basescan.org/apis](https://basescan.org/apis)
- Arbitrum: [arbiscan.io/apis](https://arbiscan.io/apis)


## Security Best Practices

### Production Deployments

1. **Use hardware wallets** (Ledger) for mainnet deployments
2. **Test on testnets first** with the same configuration
3. **Use multisig addresses** for `FACTORY_OWNER` in production
4. **Verify contracts** - always use `--verify` flag
5. **Simulate first** - run without `--broadcast` to review
6. **Verify address** - use `computeAddress()` before deploying
