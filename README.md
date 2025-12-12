# StableSwap Hooks

A Uniswap v4 hook implementation that brings the [StableSwap (Curve)](https://curve.fi/) AMM design to the Uniswap v4 ecosystem. This enables efficient stablecoin trading with minimal slippage using the StableSwap invariant.

## Overview

Unlike Uniswap's constant-product formula (`x*y=k`), StableSwap uses a hybrid invariant that operates like constant-sum at equilibrium but transitions toward constant-product when imbalanced. This provides:

- **100-1000x lower slippage** for stablecoin pairs
- **Efficient cross-market trading** without intermediaries or order books
- **Composability** with the Uniswap v4 ecosystem

### The StableSwap Invariant

```
A·n^n·Σx_i + D = A·D·n^n + D^(n+1)/(n^n·Πx_i)
```

Where:

- `A` = Amplification coefficient (controls price curve steepness)
- `n` = Number of tokens (2 for this implementation)
- `D` = Invariant value
- `Σx_i` = Sum of reserves
- `Πx_i` = Product of reserves

## Architecture

```
src/
├── StableSwapHooks.sol      # Main entry point & unlock callback handler
├── Base.sol                 # Pool configuration & hook permissions
├── Swap.sol                 # Swap execution using StableSwap math
├── Liquidity.sol            # LP token & liquidity management (ERC20)
├── Fees.sol                 # Three-tier fee collection & distribution
├── Amp.sol                  # Amplification coefficient management
└── libraries/
    ├── StableSwapMath.sol   # Core mathematical operations
    └── Actions.sol          # Action type identifiers
```

### Contract Hierarchy

```
StableSwapHooks
    └── Swap
        └── Liquidity (ERC20)
            └── Fees
                └── Amp
                    └── Base
                        └── BaseHook (OpenZeppelin)
```

## Features

### Swaps

- Exact input and exact output modes
- Bidirectional swaps (token0 ↔ token1)
- Minimal slippage for similarly-priced assets
- Fee deduction from output (exact input) or added to input (exact output)

### Liquidity Management

- Proportional or single-sided deposits
- LP tokens (`SSLP`) representing pool shares
- Slippage protection via `minShares`, `minAmount0`, `minAmount1` parameters
- Liquidity operations routed through the hook (direct PoolManager access blocked)

### Three-Tier Fee System

| Fee Type      | Recipient           | Description                                       |
| ------------- | ------------------- | ------------------------------------------------- |
| LP Fees       | Liquidity Providers | Accumulated in reserves, increases LP token value |
| Hook Fees     | Hook Operator       | Withdrawable to admin-designated address          |
| Protocol Fees | Protocol Treasury   | Withdrawable to configured collector address      |

All fees use `FEE_PRECISION = 1e6` (100% = 1,000,000). Total fees cannot exceed 100%.

### Amplification Coefficient

The `A` parameter controls pool behavior:

- **Low A (1-10)**: More like constant-product (Uniswap-style)
- **High A (100-1000)**: More like constant-sum (stablecoin-optimized)

Safety mechanisms:

- Changes must be ramped over minimum 1 day
- Maximum 10x change per ramp
- Linear interpolation for smooth transitions
- Admin can stop ramp if needed

> **Why ramping?** Instant `A` changes could be exploited via sandwich attacks or LP value extraction. Gradual ramping gives LPs time to react and withdraw if they disagree, prevents arbitrageable price discontinuities, and ensures predictable pool behavior at every block.

## Usage

### Deployment & Initialization

The hook must be deployed to an address that encodes the correct permission flags. Use `HookMiner` to find a valid salt:

```solidity
// 1. Deploy the hook with CREATE2 to a valid hook address
StableSwapHooks hook = new StableSwapHooks{salt: salt}(
    poolManager,
    currency0,
    currency1,
    protocolFeeCollector,
    protocolFeePercentage,   // e.g., 500 = 0.05%
    hookFeePercentage,       // e.g., 1000 = 0.1%
    lpFeePercentage,         // e.g., 3000 = 0.3%
    amplificationCoefficient // e.g., 100
);

// 2. Initialize the pool with the hook
PoolKey memory poolKey = PoolKey({
    currency0: currency0,
    currency1: currency1,
    fee: lpFeePercentage,
    tickSpacing: 1,
    hooks: IHooks(address(hook))
});

poolManager.initialize(poolKey, SQRT_PRICE_1_1); // 1:1 price = 1 << 96
```

### Adding Liquidity

```solidity
// Approve tokens first
token0.approve(address(hook), amount0);
token1.approve(address(hook), amount1);

// Add liquidity with slippage protection
uint256 shares = hook.addLiquidity(amount0, amount1, minShares);
```

### Removing Liquidity

```solidity
// Burn LP shares and receive tokens
(uint256 received0, uint256 received1) = hook.removeLiquidity(
    shares,
    minAmount0,
    minAmount1
);
```

### Swapping

Swaps are executed through the [Universal Router](https://docs.uniswap.org/contracts/universal-router/overview). The hook intercepts swaps via `beforeSwap` and applies StableSwap pricing.

```solidity
// Swap 1000 USDC for USDT with 0.1% slippage tolerance (pseudocode)
universalRouter.execute(
    V4_SWAP,
    ExactInputSingleParams({
        poolKey: poolKey,
        zeroForOne: true,
        amountIn: 1000e6,
        amountOutMinimum: 999e6
    })
);
```

### Admin Functions

```solidity
// Fee management
hook.setLpFeePercentage(3000);           // 0.3%
hook.setHookFeePercentage(1000);         // 0.1%
hook.setProtocolFeePercentage(500);      // 0.05%
hook.setProtocolFeeCollector(treasury);

// Withdraw accumulated fees
hook.withdrawProtocolFees();
hook.withdrawHookFees(beneficiary);

// Amplification adjustment
hook.startAmpRamp(newAmp, block.timestamp + 7 days);
hook.stopAmpRamp();  // Emergency stop
```

## Hook Permissions

| Hook                  | Enabled | Purpose                            |
| --------------------- | ------- | ---------------------------------- |
| beforeInitialize      | Yes     | Validate pool configuration        |
| beforeAddLiquidity    | Yes     | Block direct PoolManager liquidity |
| beforeRemoveLiquidity | Yes     | Block direct PoolManager liquidity |
| beforeSwap            | Yes     | Execute StableSwap pricing logic   |
| beforeDonate          | Yes     | Block donations                    |

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity 0.8.30+

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

## Dependencies

- [@uniswap/v4-core](https://github.com/Uniswap/v4-core) - Uniswap v4 protocol
- [@uniswap/v4-periphery](https://github.com/Uniswap/v4-periphery) - Router and utilities
- [uniswap-hooks](https://github.com/OpenZeppelin/uniswap-hooks) - OpenZeppelin's BaseHook
- [@openzeppelin/contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - AccessControl, ERC20

## References

- [StableSwap Whitepaper](https://curve.fi/files/stableswap-paper.pdf)
- [Uniswap v4 Documentation](https://docs.uniswap.org/)
- [Curve Finance](https://curve.fi/)

## License

See [LICENSE](LICENSE) for details.
