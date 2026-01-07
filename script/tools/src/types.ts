export interface ChainInfo {
  chainId: number;
  name: string;
  rpcUrl?: string;
  poolManager?: string;
  testnet: boolean;
}

export interface DeploymentConfig {
  chainId: number;
  factoryAddress?: string;
  currencies: string[];
  rateOracles: RateOracleConfig[];
  lpFeePercentage: string;
  baseAmp: string;
  initializePools: boolean;
  sqrtPriceX96?: string;
}

export interface RateOracleConfig {
  oracle: string;
  selector: string;
}

export interface FactoryDeploymentConfig {
  chainId: number;
  poolManager: string;
  factoryOwner: string;
  protocolFeeCollector: string;
  hookFeeCollector: string;
}

export const SUPPORTED_CHAINS: Record<number, ChainInfo> = {
  // Mainnets
  1: { chainId: 1, name: "ethereum", testnet: false },
  42161: { chainId: 42161, name: "arbitrum", testnet: false },
  10: { chainId: 10, name: "optimism", testnet: false },
  8453: { chainId: 8453, name: "base", testnet: false },
  137: { chainId: 137, name: "polygon", testnet: false },
  56: { chainId: 56, name: "bsc", testnet: false },
  43114: { chainId: 43114, name: "avalanche", testnet: false },
  42220: { chainId: 42220, name: "celo", testnet: false },

  // Testnets
  11155111: { chainId: 11155111, name: "sepolia", testnet: true },
  84532: { chainId: 84532, name: "base-sepolia", testnet: true },
  421614: { chainId: 421614, name: "arbitrum-sepolia", testnet: true },
  11155420: { chainId: 11155420, name: "optimism-sepolia", testnet: true },

  // Local
  31337: { chainId: 31337, name: "anvil", rpcUrl: "http://127.0.0.1:8545", testnet: true },
};
