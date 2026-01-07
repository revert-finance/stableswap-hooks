import { readFileSync } from 'fs';
import { join } from 'path';
import { keccak256, isAddress, getAddress } from 'viem';
import { SUPPORTED_CHAINS, ChainInfo } from './types.js';

/**
 * Calculate the keccak256 hash of the StableSwapHooks creation bytecode
 */
export function calculateCreationCodeHash(): string {
  try {
    // Read the compiled bytecode from forge artifacts
    const artifactPath = join(process.cwd(), '../../out/StableSwapHooks.sol/StableSwapHooks.json');
    const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'));
    const bytecode = artifact.bytecode.object;

    // Ensure bytecode has 0x prefix
    const bytecodeHex = bytecode.startsWith('0x') ? bytecode : `0x${bytecode}`;
    const hash = keccak256(bytecodeHex as `0x${string}`);

    console.log('Creation code hash:', hash);
    return hash;
  } catch (error) {
    console.error('Error reading bytecode. Make sure you run "forge build" first.');
    throw error;
  }
}

/**
 * Get chain information by chain ID or name
 */
export function getChainInfo(chainIdOrName: string): ChainInfo {
  // Try parsing as number first
  const maybeChainId = parseInt(chainIdOrName);
  if (!isNaN(maybeChainId) && SUPPORTED_CHAINS[maybeChainId]) {
    return SUPPORTED_CHAINS[maybeChainId];
  }

  // Try matching by name
  const chain = Object.values(SUPPORTED_CHAINS).find(
    c => c.name.toLowerCase() === chainIdOrName.toLowerCase()
  );

  if (!chain) {
    throw new Error(`Unsupported chain: ${chainIdOrName}`);
  }

  return chain;
}

/**
 * Load RPC URL from environment variables
 * Supports pattern: <CHAIN_NAME>_RPC_URL or RPC_URL_<CHAIN_NAME>
 */
export function getRpcUrl(chainInfo: ChainInfo): string {
  if (chainInfo.rpcUrl) {
    return chainInfo.rpcUrl;
  }

  const envVarName1 = `${chainInfo.name.toUpperCase().replace('-', '_')}_RPC_URL`;
  const envVarName2 = `RPC_URL_${chainInfo.name.toUpperCase().replace('-', '_')}`;

  const rpcUrl = process.env[envVarName1] || process.env[envVarName2];

  if (!rpcUrl) {
    throw new Error(
      `No RPC URL found for ${chainInfo.name}. Set ${envVarName1} or ${envVarName2} in .env`
    );
  }

  return rpcUrl;
}

/**
 * Format address for display
 */
export function formatAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

/**
 * Validate Ethereum address format using viem
 */
export function validateAddress(address: string): boolean {
  return isAddress(address);
}

/**
 * Normalize address to checksummed format
 */
export function normalizeAddress(address: string): string {
  if (!isAddress(address)) {
    throw new Error(`Invalid address: ${address}`);
  }
  return getAddress(address);
}

/**
 * Validate addresses are sorted in ascending order (required for Uniswap v4)
 */
export function validateCurrenciesSorted(currencies: string[]): boolean {
  // Normalize all addresses first
  const normalized = currencies.map(c => normalizeAddress(c).toLowerCase());

  for (let i = 0; i < normalized.length - 1; i++) {
    if (BigInt(normalized[i]) >= BigInt(normalized[i + 1])) {
      return false;
    }
  }
  return true;
}

/**
 * Sort currencies in ascending order
 */
export function sortCurrencies(currencies: string[]): string[] {
  const normalized = currencies.map(c => normalizeAddress(c));

  return normalized.sort((a, b) => {
    const aBig = BigInt(a);
    const bBig = BigInt(b);
    return aBig < bBig ? -1 : aBig > bBig ? 1 : 0;
  });
}

/**
 * Mine a CREATE2 salt for valid hook address with required permission flags
 * This is a simplified TypeScript version - for production, use the Solidity mineSalt function
 */
export function mineSaltInfo(
  factoryAddress: string,
  requiredFlags: bigint
): string {
  return `
Salt mining finds a CREATE2 salt that produces a hook address with correct permission flags.

Required flags (HOOK_FLAGS): ${requiredFlags}
Factory address: ${factoryAddress}

To mine a salt, the DeployHook script automatically calls factory.mineSalt() before deployment.

The factory.mineSalt() function uses HookMiner.find() which iterates through salts until
it finds one that produces an address with the correct permission flags encoded in it.

Note: Salt mining is computationally intensive and automatically handled by the deployment scripts.
  `.trim();
}

/**
 * Display hook permissions from address
 */
export function decodeHookPermissions(hookAddress: string): {
  beforeInitialize: boolean;
  afterInitialize: boolean;
  beforeAddLiquidity: boolean;
  afterAddLiquidity: boolean;
  beforeRemoveLiquidity: boolean;
  afterRemoveLiquidity: boolean;
  beforeSwap: boolean;
  afterSwap: boolean;
  beforeDonate: boolean;
  afterDonate: boolean;
  beforeSwapReturnsDelta: boolean;
  afterSwapReturnsDelta: boolean;
  afterAddLiquidityReturnsDelta: boolean;
  afterRemoveLiquidityReturnsDelta: boolean;
} {
  const addressBigInt = BigInt(normalizeAddress(hookAddress));

  return {
    beforeInitialize: (addressBigInt & (1n << 159n)) !== 0n,
    afterInitialize: (addressBigInt & (1n << 158n)) !== 0n,
    beforeAddLiquidity: (addressBigInt & (1n << 157n)) !== 0n,
    afterAddLiquidity: (addressBigInt & (1n << 156n)) !== 0n,
    beforeRemoveLiquidity: (addressBigInt & (1n << 155n)) !== 0n,
    afterRemoveLiquidity: (addressBigInt & (1n << 154n)) !== 0n,
    beforeSwap: (addressBigInt & (1n << 153n)) !== 0n,
    afterSwap: (addressBigInt & (1n << 152n)) !== 0n,
    beforeDonate: (addressBigInt & (1n << 151n)) !== 0n,
    afterDonate: (addressBigInt & (1n << 150n)) !== 0n,
    beforeSwapReturnsDelta: (addressBigInt & (1n << 149n)) !== 0n,
    afterSwapReturnsDelta: (addressBigInt & (1n << 148n)) !== 0n,
    afterAddLiquidityReturnsDelta: (addressBigInt & (1n << 147n)) !== 0n,
    afterRemoveLiquidityReturnsDelta: (addressBigInt & (1n << 146n)) !== 0n,
  };
}
