import { ethers } from "npm:ethers@5";

// =============================================================================
// Hook Miner
// lib/uniswap-hooks/lib/v4-periphery/src/utils/HookMiner.sol
// =============================================================================

const FLAG_MASK = BigInt(0x3fff);
const MAX_LOOP = 160_444;

function toBytes32(value) {
  return value.toString(16).padStart(64, "0");
}

function concatHex(...hexStrings) {
  return "0x" + hexStrings.map((s) => s.replace(/^0x/, "")).join("");
}

function computeCreate2Address(deployer, salt, initCode, keccak256) {
  const initCodeHash = keccak256(initCode);
  const data = concatHex("0xff", deployer, toBytes32(salt), initCodeHash);
  const hash = keccak256(data);
  return "0x" + hash.slice(-40);
}

function mineSalt(deployer, flags, creationCode, constructorArgs, keccak256, options = {}) {
  const { startSalt = 0n, maxIterations = MAX_LOOP } = options;
  const targetFlags = flags & FLAG_MASK;
  const initCode = concatHex(creationCode, constructorArgs);

  for (let i = 0; i < maxIterations; i++) {
    const salt = startSalt + BigInt(i);
    const hookAddress = computeCreate2Address(deployer, salt, initCode, keccak256);
    const addressFlags = BigInt(hookAddress) & FLAG_MASK;

    if (addressFlags === targetFlags) {
      return {
        address: hookAddress,
        salt: "0x" + toBytes32(salt),
      };
    }
  }

  throw new Error("HookMiner: could not find salt");
}

// =============================================================================
// Demo (Arbitrum Sepolia)
// deno run --allow-env=WS_NO_BUFFER_UTIL --allow-read=out/StableSwapHooks.sol/StableSwapHooks.json utils/hookMiner.demo.js
// =============================================================================

const POOL_MANAGER = "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317";
const USDT = "0x30fA2FbE15c1EaDfbEF28C188b7B8dbd3c1Ff2eB";
const USDC = "0xf3C3351D6Bd0098EEb33ca8f830FAf2a141Ea2E1";
const FACTORY_ADDRESS = ethers.constants.AddressZero; // Replace with the StableSwapHookFactory address deployed in the expected chain
const LP_FEE_PERCENTAGE = 300; // 0.03% (FEE_PRECISION = 1e6)
const BASE_AMP = 100;

const emptyOracle = { oracle: ethers.constants.AddressZero, selector: "0x00000000" }; // Disabled oracle.

const hooksDataPath = "out/StableSwapHooks.sol/StableSwapHooks.json";
const hooksData = JSON.parse(await Deno.readTextFile(hooksDataPath));
const creationCode = hooksData.bytecode.object;
console.log("Loaded hook bytecode:", creationCode.length, "chars");

// Hook flags from lib/uniswap-hooks/lib/v4-core/src/libraries/Hooks.sol.
// Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_DONATE_FLAG
const hookFlags = BigInt(10920);
console.log("Hook flags:", "0x" + hookFlags.toString(16));

// Constructor payload for StableSwapHooks.
const constructorArgs = ethers.utils.defaultAbiCoder.encode(
  ["address", "address[]", "tuple(address oracle, bytes4 selector)[]", "uint256", "uint256"],
  [POOL_MANAGER, [USDT, USDC], [{ ...emptyOracle }, { ...emptyOracle }], LP_FEE_PERCENTAGE, BASE_AMP],
);

console.log("Constructor args:", constructorArgs);

const start = performance.now(); // Simple timing for the mining loop.
console.log("Mining Salt...")

const result = mineSalt(FACTORY_ADDRESS, hookFlags, creationCode, constructorArgs, ethers.utils.keccak256);

const elapsed = performance.now() - start;
console.log("Mined address:", result.address);
console.log("Salt:", result.salt);
console.log("Elapsed:", elapsed.toFixed(2), "ms");
