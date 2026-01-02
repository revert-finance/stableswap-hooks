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
- `n` = Number of tokens (2-4 supported)
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

- Proportional deposits across all currencies
- LP tokens (`SSLP`) representing pool shares
- Slippage protection via `_minShares` (deposits) and `_minAmounts[]` (withdrawals)
- Liquidity operations routed through the hook (direct PoolManager access blocked)
- Only proportional amounts are pulled; excess approval is unused

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

### Multi-Currency Support

The pool supports 2-4 currencies with automatic pairwise pool initialization:

- All pairwise combinations are initialized on deployment
- Currencies must be sorted in ascending order by address
- Swaps between any two supported currencies use the StableSwap invariant

### Dynamic Rate Oracles

Each currency can have a custom rate oracle to define non-1:1 balance rates for LSTs like wstETH (e.g., 1 wstETH = ~1.22 WETH):

- Configure via `RateOracleConfig(oracle, selector)` at deployment
- Use `address(0)` for static rates
- **wstETH example** (mainnet): oracle = [`0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0`](https://etherscan.io/token/0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0), selector = `0x035faf82` (`stEthPerToken()`)

## Usage

### Deployment & Initialization

The hook must be deployed to an address that encodes the correct permission flags. Use `HookMiner` to find a valid salt:

```solidity
// 1. Prepare currencies (must be sorted by address in ascending uint160 order)
Currency[] memory currencies = new Currency[](2);
currencies[0] = currency0;
currencies[1] = currency1;

// 2. Configure rate oracles (use address(0) for static rates)
RateOracleConfig[] memory rateOracles = new RateOracleConfig[](2);
rateOracles[0] = RateOracleConfig(address(0), bytes4(0)); // Static rate
rateOracles[1] = RateOracleConfig(address(0), bytes4(0)); // Static rate

// 3. Deploy the hook with CREATE2 to a valid hook address
StableSwapHooks hook = new StableSwapHooks{salt: salt}(
    poolManager,
    currencies,
    rateOracles,
    protocolFeeCollector,
    protocolFeePercentage,   // e.g., 500 = 0.05%
    hookFeePercentage,       // e.g., 1000 = 0.1%
    lpFeePercentage,         // e.g., 3000 = 0.3%
    amplificationCoefficient // e.g., 100
);

// Note: All pairwise pools are automatically initialized by the constructor
```

**WETH/wstETH example** (mainnet):

```solidity
Currency[] memory currencies = new Currency[](2);
currencies[0] = Currency.wrap(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0); // wstETH
currencies[1] = Currency.wrap(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH

RateOracleConfig[] memory rateOracles = new RateOracleConfig[](2);
rateOracles[0] = RateOracleConfig(
    0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, // wstETH contract
    0x035faf82                                  // stEthPerToken()
);
rateOracles[1] = RateOracleConfig(address(0), bytes4(0)); // WETH: static rate

StableSwapHooks hook = new StableSwapHooks{salt: salt}(
    poolManager,
    currencies,
    rateOracles,
    protocolFeeCollector,
    500,  // 0.05% protocol fee
    1000, // 0.1% hook fee
    300,  // 0.03% LP fee
    100   // A = 100
);
```

### Adding Liquidity

```solidity
// Approve tokens first
token0.approve(address(hook), amount0);
token1.approve(address(hook), amount1);

// Prepare amounts array
uint256[] memory amounts = new uint256[](2);
amounts[0] = amount0;
amounts[1] = amount1;

// Add liquidity with slippage protection
hook.addLiquidity(amounts, minShares);
```

> **Note:** Only proportional amounts are pulled from the user. Unused approval remains. Some tokens like USDT require resetting approval to 0 before approving again.

### Removing Liquidity

```solidity
// Prepare minimum amounts array
uint256[] memory minAmounts = new uint256[](2);
minAmounts[0] = minAmount0;
minAmounts[1] = minAmount1;

// Burn LP shares and receive tokens proportionally
hook.removeLiquidity(shares, minAmounts);
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

## External Functions

### User Functions

| Function                                                  | Description                                         |
| --------------------------------------------------------- | --------------------------------------------------- |
| `addLiquidity(uint256[] _amounts, uint256 _minShares)`    | Deposit tokens proportionally and receive LP shares |
| `removeLiquidity(uint256 _shares, uint256[] _minAmounts)` | Burn LP shares and withdraw proportional tokens     |
| `withdrawProtocolFees()`                                  | Send accumulated protocol fees to collector address |

### Admin Functions (DEFAULT_ADMIN_ROLE)

| Function                            | Description                                   |
| ----------------------------------- | --------------------------------------------- |
| `setProtocolFeeCollector(address)`  | Update protocol fee recipient address         |
| `setProtocolFeePercentage(uint256)` | Update protocol fee (scaled by 1e6)           |
| `setHookFeePercentage(uint256)`     | Update hook fee (scaled by 1e6)               |
| `setLpFeePercentage(uint256)`       | Update LP fee (scaled by 1e6)                 |
| `startAmpRamp(uint256, uint256)`    | Begin gradual A coefficient change            |
| `stopAmpRamp()`                     | Emergency stop current A coefficient ramp     |
| `withdrawHookFees(address)`         | Withdraw accumulated hook fees to beneficiary |

### View Functions

| Function                                      | Description                          |
| --------------------------------------------- | ------------------------------------ |
| `getCurrencyIndex(Currency)`                  | Get index of a currency in the pool  |
| `currencies(uint256)`                         | Get currency address at index        |
| `reserves(uint256)`                           | Get current reserve for a currency   |
| `rates(uint256)`                              | Get base scaling rate for a currency |
| `protocolFees(uint256)` / `hookFees(uint256)` | Get accumulated fees per currency    |

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
