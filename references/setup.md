# FHEVM Development Environment Setup

## Prerequisites

- **Node.js** 20 or higher (required by `fhevm-hardhat-template`)
- **npm** / **pnpm** / **yarn**
- **Git**
- MetaMask (for testnet interaction)
- Sepolia ETH (from faucets — see [addresses.md](addresses.md))

---

## Option A: Hardhat Template (Recommended)

The official Zama Hardhat template is the fastest starting point:

```bash
git clone https://github.com/zama-ai/fhevm-hardhat-template my-confidential-app
cd my-confidential-app
npm install
```

Template version: **0.4.x** — uses `@fhevm/solidity ^0.11.1`, `@fhevm/hardhat-plugin ^0.4.2`, `ethers ^6.x`.

### Set Required Variables

```bash
# Deployer wallet mnemonic (12 words)
npx hardhat vars set MNEMONIC

# Infura API key for Sepolia RPC
npx hardhat vars set INFURA_API_KEY

# Optional: Etherscan contract verification
npx hardhat vars set ETHERSCAN_API_KEY
```

### Run Locally

```bash
npm run compile       # compile contracts
npm run test          # run tests against local Hardhat mock (cleartext FHE)
```

### Deploy to Sepolia

```bash
npx hardhat deploy --network sepolia
npx hardhat test --network sepolia   # run Sepolia-gated test suite
npx hardhat verify --network sepolia <CONTRACT_ADDRESS>
```

---

## Option B: React + Foundry Template (Full-Stack)

```bash
git clone https://github.com/zama-ai/fhevm-react-template my-fhe-dapp
cd my-fhe-dapp
pnpm install
pnpm contracts:install   # forge soldeer install
```

```bash
# Terminal 1: local chain + FHEVM host + deploy contracts
pnpm chain

# Terminal 2: frontend at http://localhost:3000
pnpm start
```

### Deploy to Sepolia

```bash
cp .env.example .env.local
# Fill in DEPLOYER_PRIVATE_KEY, SEPOLIA_RPC_URL, optional ETHERSCAN_API_KEY
pnpm deploy:sepolia
pnpm start
```

---

## Manual Setup (From Scratch)

### 1. Initialize Project

```bash
mkdir my-fhevm-project && cd my-fhevm-project
npm init -y
```

### 2. Install Dependencies

```bash
# Core FHEVM (standalone, FHE namespace)
npm install @fhevm/solidity

# Hardhat testing — @fhevm/hardhat-plugin peers require these
npm install --save-dev @fhevm/hardhat-plugin
npm install --save-dev @fhevm/mock-utils          # required peer of hardhat-plugin
npm install @zama-fhe/relayer-sdk                 # required peer of hardhat-plugin

# Hardhat ecosystem
npm install --save-dev hardhat
npm install --save-dev @nomicfoundation/hardhat-ethers
npm install --save-dev @nomicfoundation/hardhat-chai-matchers
npm install --save-dev @nomicfoundation/hardhat-verify
npm install --save-dev @typechain/hardhat @typechain/ethers-v6
npm install --save-dev hardhat-deploy hardhat-gas-reporter solidity-coverage
npm install ethers@^6

# TypeScript
npm install --save-dev typescript ts-node @types/node

# Testing (chai v4 — NOT v5)
npm install --save-dev chai@^4 @types/chai mocha @types/mocha chai-as-promised
```

### 3. `hardhat.config.ts`

```typescript
import "@fhevm/hardhat-plugin";           // ← MUST BE FIRST IMPORT
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "@typechain/hardhat";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import type { HardhatUserConfig } from "hardhat/config";
import { vars } from "hardhat/config";
import "solidity-coverage";

const MNEMONIC = vars.get("MNEMONIC", "test test test test test test test test test test test junk");
const INFURA_API_KEY = vars.get("INFURA_API_KEY", "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz");

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  namedAccounts: { deployer: 0 },
  networks: {
    hardhat: {
      accounts: { mnemonic: MNEMONIC },
      chainId: 31337,
    },
    sepolia: {
      accounts: { mnemonic: MNEMONIC, path: "m/44'/60'/0'/0/", count: 10 },
      chainId: 11155111,
      url: `https://sepolia.infura.io/v3/${INFURA_API_KEY}`,
    },
  },
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: { enabled: true, runs: 800 },
      evmVersion: "cancun",   // ← REQUIRED for FHEVM
      metadata: { bytecodeHash: "none" },
    },
  },
  typechain: { outDir: "types", target: "ethers-v6" },
  etherscan: { apiKey: { sepolia: vars.get("ETHERSCAN_API_KEY", "") } },
  gasReporter: { currency: "USD", enabled: !!process.env.REPORT_GAS },
};
export default config;
```

**Critical requirements:**
- `import "@fhevm/hardhat-plugin"` must be the **first** import — always
- `evmVersion: "cancun"` — FHEVM requires Cancun EVM (transient storage, new precompiles)
- `solidity: { version: "0.8.27" }` — 0.8.24+ required; 0.8.27 recommended

### 4. `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "dist",
    "types": ["hardhat/types", "@fhevm/hardhat-plugin"]
  },
  "include": [
    "hardhat.config.ts",
    "contracts/**/*.ts",
    "test/**/*.ts",
    "scripts/**/*.ts",
    "deploy/**/*.ts"
  ]
}
```

### 5. First Solidity Contract

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

// Standalone @fhevm/solidity — use FHE namespace
import { FHE, euint64, externalEuint64 } from "@fhevm/solidity";

// Network config — pick ONE:
// Local Hardhat: no import, no inheritance (plugin auto-configures)
// Sepolia (main branch / upcoming):
//   import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
//   contract MyContract is SepoliaFHEVMConfig { ... }
// Mainnet (v0.11.1 current):
//   import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
//   contract MyContract is ZamaEthereumConfig { ... }

contract MyCounter {
    mapping(address => euint64) private _counters;

    function increment(externalEuint64 encAmount, bytes calldata proof) external {
        euint64 amount = FHE.fromExternal(encAmount, proof);
        if (!FHE.isInitialized(_counters[msg.sender])) {
            _counters[msg.sender] = FHE.asEuint64(0);
        }
        _counters[msg.sender] = FHE.add(_counters[msg.sender], amount);
        FHE.allowThis(_counters[msg.sender]);
        FHE.allow(_counters[msg.sender], msg.sender);
    }

    function getCounter(address user) external view returns (euint64) {
        return _counters[user];
    }
}
```

---

## Network Config Table (Both Package Families)

| Network | `@fhevm/solidity` (standalone) | `fhevm-contracts` extensions |
|---|---|---|
| **Local Hardhat** | *(no class — plugin auto)* | *(no class — plugin auto)* |
| **Sepolia (upcoming)** | `SepoliaFHEVMConfig` from `@fhevm/solidity/config/FHEVMConfig.sol` | `SepoliaZamaFHEVMConfig` from `fhevm/config/ZamaFHEVMConfig.sol` |
| **Sepolia (v0.11.1)** | verify: `ls node_modules/@fhevm/solidity/config/` | `SepoliaZamaFHEVMConfig` from `fhevm/config/ZamaFHEVMConfig.sol` |
| **Mainnet (v0.11.1)** | `ZamaEthereumConfig` from `@fhevm/solidity/config/ZamaConfig.sol` | TBD |
| **Mainnet (upcoming)** | `EthereumFHEVMConfig` from `@fhevm/solidity/config/FHEVMConfig.sol` | TBD |

> **Do not mix package families.** `SepoliaZamaFHEVMConfig` (fhevm-contracts) and `SepoliaFHEVMConfig` (@fhevm/solidity) are different classes from different packages. Using the wrong one silently routes to the wrong network or fails to compile.

---

## Verifying Your Setup

```bash
# Print version info
npx hardhat --version

# Compile contracts
npm run compile

# Run local tests (should all pass quickly in cleartext mock)
npm run test

# Check installed package versions
npm list @fhevm/solidity @fhevm/hardhat-plugin @fhevm/mock-utils @zama-fhe/relayer-sdk

# Find available config classes in your installed version:
ls node_modules/@fhevm/solidity/config/
ls node_modules/fhevm/config/    # if using fhevm-contracts
```

If `fhevm` is not a named export from `"hardhat"` in tests → `@fhevm/hardhat-plugin` is not first in `hardhat.config.ts`.

---

## `fhevm-contracts` Setup (If Extending OZ Confidential Contracts)

```bash
npm install fhevm-contracts
# fhevm-contracts depends on fhevm ^0.6.2 and @openzeppelin/contracts ^5.1.0
# These are installed automatically as transitive deps
```

```solidity
import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20Mintable } from
    "fhevm-contracts/contracts/token/ERC20/extensions/ConfidentialERC20Mintable.sol";

contract MyToken is SepoliaZamaFHEVMConfig, ConfidentialERC20Mintable {
    constructor(address owner)
        ConfidentialERC20Mintable("MyToken", "MTK", owner)
    {}
}
```

See [`examples/ConfidentialTokenFhevmContracts.sol`](../examples/ConfidentialTokenFhevmContracts.sol) for a complete example.
