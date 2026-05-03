// Canonical Hardhat config for FHEVM development
// IMPORTANT: @fhevm/hardhat-plugin MUST be the FIRST import

import "@fhevm/hardhat-plugin";                          // ← MUST be first
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "@typechain/hardhat";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import type { HardhatUserConfig } from "hardhat/config";
import { vars } from "hardhat/config";
import "solidity-coverage";

// npx hardhat vars set MNEMONIC
// npx hardhat vars set INFURA_API_KEY
// npx hardhat vars set ETHERSCAN_API_KEY (optional)

const MNEMONIC: string = vars.get(
  "MNEMONIC",
  "test test test test test test test test test test test junk"
);
const INFURA_API_KEY: string = vars.get(
  "INFURA_API_KEY",
  "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
);

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",

  namedAccounts: {
    deployer: 0,
  },

  etherscan: {
    apiKey: {
      sepolia: vars.get("ETHERSCAN_API_KEY", ""),
    },
  },

  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS === "true",
    excludeContracts: [],
  },

  networks: {
    // Local Hardhat — cleartext mock FHE (fast, no real encryption)
    hardhat: {
      accounts: { mnemonic: MNEMONIC },
      chainId: 31337,
    },

    // Local Anvil — for React template / Foundry workflow
    anvil: {
      accounts: {
        mnemonic: MNEMONIC,
        path: "m/44'/60'/0'/0/",
        count: 10,
      },
      chainId: 31337,
      url: "http://localhost:8545",
    },

    // Sepolia testnet — real FHE with Zama's coprocessor + KMS
    sepolia: {
      accounts: {
        mnemonic: MNEMONIC,
        path: "m/44'/60'/0'/0/",
        count: 10,
      },
      chainId: 11155111,
      url: `https://sepolia.infura.io/v3/${INFURA_API_KEY}`,
      // Alternative public endpoints:
      // url: "https://eth-sepolia.public.blastapi.io",
      // url: "https://rpc.sepolia.org",
    },
  },

  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },

  solidity: {
    version: "0.8.27",
    settings: {
      metadata: {
        bytecodeHash: "none",
      },
      optimizer: {
        enabled: true,
        runs: 800,
      },
      evmVersion: "cancun",  // ← REQUIRED for FHEVM (transient storage + precompiles)
    },
  },

  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
};

export default config;
