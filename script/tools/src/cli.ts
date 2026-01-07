#!/usr/bin/env node

import { Command } from 'commander';
import { config } from 'dotenv';
import {
  calculateCreationCodeHash,
  getChainInfo,
  getRpcUrl,
  validateCurrenciesSorted,
  sortCurrencies,
  decodeHookPermissions,
  mineSaltInfo,
  validateAddress
} from './utils.js';
import { SUPPORTED_CHAINS } from './types.js';

// Load environment variables
config();

const program = new Command();

program
  .name('stableswap-tools')
  .description('CLI tools for StableSwap hook deployment and management')
  .version('1.0.0');

// Command: bytecode-hash
program
  .command('bytecode-hash')
  .description('Calculate the creation code hash for StableSwapHooks')
  .action(() => {
    try {
      const hash = calculateCreationCodeHash();
      console.log('\n✓ Creation code hash calculated successfully');
      console.log('\nUse this hash when deploying the factory.');
    } catch (error) {
      console.error('Error:', (error as Error).message);
      process.exit(1);
    }
  });

// Command: list-chains
program
  .command('list-chains')
  .description('List all supported chains')
  .option('--testnet', 'Show only testnets')
  .option('--mainnet', 'Show only mainnets')
  .action((options) => {
    console.log('\nSupported Chains:\n');
    console.log('ID       | Name                | Type    | RPC Configured');
    console.log('---------|---------------------|---------|---------------');

    Object.values(SUPPORTED_CHAINS)
      .filter(chain => {
        if (options.testnet) return chain.testnet;
        if (options.mainnet) return !chain.testnet;
        return true;
      })
      .forEach(chain => {
        const rpcEnvVar = `${chain.name.toUpperCase().replace('-', '_')}_RPC_URL`;
        const hasRpc = !!chain.rpcUrl || !!process.env[rpcEnvVar];
        const type = chain.testnet ? 'Testnet' : 'Mainnet';

        console.log(
          `${chain.chainId.toString().padEnd(8)} | ${chain.name.padEnd(19)} | ${type.padEnd(7)} | ${hasRpc ? '✓' : '✗'}`
        );
      });

    console.log('\nTo configure RPC URLs, add to your .env file:');
    console.log('  <CHAIN_NAME>_RPC_URL=https://...');
  });

// Command: validate-currencies
program
  .command('validate-currencies')
  .description('Validate currency addresses are sorted correctly')
  .argument('<currencies...>', 'Currency addresses')
  .action((currencies: string[]) => {
    console.log('\nValidating currencies...\n');

    // Validate all addresses first
    for (const currency of currencies) {
      if (!validateAddress(currency)) {
        console.log(`✗ Invalid address: ${currency}`);
        process.exit(1);
      }
    }

    console.log('Input:', currencies.join(', '));

    const isSorted = validateCurrenciesSorted(currencies);

    if (isSorted) {
      console.log('\n✓ Currencies are correctly sorted (ascending order)');
    } else {
      console.log('\n✗ Currencies are NOT sorted correctly');
      console.log('\nCorrect order should be:');
      const sorted = sortCurrencies(currencies);
      sorted.forEach((addr, i) => {
        console.log(`  ${i + 1}. ${addr}`);
      });
    }
  });

// Command: sort-currencies
program
  .command('sort-currencies')
  .description('Sort currency addresses in ascending order')
  .argument('<currencies...>', 'Currency addresses')
  .action((currencies: string[]) => {
    console.log('\nSorting currencies...\n');

    // Validate all addresses first
    for (const currency of currencies) {
      if (!validateAddress(currency)) {
        console.log(`✗ Invalid address: ${currency}`);
        process.exit(1);
      }
    }

    const sorted = sortCurrencies(currencies);

    console.log('Sorted addresses:');
    sorted.forEach((addr, i) => {
      console.log(`  ${i + 1}. ${addr}`);
    });

    console.log('\nFor .env file:');
    console.log(`CURRENCIES=${sorted.join(',')}`);
  });

// Command: hook-permissions
program
  .command('hook-permissions')
  .description('Decode hook permissions from address')
  .argument('<address>', 'Hook address')
  .action((address: string) => {
    if (!validateAddress(address)) {
      console.error('Error: Invalid address format');
      process.exit(1);
    }

    console.log('\nHook Permissions:\n');
    console.log('Address:', address);
    console.log('');

    const perms = decodeHookPermissions(address);

    const enabled = Object.entries(perms)
      .filter(([_, value]) => value)
      .map(([key, _]) => key);

    if (enabled.length === 0) {
      console.log('No permissions enabled');
    } else {
      console.log('Enabled permissions:');
      enabled.forEach(perm => console.log(`  ✓ ${perm}`));
    }
  });

// Command: mine-salt-info
program
  .command('mine-salt-info')
  .description('Show information about salt mining process')
  .requiredOption('-f, --factory <address>', 'Factory address')
  .option('-c, --chain <chain>', 'Chain ID or name', '31337')
  .action((options) => {
    try {
      if (!validateAddress(options.factory)) {
        console.error('Error: Invalid factory address');
        process.exit(1);
      }

      const chainInfo = getChainInfo(options.chain);
      console.log(`\nChain: ${chainInfo.name} (${chainInfo.chainId})`);
      console.log(`Factory: ${options.factory}\n`);

      // StableSwapHooks required flags
      const HOOK_FLAGS =
        (1n << 159n) | // beforeInitialize
        (1n << 157n) | // beforeAddLiquidity
        (1n << 155n) | // beforeRemoveLiquidity
        (1n << 153n) | // beforeSwap
        (1n << 149n) | // beforeSwapReturnsDelta
        (1n << 151n);  // beforeDonate

      const info = mineSaltInfo(options.factory, HOOK_FLAGS);
      console.log(info);
    } catch (error) {
      console.error('Error:', (error as Error).message);
      process.exit(1);
    }
  });

// Command: generate-env
program
  .command('generate-env')
  .description('Generate example .env file for deployment')
  .option('-c, --chain <chain>', 'Chain ID or name')
  .option('--factory', 'Generate factory deployment config')
  .option('--hook', 'Generate hook deployment config')
  .action((options) => {
    console.log('\n# StableSwap Deployment Configuration\n');

    if (options.chain) {
      const chainInfo = getChainInfo(options.chain);
      const rpcVar = `${chainInfo.name.toUpperCase().replace('-', '_')}_RPC_URL`;
      console.log(`# Chain: ${chainInfo.name} (${chainInfo.chainId})`);
      console.log(`${rpcVar}=https://...`);
      console.log('');
    }

    if (options.factory || (!options.factory && !options.hook)) {
      console.log('# Factory Deployment');
      console.log('POOL_MANAGER=0x...');
      console.log('FACTORY_OWNER=0x...');
      console.log('PROTOCOL_FEE_COLLECTOR=0x...');
      console.log('HOOK_FEE_COLLECTOR=0x...');
      console.log('');
    }

    if (options.hook || (!options.factory && !options.hook)) {
      console.log('# Hook Deployment');
      console.log('FACTORY_ADDRESS=0x...');
      console.log('CURRENCIES=0x...,0x...');
      console.log('RATE_ORACLES=0x0000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000');
      console.log('RATE_ORACLE_SELECTORS=0x00000000,0x00000000');
      console.log('LP_FEE_PERCENTAGE=300');
      console.log('BASE_AMP=100');
      console.log('INITIALIZE_POOLS=true');
      console.log('SQRT_PRICE_X96=79228162514264337593543950336');
      console.log('');
    }
  });

program.parse();
