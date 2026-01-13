# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

StableSwap Hooks is a Uniswap v4 hook implementation that brings Curve-style StableSwap AMM design to Uniswap v4. It enables efficient stablecoin/LST trading with minimal slippage using the StableSwap invariant.

## Build Commands

```shell
forge build           # Compile contracts
forge test            # Run all tests
forge test -vvv       # Run tests with verbose output
forge test --mt <test_name>  # Run specific test by name
forge test --mc <contract_name>  # Run tests in specific contract
forge fmt             # Format code
forge fmt --check     # Check formatting (used in CI)
forge snapshot        # Generate gas snapshots
```

## Architecture

### Contract Hierarchy (inheritance flows upward)

```
StableSwapHooks (main entry point, IUnlockCallback)
    └── Swap (beforeSwap hook, StableSwap pricing)
        └── Liquidity (ERC20 LP tokens, add/remove liquidity)
            └── Fees (three-tier fee system: LP, Hook, Protocol)
                └── Amp (amplification coefficient ramping)
                    └── Base (pool config, hook permissions, BaseHook)

StableSwapHooksFactory (Ownable, Pausable)
    └── Deploys hooks via CREATE2 with caller-provided bytecode
    └── Manages fee collectors (protocolFeeCollector, hookFeeCollector)
```

### Key Source Files

- `src/StableSwapHooks.sol` - Entry point, routes unlock callbacks to handlers
- `src/Swap.sol` - Implements `beforeSwap` with StableSwap math
- `src/Liquidity.sol` - LP token minting/burning, proportional deposits/withdrawals
- `src/Fees.sol` - Fee calculation and withdrawal logic
- `src/Amp.sol` - Amplification coefficient with time-based ramping
- `src/Base.sol` - Pool initialization, hook permissions, rate oracle config
- `src/libraries/StableSwapMath.sol` - Newton-Raphson invariant/reserve calculations
- `src/factories/StableSwapHooksFactory.sol` - CREATE2 factory, fee collector management

### Testing Structure

- `test/testUtils/StableSwapHooksBaseTest.sol` - Base test class with helper methods
- `test/testUtils/StableSwapHooksFactoryHarness.sol` - Factory harness with `mineSalt()` for tests
- `test/testUtils/ExternalContractsDeployer.sol` - Deploys PoolManager, Universal Router, Permit2
- `test/scenarios/` - Edge case and scenario tests
- Tests use `hooks` (2-currency pool) and `hooks3` (3-currency pool) fixtures
- Helper functions: `_addLiquidity()`, `_executeExactInputSwap()`, `_executeExactOutputSwap()`

### Testing Conventions

- Use `stdError` from `forge-std/StdError.sol` for Solidity panic errors:
  - `stdError.divisionError` - division/modulo by zero (0x12)
  - `stdError.arithmeticError` - overflow/underflow (0x11)
  - `stdError.indexOOBError` - array index out of bounds (0x32)
- Always expect specific errors in `vm.expectRevert()`, not just any revert

## Key Concepts

### StableSwap Invariant

The math uses Newton-Raphson iteration to solve:
```
A·n^n·Σx_i + D = A·D·n^n + D^(n+1)/(n^n·Πx_i)
```
- `A` = amplification coefficient (higher = more stable pricing around equilibrium)
- `D` = invariant value
- Implementation in `StableSwapMath.getInvariant()` and `getTargetReserves()`

### Fee System

Three-tier fees (all scaled by `FEE_PRECISION = 1e6`):
- LP fees: Accumulated in reserves, increase LP token value (immutable, set at deployment)
- Hook fees: Withdrawable to `factory.hookFeeCollector()` (percentage configurable)
- Protocol fees: Withdrawable to `factory.protocolFeeCollector()` (percentage configurable)

Admin functions on hooks use `onlyFactoryOwner` modifier (checks `factory.owner()`).

### Rate Oracles

Currencies can have custom rate oracles for non-1:1 assets (e.g., wstETH/WETH). Configure via `RateOracleConfig(oracle, selector)` at deployment.

### Hook Deployment

Hooks must be deployed via `StableSwapHooksFactory` to addresses encoding correct permission flags:
1. Factory constructor takes `creationCodeHash` for bytecode validation
2. Compute valid CREATE2 salt off-chain (required due to gas constraints)
3. `factory.deploy()` deploys with caller-provided `creationCode` (validated against hash)

### Off-chain Salt Mining

Salt mining is computationally intensive and must be done off-chain. Reference implementations:
- `script/hookMiner.demo.js` - JavaScript implementation using ethers.js (any keccak256 library works)
- `lib/uniswap-hooks/lib/v4-periphery/src/utils/HookMiner.sol` - Solidity reference

Run the JS demo (requires Deno and `forge build`):
```shell
deno run --allow-env=WS_NO_BUFFER_UTIL --allow-read=out/StableSwapHooks.sol/StableSwapHooks.json script/hookMiner.demo.js
```

For dApp integration, run mining server-side or in a Web Worker to avoid blocking the main thread.

## Dependencies (via remappings)

- `@uniswap/v4-core/` - Uniswap v4 protocol
- `@uniswap/v4-periphery/` - Router and utilities
- `uniswap-hooks/` - OpenZeppelin's BaseHook
- `@openzeppelin/contracts/` - Ownable, Pausable, ERC20, Create2
