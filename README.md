# StableSwap Hooks

## Table of Contents
- [Description](#description)
- [Important Usage Notes](#important-usage-notes)
- [Liquidity](#liquidity)
  - [Add liquidity](#add-liquidity)
  - [Remove liquidity](#remove-liquidity)
  - [Liquidity Token](#liquidity-token)
- [Stable Swaps](#stable-swaps)
  - [Swapping via Universal Router](#swapping-via-universal-router)
  - [Quoting swaps](#quoting-swaps)
  - [Fees](#fees)
- [Factory](#factory)
  - [Deploy the factory](#deploy-the-factory)
  - [Deploy new pools (hooks)](#deploy-new-pools-hooks)
  - [Off-chain salt mining](#off-chain-salt-mining)
- [Fees](#fees-1)
  - [Fee percentages](#fee-percentages)
  - [Fee withdrawal](#fee-withdrawal)
- [Amplification](#amplification)
  - [Ramping A](#ramping-a)
  - [Stopping a ramp](#stopping-a-ramp)
- [Development](#development)
  - [Project structure](#project-structure)
  - [Build and test](#build-and-test)
  - [Formatting](#formatting)
- [License](#license)

## Description
StableSwap Hooks is a Uniswap v4 hook implementation that brings Curve-style StableSwap AMM behavior to v4 pools. It targets stable assets (stablecoins, LSTs, etc.) to provide low-slippage swaps around the 1:1 price, while supporting configurable fees, rate oracles, and amplification (A) ramping.

The StableSwap invariant blends constant-sum and constant-product behavior with an amplification coefficient (A): near balance it behaves closer to constant-sum for tighter pricing, and as the pool becomes imbalanced it shifts toward constant-product to preserve liquidity. The benefit is concentrated liquidity around the peg without relying on external oracles for pricing, which improves capital efficiency for LPs and reduces price impact for traders.

## Important Usage Notes
Read these before deploying a pool. Ignoring them can lead to broken accounting or unexpected pricing.

- **Token decimals must be between 6 and 18 (inclusive).** Each token is normalized to 1e18 precision internally using a scaling rate of `10^(36 - decimals)`. Tokens with fewer than 6 or more than 18 decimals fall outside the tested range and will not behave as expected (loss of precision, or a revert during deployment for very high decimals). Do not use them.
- **Use A ≥ 10.** Using less than 10 discouraged: On tiny or heavily imbalanced pools it lets the fee round to zero, exposing dust-sized rounding leaks on round-trip swaps.
- **Rebasing tokens are not supported.** Reserves are tracked internally, so tokens that change balances via rebasing (for example stETH) will desync the pool's accounting from its actual balances. Use the wrapped, non-rebasing equivalent instead (for example wstETH, configured with a rate oracle).
- **Fee-on-transfer / deflationary tokens are not supported.** On deposits the pool credits reserves with the requested transfer amount, assuming the exact amount arrives. A token that takes a fee on transfer will desync accounting or revert on settlement. Do not use them.
- **Rate oracles must return a single `uint256` scaled to 18-decimal precision (`RATE_PRECISION = 1e18`).** The configured `(oracle, selector)` is `staticcall`ed and only the 32-byte return length is validated; a wrong return type or wrong scaling silently misprices the pool. Use a hardened accumulator-style rate source (for example `wstETH.stEthPerToken`), or wrap an existing oracle in a proxy contract that returns the expected format. A validly-scaled but near-zero effective rate (an asset priced far below the reference unit) reintroduces the dust-sized round-trip leak noted above for low A, so do not use an oracle that can return one.
- **Ramp A down gradually.** Swaps price against the live interpolated A, so ramping (rather than an instant change) stops a trader from front-running an A jump and round-tripping across it for profit. Gradual ramping does not remove this entirely; it dilutes it into small, arbitrage-competed steps, which matter most on downward ramps and on pools with little trading activity. Prefer a long ramp (a week or more rather than the 1-day minimum) and a small change (2x or 3x rather than 10x).
- **Bricking a pool.** Adding liquidity and swapping verify that reserves are priceable (the invariant solver converges) and revert otherwise. Changing A and removing liquidity skip that check, so on an already extremely imbalanced pool either can push reserves into a non-converging region, blocking swaps and adds. LPs are never locked in: `removeLiquidity` can still be used in this bricked state.

## Liquidity
Liquidity is pooled and represented by ERC20 LP tokens. The hook does not rely on Uniswap’s position manager or concentrated liquidity NFTs; it manages liquidity internally with Uniswap v2-style ERC20 LP tokens. Deposits and withdrawals are proportional across all pool assets; there is no range-based liquidity and no NFT positions.

### Add liquidity
Add liquidity uses the hook’s internal accounting and mints ERC20 LP tokens.

The first deposit consumes the provided amounts as-is and permanently locks `MINIMUM_LIQUIDITY` to `DEAD_ADDRESS` to prevent dust attacks and protect the pool from manipulation at very low total supply.

Subsequent deposits are taken proportionally to current reserves.

Approve each pool currency to the hook, then use `quoteAddLiquidity` to fetch slippage protection values and pass them into `addLiquidity`.

```solidity
uint256[] memory amounts = new uint256[](2);
amounts[0] = amount0;
amounts[1] = amount1;

// Quote expected shares and actual amounts used by the pool.
(uint256 expectedShares, uint256[] memory actualAmounts) = hooks.quoteAddLiquidity(amounts);

// Apply a slippage tolerance for minAmounts and minShares.
uint256[] memory minAmounts = new uint256[](2);
minAmounts[0] = actualAmounts[0] * 99 / 100; // 1% slippage
minAmounts[1] = actualAmounts[1] * 99 / 100;
uint256 minShares = expectedShares * 99 / 100;

hooks.addLiquidity(amounts, minAmounts, minShares);
```

For pools with native ETH, pass the ETH amount as `msg.value` and set the corresponding `amounts[]` entry to the same value: `hooks.addLiquidity{value: ethAmount}(amounts, ...)`. Excess ETH from proportional deposits is refunded automatically.

### Remove liquidity
Remove liquidity burns LP shares and returns proportional amounts of each currency.

Use `quoteRemoveLiquidity` to preview expected amounts, then pass minimums into `removeLiquidity` for slippage protection.

```solidity
uint256 shares = lpSharesToBurn;

uint256[] memory expectedAmounts = hooks.quoteRemoveLiquidity(shares);

uint256[] memory minAmounts = new uint256[](2);
minAmounts[0] = expectedAmounts[0] * 99 / 100; // 1% slippage
minAmounts[1] = expectedAmounts[1] * 99 / 100;

hooks.removeLiquidity(shares, minAmounts);
```

### Liquidity Token
The hook itself is an ERC20 that tracks the balance of liquidity tokens and exposes the full ERC20 interface (transfer, approve, allowance, and related functions).

## Stable Swaps
StableSwap replaces Uniswap v4's default AMM math with a StableSwap invariant. The hook overrides `beforeSwap` in `src/Swap.sol` to compute swap amounts using StableSwap math, then returns the delta to the pool manager so the swap settles with the hook's pricing.

### Swapping via Universal Router
Swaps should be executed through the v4 Universal Router (for example `@uniswap/v4-periphery`), using a `PoolKey` that includes the hook address and the LP fee encoded in `fee`.

This keeps the hook compatible with existing v4 routing, batching, and settlement flows while preserving standard slippage controls. Slippage protection is enforced by the router's `amountOutMinimum` (exact input) or `amountInMaximum` (exact output) parameters.

The action sequence uses `SWAP_EXACT_IN_SINGLE` to perform the swap, `SETTLE_ALL` to settle input currency, and `TAKE_ALL` to pull output currency.

The example below shows an exact-input swap; exact-output swaps use `SWAP_EXACT_OUT_SINGLE` with `amountInMaximum`.

```solidity
// Build the pool key that routes swaps through this hook.
PoolKey memory poolKey = PoolKey({
    currency0: currency0,
    currency1: currency1,
    fee: uint24(lpFeePercentage),
    tickSpacing: hooks.TICK_SPACING(),
    hooks: IHooks(address(hooks))
});

// Compose the v4 swap actions.
bytes memory actions =
    abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

bytes[] memory params = new bytes[](3);
// Exact input swap with slippage protection.
params[0] = abi.encode(
    IV4Router.ExactInputSingleParams({
        poolKey: poolKey,
        zeroForOne: true,
        amountIn: uint128(amountIn),
        amountOutMinimum: amountOutMin,
        hookData: bytes("")
    })
);
// Settle input currency and take output currency.
params[1] = abi.encode(poolKey.currency0, amountIn);
params[2] = abi.encode(poolKey.currency1, 0);

// Dispatch the swap through the Universal Router.
bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
bytes[] memory inputs = new bytes[](1);
inputs[0] = abi.encode(actions, params);

universalRouter.execute(commands, inputs, block.timestamp + 100);
```

For native ETH swaps, pass ETH via `{value: amountIn}`. For exact-output swaps, send more ETH than needed (`amountInMaximum`) and add a `Commands.SWEEP` command after `V4_SWAP` to return unused ETH. See `test/scenarios/NativeEthMockERC20Pool.t.sol` for reference.

### Quoting swaps
Use the v4 quoter to estimate swap amounts before execution, then feed the quote into the router's slippage parameters.

```solidity
IV4Quoter quoter = IV4Quoter(quoterAddress);

// Exact input quote.
(uint256 quotedAmountOut,) = quoter.quoteExactInputSingle(
    IV4Quoter.QuoteExactSingleParams({
        poolKey: poolKey,
        zeroForOne: true,
        exactAmount: uint128(amountIn),
        hookData: bytes("")
    })
);
uint256 amountOutMinimum = quotedAmountOut * 990000 / 1000000; // 1% slippage

// Exact output quote.
(uint256 quotedAmountIn,) = quoter.quoteExactOutputSingle(
    IV4Quoter.QuoteExactSingleParams({
        poolKey: poolKey,
        zeroForOne: true,
        exactAmount: uint128(amountOut),
        hookData: bytes("")
    })
);
uint256 amountInMaximum = quotedAmountIn * 1010000 / 1000000; // 1% slippage
```

### Fees
Fees are split into LP, hook, and protocol components (all scaled by `FEE_PRECISION = 1e6`). Fees are always realized on the output side of the curve: exact-input swaps deduct the fee from the output, and exact-output swaps gross up the requested output before solving the curve, so both modes traverse the curve to the same depth for the same net output and their cost only differs by rounding. Hook and protocol fees are taken as percentages of the gross LP fee (accrued in the output currency), and the remaining LP fee stays in reserves (benefiting LPs). Hook and protocol fees accumulate and can be withdrawn via `withdrawHookFees()` and `withdrawProtocolFees()`.

## Factory
The factory deploys StableSwap hooks via CREATE2, validates the hook bytecode against a known hash, and configures protocol and hook fee collectors for all pools created through it.

### Deploy the factory
Deploy `StableSwapHooksFactory` via the CREATE3 script in `script/DeployStableSwapHooksFactory.s.sol`. Pass the owner and fee collector addresses to the script, then run:

```bash
forge script script/DeployStableSwapHooksFactory.s.sol \
  $FACTORY_OWNER \
  $PROTOCOL_FEE_COLLECTOR \
  $HOOK_FEE_COLLECTOR \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

If you don't want to use a private key from env, you can configure the deploying account using other `forge script` options (for example `--account` or `--ledger`); see https://book.getfoundry.sh/reference/forge/forge-script.

Use the same sender address across chains to keep the factory address consistent.

CREATE3 addresses depend on the deployer and salt; if you need to redeploy, you must change one of them, which changes the factory address. To keep addresses consistent across chains, redeploy everywhere using the new deployer or salt.

### Deploy new pools (hooks)
Use the factory to deploy a new hook (and initialize all pairwise pools):
1. Prepare sorted `currencies[]` (2-4 assets) and matching `rateOracles[]`.
2. Compute a CREATE2 salt off-chain (see [Off-chain salt mining](#off-chain-salt-mining) below).
3. Call `factory.deploy(...)` with the creation code and constructor params.

`currencies[]` are the token addresses for the pool (native ETH is supported via `address(0)`), and they must be sorted ascending by numerical address value. `rateOracles[]` are optional per-asset price oracles for tokens that represent a different underlying value (for example wstETH vs WETH at 1.22:1). Use zero values for assets that do not require an oracle.

`deploy(...)` expects the hook initcode without constructor args. You can obtain it from Solidity as `type(StableSwapHooks).creationCode` (as shown below), or from the compiled artifact bytecode.object at `out/StableSwapHooks.sol/StableSwapHooks.json` after a `forge build`.

```solidity
Currency[] memory currencies = new Currency[](2);
currencies[0] = usdc;
currencies[1] = usdt;

Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
rateOracles[0] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});
rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

bytes memory code = type(StableSwapHooks).creationCode;
bytes memory constructorArgs = abi.encode(poolManager, currencies, rateOracles, lpFeePercentage, baseAmp);
(, bytes32 salt) = HookMiner.find(address(factory), factory.HOOK_FLAGS(), code, constructorArgs);

StableSwapHooks hooks =
    StableSwapHooks(factory.deploy(currencies, rateOracles, lpFeePercentage, baseAmp, salt, code));
```

WETH/wstETH example with a rate oracle:

```solidity
Currency[] memory currencies = new Currency[](2);
currencies[0] = wsteth;
currencies[1] = weth;

Base.RateOracleConfig[] memory rateOracles = new Base.RateOracleConfig[](2);
rateOracles[0] =
    Base.RateOracleConfig({oracle: Currency.unwrap(wsteth), selector: IWstETH.stEthPerToken.selector});
rateOracles[1] = Base.RateOracleConfig({oracle: address(0), selector: bytes4(0)});

bytes memory code = type(StableSwapHooks).creationCode;
bytes memory constructorArgs = abi.encode(poolManager, currencies, rateOracles, lpFeePercentage, baseAmp);
(, bytes32 salt) = HookMiner.find(address(factory), factory.HOOK_FLAGS(), code, constructorArgs);

StableSwapHooks hooks =
    StableSwapHooks(factory.deploy(currencies, rateOracles, lpFeePercentage, baseAmp, salt, code));
```

### Off-chain salt mining
Salt mining must be performed off-chain because the iterative search is computationally intensive and would consume all available gas if attempted on-chain.

The `script/hookMiner.demo.js` file demonstrates how to mine a valid salt using the same algorithm as `HookMiner.sol`. The demo uses ethers.js, but any library providing a keccak256 function will work. Use this as a reference to integrate salt mining into your dApp, enabling users to deploy their own pools. The mining process can take several seconds depending on how quickly a valid salt is found. Consider running it server-side as an API endpoint, or client-side in a Web Worker to avoid blocking the main thread.

To run the demo locally, you need [Deno](https://deno.land/) and compiled contracts (`forge build`):
```bash
deno run --allow-env=WS_NO_BUFFER_UTIL --allow-read=out/StableSwapHooks.sol/StableSwapHooks.json script/hookMiner.demo.js
```

To adapt the script for your deployment, update the following constants:
- `FACTORY_ADDRESS`: The deployed `StableSwapHooksFactory` address
- `POOL_MANAGER`: The Uniswap v4 PoolManager address for your target chain
- Token addresses and constructor parameters (`LP_FEE_PERCENTAGE`, `BASE_AMP`, rate oracles)

## Fees
Protocol and hook fees are configured on the factory and applied by each hook as percentages of the gross LP fee. Fees accrue during swaps: the net LP fee stays in reserves, while hook and protocol fees accumulate per currency inside the hook until withdrawn.

The factory admin controls fee percentages via `setProtocolFeePercentage` and `setHookFeePercentage` on each hook, and can withdraw accumulated balances using `withdrawProtocolFees()` and `withdrawHookFees()`. The protocol fee collector is intended to be Uniswap, and the hook fee collector is intended to be revert.

### Fee percentages
Set fee percentages on the hook (scaled by `FEE_PRECISION = 1e6`).

```solidity
hooks.setProtocolFeePercentage(100000); // 10% of gross LP fee
hooks.setHookFeePercentage(200000); // 20% of gross LP fee
```

Example fee mix (LP fee set at deployment):

```solidity
// LP fee is set when deploying the hook (0.05% = 500).
uint256 lpFeePercentage = 500;

// Hook/protocol fees set post-deploy (percentages of gross LP fee).
hooks.setHookFeePercentage(200000); // 20% of gross LP fee
hooks.setProtocolFeePercentage(100000); // 10% of gross LP fee
```

Swap example (exact input):

```solidity
// amountOut = 1,000,000 units (1 USDC with 6 decimals), FEE_PRECISION = 1e6
// Gross LP fee = 1,000,000 * 500 / 1e6 = 500
// Hook fee = 500 * 200000 / 1e6 = 100 (accrues to hookFees)
// Protocol fee = 500 * 100000 / 1e6 = 50 (accrues to protocolFees)
// Net LP fee = 500 - 100 - 50 = 350 (stays in reserves)
// Amount out after fees = 1,000,000 - 500 = 999,500.
```

### Fee withdrawal
Withdraw accumulated fees to the configured collectors. Anyone can call these functions; funds are transferred to the fee collector addresses configured on the factory.

```solidity
hooks.withdrawProtocolFees();
hooks.withdrawHookFees();
```

## Amplification
The amplification coefficient (A) controls how tightly the pool prices around the 1:1 peg. Higher A reduces slippage near equilibrium, while lower A behaves closer to constant product. The factory owner can update A over time using ramping, via `startAmpRamp(nextAmp, nextAmpTime)` and `stopAmpRamp()` on the hook.

For intuition: the lower the A, the closer the pool behaves to constant product; the higher the A, the closer it behaves to constant sum. As a concrete reference, Curve’s USDC/USDT pool uses A = 10,000 (see `https://etherscan.io/address/0x4f493b7de8aac7d55f71853688b1f7c8f0243c85#readContract`). In practice you choose A based on how stable and correlated the assets are, and ramp between values to avoid abrupt changes.

Suggested values for stable pools are A between 100 and 1,000: A ≈ 100 keeps a 10% trade under ~10 bps of slippage, while A ≈ 1,000 is effectively constant sum (~1 bp on a 10% trade). For the tightest fiat-stablecoin pegs (for example USDC/USDT) values up to ~10,000 are reasonable, matching Curve; for looser pegs such as LSTs (for example wstETH/WETH, where the rate drifts) prefer the lower end, around A ≈ 100–500.

### Ramping A
Ramping updates A gradually to avoid abrupt changes in pricing and pool balances. Large, immediate shifts in A can be sandwiched between trades to exploit the sudden invariant change and extract value from LPs; ramping smooths the transition to reduce that attack surface. Only the factory owner can start a ramp, and the change must respect the minimum ramp duration and max change limits enforced by the hook.

```solidity
uint256 nextAmp = 200;
uint256 nextAmpTime = block.timestamp + 2 days;

hooks.startAmpRamp(nextAmp, nextAmpTime);
```

### Stopping a ramp
Stopping a ramp freezes A at the current interpolated value. Only the factory owner can stop a ramp.

```solidity
hooks.stopAmpRamp();
```

## Development
### Project structure
- `src/` core contracts (StableSwapHooks, factory, math, liquidity, fees, amp)
- `script/` deployment scripts and chain configuration (`script/config/ChainConfig.sol`)
- `test/` Forge tests and helpers

### Build and test
CI reads the pinned Foundry version from `.foundry-version`; use the same version locally before compiling/deploying the factory so `StableSwapHooks` creation-code hashes match.

```bash
forge build
forge test
forge test -vvv
forge test --mt <test_name>
forge test --mc <contract_name>
```

### Formatting
```bash
forge fmt
forge fmt --check
```

## License
Project source files in `src/`, `script/`, and `test/` are licensed under the Business Source License 1.1 (`BUSL-1.1`). See `LICENSE` for full terms.

Third-party fixtures under `test/testUtils/external/` retain their original upstream licenses.
