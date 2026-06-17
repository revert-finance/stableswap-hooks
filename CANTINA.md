# Cantina Post Audit

This file is to be used as reference for the main feature branch where the different PR regarding cantina finding fixes are made

Can be deleted when all finding fixes are merged

## Findings

- [x] **1351** - quoteZapIn underestimates shares, undermining slippage protection
- [x] **998** - Reachable 4-token pool states allow zero-input exact-output reserve extraction
- [x] **788** - Low-amp pools can be pushed into non-convergent reserve states that brick swaps
- [x] **546** - Zero-fee exact-input round trips can extract reserves through StableSwap rounding asymmetry
- [x] **522** - Zero LP Fee Deployment Allows Single Exact-Input Swap to Drain Output Reserve, Permanently Bricking addLiquidity
- [ ] **512** - StableSwapZapIn._calculateSwapAmount Overshoots Target Ratio in 3+ Token Pools, Causing Up to ~17% LP-Share Loss
- [x] **102** - Asymmetric Exact Output Math Enables Systemic Fee Evasion and LP Yield Loss
- [x] **63** - StableSwap Invariant Overflow Causes Persistent Swap DoS in Imbalanced Pools
- [x] **53** - Integer rounding in 3-token geometricMean leads to mispriced initial invariant and capital loss for LPs
- [x] **29** - Native ETH removeLiquidity reentrancy lets LP swap against withdrawn stale reserves
- [ ] **15** - zapIn passes zero slippage to internal addLiquidity, enabling sandwich attacks
- [x] **8** - Low-decimal exact-output swaps can withdraw LP reserves for zero input
