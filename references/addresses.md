# Network Addresses & Configuration

> **Source of truth:** These addresses are embedded in `@fhevm/solidity/config/FHEVMConfig.sol` and
> `fhevm/config/ZamaFHEVMConfig.sol` — the same values your config-inheritance classes set automatically.
> Verified from source: 2026-05-02.

---

## Sepolia Testnet (Chain ID: 11155111)

### Core FHEVM Contracts

These are read directly from `FHEVMConfig.getSepoliaConfig()` in the published `@fhevm/solidity` package:

| Contract | Address |
|---|---|
| **ACL** | `0xFee8407e2f5e3Ee68ad77cAE98c434e637f516e5` |
| **FHEVMExecutor** (coprocessor) | `0x687408aB54661ba0b4aeF3a44156c616c6955E07` |
| **KMSVerifier** | `0x9D6891A6240D6130c54ae243d8005063D05fE14b` |
| **InputVerifier** | `0x3a2DA6f1daE9eF988B48d9CF27523FA31a8eBE50` |

> **Never hardcode these.** Inherit the config class in your contract instead — it calls `FHE.setCoprocessor()` with the right struct. Addresses can change on protocol upgrades. Using the config class insulates you automatically.

### Config Class (Sepolia) — How to Use

**Standalone contracts (`@fhevm/solidity`):**
```solidity
// Upcoming / GitHub main branch:
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
contract MyContract is SepoliaFHEVMConfig { }

// Current npm v0.11.1 (check your package.json):
// The Sepolia class name may differ — verify by running:
//   ls node_modules/@fhevm/solidity/config/
```

**fhevm-contracts extensions (`fhevm` ^0.6.x + `fhevm-contracts` v0.2.4):**
```solidity
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
contract MyToken is SepoliaZamaFHEVMConfig, ConfidentialERC20Mintable { }
```

**Local Hardhat (no inheritance needed — plugin configures automatically):**
```solidity
contract MyContract { }  // @fhevm/hardhat-plugin handles setup
```

---

## Ethereum Mainnet (Chain ID: 1)

> Mainnet support is marked TODO in the current source (`getEthereumConfig()` is not yet implemented).
> When it ships, use `EthereumFHEVMConfig` from `@fhevm/solidity/config/FHEVMConfig.sol`.

### Config Class (Mainnet) — Current (v0.11.1)

```solidity
// For @fhevm/solidity v0.11.1 (current npm):
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
contract MyContract is ZamaEthereumConfig { }

// For upcoming @fhevm/solidity (main branch):
import { EthereumFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
contract MyContract is EthereumFHEVMConfig { }
```

---

## Package Versions (Verified 2026-05-02)

| Package | Current Version | Notes |
|---|---|---|
| `@fhevm/solidity` | **0.11.1** | Standalone FHE library. Config at `ZamaConfig.sol` (v0.11.1) or `FHEVMConfig.sol` (main) |
| `@fhevm/hardhat-plugin` | **0.4.2** | Must be first import in `hardhat.config.ts` |
| `@fhevm/mock-utils` | **0.4.2** | Required peer dep of hardhat-plugin; mock mode support |
| `@zama-fhe/relayer-sdk` | **0.4.1–0.4.2** | Frontend SDK for user re-encryption |
| `fhevm-contracts` | **0.2.4** | 11 pre-built confidential contracts; uses `TFHE` namespace |
| `fhevm` (core, used by fhevm-contracts) | **^0.6.2** | Transitive dep via fhevm-contracts; different from @fhevm/solidity |

---

## RPC Endpoints

### Sepolia (Free)
```
https://eth-sepolia.public.blastapi.io
https://rpc.sepolia.org
https://sepolia.drpc.org
```

### Sepolia (API Key)
```
https://sepolia.infura.io/v3/YOUR_INFURA_KEY
https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
```

### Hardhat Config Network Entry
```typescript
sepolia: {
  accounts: { mnemonic: MNEMONIC, path: "m/44'/60'/0'/0/", count: 10 },
  chainId: 11155111,
  url: `https://sepolia.infura.io/v3/${INFURA_API_KEY}`,
},
```

---

## Relayer & KMS Endpoints

```
Testnet Relayer:  https://relayer.testnet.zama.ai
KMS Gateway:      https://gateway.sepolia.zama.ai
```

---

## Solidity Config Reference

The full `FHEVMConfigStruct` (for advanced/custom setups):

```solidity
struct FHEVMConfigStruct {
    address ACLAddress;
    address FHEVMExecutorAddress;
    address KMSVerifierAddress;
    address InputVerifierAddress;
}

// Sepolia values (embedded in SepoliaFHEVMConfig constructor):
FHEVMConfigStruct({
    ACLAddress:           0xFee8407e2f5e3Ee68ad77cAE98c434e637f516e5,
    FHEVMExecutorAddress: 0x687408aB54661ba0b4aeF3a44156c616c6955E07,
    KMSVerifierAddress:   0x9D6891A6240D6130c54ae243d8005063D05fE14b,
    InputVerifierAddress: 0x3a2DA6f1daE9eF988B48d9CF27523FA31a8eBE50
})
```

---

## Frontend (`@zama-fhe/relayer-sdk`) Instance

```typescript
// Node / server-side (import from "@zama-fhe/relayer-sdk/node" or "@zama-fhe/relayer-sdk")
import { RelayerWeb } from "@zama-fhe/relayer-sdk/web";

// Sepolia
const relayer = new RelayerWeb({
  relayerUrl: "https://relayer.testnet.zama.ai",
});

// Local anvil / cleartext mock
import { RelayerCleartext } from "@zama-fhe/relayer-sdk";
const relayer = new RelayerCleartext({ rpcUrl: "http://localhost:8545" });
```

---

## Sepolia Faucets

| Faucet | URL | Daily Limit |
|---|---|---|
| Alchemy | https://sepoliafaucet.com | 0.5 ETH |
| Infura | https://www.infura.io/faucet/sepolia | 0.5 ETH |
| QuickNode | https://faucet.quicknode.com/ethereum/sepolia | 1 ETH |
| pk910 PoW | https://sepolia-faucet.pk910.de | Variable |

---

## Block Explorers

| Network | Explorer |
|---|---|
| Sepolia | https://sepolia.etherscan.io |
| Mainnet | https://etherscan.io |

---

## Chain IDs

| Network | Chain ID |
|---|---|
| Ethereum Mainnet | 1 |
| Sepolia Testnet | 11155111 |
| Local Hardhat / Anvil | 31337 |

---

## Key Resources

| Resource | URL |
|---|---|
| Zama Protocol Docs | https://docs.zama.org/protocol |
| fhevm-solidity GitHub | https://github.com/zama-ai/fhevm-solidity |
| Hardhat Template | https://github.com/zama-ai/fhevm-hardhat-template |
| fhevm-contracts GitHub | https://github.com/zama-ai/fhevm-contracts |
| relayer-sdk GitHub | https://github.com/zama-ai/relayer-sdk |
| `@fhevm/solidity` npm | https://www.npmjs.com/package/@fhevm/solidity |
| `@fhevm/hardhat-plugin` npm | https://www.npmjs.com/package/@fhevm/hardhat-plugin |
| `fhevm-contracts` npm | https://www.npmjs.com/package/fhevm-contracts |
| `@zama-fhe/relayer-sdk` npm | https://www.npmjs.com/package/@zama-fhe/relayer-sdk |
| Community Forum | https://community.zama.ai |
| Discord | https://discord.gg/zama |
| Sepolia Address Page | https://docs.zama.org/protocol/protocol-apps/addresses/testnet/sepolia |
