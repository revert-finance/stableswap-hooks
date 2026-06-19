# Cantina Post Audit

This file is to be used as reference for the main feature branch where the different PR regarding cantina finding fixes are made

Can be deleted when all finding fixes are merged

## Findings

- [x] **1351** - quoteZapIn underestimates shares, undermining slippage protection
- [x] **998** - Reachable 4-token pool states allow zero-input exact-output reserve extraction
- [x] **788** - Low-amp pools can be pushed into non-convergent reserve states that brick swaps
- [x] **546** - Zero-fee exact-input round trips can extract reserves through StableSwap rounding asymmetry
- [x] **522** - Zero LP Fee Deployment Allows Single Exact-Input Swap to Drain Output Reserve, Permanently Bricking addLiquidity
- [x] **512** - StableSwapZapIn._calculateSwapAmount Overshoots Target Ratio in 3+ Token Pools, Causing Up to ~17% LP-Share Loss
- [x] **102** - Asymmetric Exact Output Math Enables Systemic Fee Evasion and LP Yield Loss
- [x] **63** - StableSwap Invariant Overflow Causes Persistent Swap DoS in Imbalanced Pools
- [x] **53** - Integer rounding in 3-token geometricMean leads to mispriced initial invariant and capital loss for LPs
- [x] **29** - Native ETH removeLiquidity reentrancy lets LP swap against withdrawn stale reserves
- [x] **15** - zapIn passes zero slippage to internal addLiquidity, enabling sandwich attacks
- [x] **8** - Low-decimal exact-output swaps can withdraw LP reserves for zero input

## Fixes

### #1351, Zap-in quote understated the shares users would get (Medium)

`quoteZapIn` estimated LP shares using the pool's balances *before* its internal balancing swaps, while sizing the deposit for the balances *after* them. The mismatch made the quote read low, so users following the "quote then apply 1% tolerance" flow ended up with ~10x weaker slippage protection than intended.

**Fix:** quote the shares against the simulated *post-swap* balances, matching what the deposit will actually see. The quote now tracks the real outcome closely, so the user's minimum-shares guard works as intended.

**Commit:** [8fd6e0f (#127)](https://github.com/revert-finance/stableswap-hooks/commit/8fd6e0fb11e5ab95de2e34600354c1134f07f730)

### #998, Exact-output swap could pay zero for nonzero output (Medium)

In certain reachable, heavily imbalanced pool states, the math that computes how much a trader must pay for an exact-output swap could round all the way down to **zero**, letting a trader take tokens out while paying nothing in.

**Fix:** reject any exact-output swap whose required input comes out to zero. The trade now reverts instead of releasing free tokens; the pool stays usable for all normal swaps.

**Commit:** [7988026 (#117)](https://github.com/revert-finance/stableswap-hooks/commit/7988026bae349b1846efd5a4409fa1e4f3abd207)

### #546 + #522, Zero-fee pools could be drained or bricked (Medium)

Both stem from the same root cause: a small slice of every swap's fee (the "net LP fee") is meant to stay in the pool, acting as a floor that keeps reserves from ever hitting zero. A pool deployed with a **0% LP fee** has no such floor. A single large swap could then drain a reserve to zero, permanently bricking deposits and swaps (#522), or a no-price-movement round trip could skim reserves through rounding (#546).

**Fix:** reject deployment of pools with a 0% LP fee. Also tightened the fee setters so the hook + protocol cut can no longer add up to 100% of the LP fee (which would zero out the floor again). A positive floor now always remains in reserves.

**Commit:** [fe1eb65 (#118)](https://github.com/revert-finance/stableswap-hooks/commit/fe1eb65e90bfbcb6dfd0839ad9c190fd2f78aba2)

### #512, Zap-in balancing overshot in 3+ token pools (Medium)

The routine that sizes each balancing swap was missing a divisor, so in pools with 3+ tokens it overshot the target, flipping the token being topped up into a surplus and forcing extra corrective swaps, each paying fees. Users got materially fewer LP shares.

**Fix:** add the missing divisor so each swap lands on the target ratio. A single-sided deposit into a 3-token pool now settles in the expected number of swaps instead of oscillating.

**Commit:** [8fd6e0f (#127)](https://github.com/revert-finance/stableswap-hooks/commit/8fd6e0fb11e5ab95de2e34600354c1134f07f730)

### #102, Exact-output swaps underpaid fees (Medium)

The fee on an exact-output swap (where the trader specifies how much they want out) was added on top of the trade cost rather than baked in. This made exact-output trades slightly cheaper than the equivalent exact-input trade, so bots could route around part of the LP fee.

**Fix:** "gross up" the input so the fee is charged as the intended percentage of the full amount paid, making both swap directions cost the same. A matching guard also rejects deployments with an LP fee of 100% or more (which the new fee math can't divide by).

**Commit:** [0cad221 (#120)](https://github.com/revert-finance/stableswap-hooks/commit/0cad2214d25f5235e1218f7f1614a9ad83dc9d1b)

### #63 + #788, Imbalanced pools could brick all swaps (Medium)

Both let a pool reach a reserve state where the core invariant math either overflows (#63) or fails to converge (#788). Because every swap recomputes that invariant first, once a pool entered the bad state, all swaps reverted, and normal trading/deposits couldn't recover it.

**Fix:** (1) use wider-precision multiplication in the invariant math so it no longer overflows, and (2) after any swap or deposit, re-check that the resulting pool is still priceable, if not, the operation reverts. This stops a pool from ever being pushed into the bricked state. Withdrawals are intentionally exempt so liquidity can always exit.

**Commit:** [990fe16 (#123)](https://github.com/revert-finance/stableswap-hooks/commit/990fe162ab27041371ea0ea47556c556b9caccdb)

**Note:** the guard only runs on swaps and deposits, so it cannot catch state that drifts on its own. A heavily imbalanced pool can still be pushed into the bricked state by changes that bypass the guard, rate-oracle movements, an amp ramp interpolating into a non-convergent region, or a liquidity removal that worsens the ratio. In every case liquidity can still be withdrawn via `removeLiquidity` (intentionally exempt from the guard), so funds are never trapped.

### #53, Rounding error in 3-token pool setup (Medium)

When a 3-token pool starts up, it computes a geometric mean by taking the cube root of each balance separately and multiplying, which rounds down three times and undervalues the pool, shortchanging the first liquidity provider's shares.

**Fix:** multiply the three balances first, then take a single cube root (rounding down only once). For very large balances where that multiplication would overflow, it safely falls back to the old per-value method (where the rounding error is negligible at that scale).

**Commit:** [05cf0c4 (#119)](https://github.com/revert-finance/stableswap-hooks/commit/05cf0c4a03097799605b7156594d97cd6b5b5991)

### #29, Native ETH removeLiquidity reentrancy (High)

When an LP removed liquidity from a pool holding native ETH, the pool sent the ETH out **before** updating its own books. A malicious LP could hijack that ETH callback to trade against the stale (still-large) balances and drain the pool at an unfair price.

**Fix:** update all internal accounting first, burn the LP's shares and lower the reserves, then send any funds out. The callback now always sees the correct post-withdrawal state.

**Commit:** [e70981f (#116)](https://github.com/revert-finance/stableswap-hooks/commit/e70981f6e93c44be34334a294c0c290a32c1544d)

### #15, Zap-in's internal swaps had no slippage protection (Medium)

`zapIn` ran its internal balancing swaps with no per-swap minimum, so if the pool moved against the user mid-zap, those swaps executed at bad rates with only the final shares check as a backstop.

**Fix:** give each pre-calculated swap its own minimum-output bound (derived from the quote), so an adverse swap reverts instead of silently executing at a worse rate.

**Commit:** [8fd6e0f (#127)](https://github.com/revert-finance/stableswap-hooks/commit/8fd6e0fb11e5ab95de2e34600354c1134f07f730)

### #8, Low-decimal exact-output could take tokens for free (Medium)

For a pool pairing a very low-decimal token (e.g. 0–6 decimals) with an 18-decimal token, the required input for an exact-output swap was rounded *down*, and could round all the way to zero, letting a trader pull out the 18-decimal token while paying nothing.

**Fix:** round the required input *up* instead, so any nonzero obligation always charges at least 1 unit. Rounding now consistently favors the pool. Combined with #998's guard, free-output is no longer possible.

**Commit:** [6452513 (#121)](https://github.com/revert-finance/stableswap-hooks/commit/6452513707f52046df0fb00d1c8ebd2e0ff28b7a)
