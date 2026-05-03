# FHEVM Agent Instructions (Codex / Plain-Markdown Adapter)

This file is the Codex and plain-markdown adapter for the `zama-fhevm-skill` package.
For the full routing layer, workflow, and correctness checks, see [SKILL.md](SKILL.md).

## What This Skill Covers

Confidential smart contracts on the Zama Protocol (FHEVM):
- Encrypted Solidity types (`euint8` through `euint256`, `ebool`, `eaddress`)
- FHE operations, ACL management, and input proofs
- User decryption (EIP-712) and public decryption (`FHE.makePubliclyDecryptable`)
- Frontend integration with `@zama-fhe/relayer-sdk`
- Testing with `@fhevm/hardhat-plugin` and `fhevm` named import from `"hardhat"`
- **Complete `fhevm-contracts` v0.2.4 library** — all 11 contracts with ground-truth API
- **ERC-7984 confidential token standard** (draft, not ERC-20 compatible)

---

## Package Versions (Verified 2026-05-02)

| Package | Version | Notes |
|---|---|---|
| `@fhevm/solidity` | **0.11.1** | Standalone `FHE` namespace library |
| `@fhevm/hardhat-plugin` | **0.4.2** | Must be first import in `hardhat.config.ts` |
| `@fhevm/mock-utils` | **0.4.2** | Required peer dep — install separately |
| `@zama-fhe/relayer-sdk` | **0.4.1–0.4.2** | Frontend SDK |
| `fhevm-contracts` | **0.2.4** | 11 pre-built contracts, `TFHE` namespace |
| `fhevm` (used by fhevm-contracts) | **^0.6.2** | Different from `@fhevm/solidity` |

```bash
npm install @fhevm/solidity
npm install --save-dev @fhevm/hardhat-plugin @fhevm/mock-utils
npm install @zama-fhe/relayer-sdk
```

---

## Two Package Families — Pick the Right One

**Do not mix these packages.** Using the wrong namespace or config class silently fails or routes to the wrong network.

| | Standalone (`@fhevm/solidity`) | `fhevm-contracts` extensions |
|---|---|---|
| FHE namespace | `FHE` | `TFHE` |
| Input type | `externalEuint64` | `einput` |
| Verify input | `FHE.fromExternal(enc, proof)` | `TFHE.asEuint64(enc, proof)` |
| ACL | `FHE.allowThis` / `FHE.allow` | `TFHE.allowThis` / `TFHE.allow` |
| Sepolia config (upcoming) | `SepoliaFHEVMConfig` from `@fhevm/solidity/config/FHEVMConfig.sol` | `SepoliaZamaFHEVMConfig` from `fhevm/config/ZamaFHEVMConfig.sol` |
| Mainnet config (v0.11.1) | `ZamaEthereumConfig` from `@fhevm/solidity/config/ZamaConfig.sol` | — |
| Local Hardhat | *(no class — plugin auto-configures)* | *(no class — plugin auto-configures)* |

> **v0.11.1 config note:** The published npm package (`@fhevm/solidity@0.11.1`) may use `ZamaConfig.sol` instead of `FHEVMConfig.sol` for the standalone config. Run `ls node_modules/@fhevm/solidity/config/` to see which files are available.

---

## Minimum Rules (always apply)

### Standalone contracts (`@fhevm/solidity`)
```
USE  : FHE namespace (import { FHE, euint64, externalEuint64 } from "@fhevm/solidity")
USE  : externalEuint64 + bytes proof → FHE.fromExternal(enc, proof) to verify
USE  : FHE.isInitialized(handle) to check if encrypted slot is initialized (not unwrap == 0)
USE  : FHE.allowThis(handle) after every encrypted assignment
USE  : FHE.allow(handle, addr) for every reader/decryptor
USE  : FHE.select() for conditional logic on ebool (never if/else on ebool)
USE  : SepoliaFHEVMConfig (testnet) / ZamaEthereumConfig (mainnet) — no hardcoded addresses
USE  : @zama-fhe/relayer-sdk for frontend (not fhevmjs)
USE  : FHE.makePubliclyDecryptable(handle) for public decryption
USE  : FHE.checkSignatures(reqId, ct, sigs) in decryption callbacks
AVOID: TFHE namespace in standalone contracts
AVOID: if/else on ebool (leaks branch information)
AVOID: euint64.unwrap(x) == 0 for init check — use FHE.isInitialized(x)
AVOID: encrypting values that don't need to be private (counters, timestamps, roles)
AVOID: uninitialized encrypted mappings — call FHE.isInitialized() before first FHE op
LIMIT: decryption batch ≤ 2048 bits total
```

### fhevm-contracts extensions (`fhevm-contracts` + `fhevm` ^0.6.x)
```
USE  : TFHE namespace (import "fhevm/lib/TFHE.sol")
USE  : einput + bytes inputProof → TFHE.asEuint64(enc, inputProof) to verify
USE  : TFHE.allowThis(handle) / TFHE.allow(handle, addr) after every assignment
USE  : SepoliaZamaFHEVMConfig from "fhevm/config/ZamaFHEVMConfig.sol"
USE  : _transferNoEvent override (NOT _update — that is OZ ERC-20, not fhevm-contracts)
USE  : super._transferNoEvent(...) first in any override
USE  : _unsafeMint(address to, uint64 amount) — address first, amount second
TRACK: _totalSupply manually — _unsafeMint does NOT auto-update it
KNOW : decimals() = 6 by default (not 18) — override if needed
KNOW : totalSupply() returns plaintext uint64 (not encrypted)
KNOW : Transfer events use _PLACEHOLDER (type(uint256).max) — not real amounts
AVOID: FHE namespace inside fhevm-contracts overrides
AVOID: SepoliaFHEVMConfig (wrong config class for fhevm-contracts)
```

### Testing (both families)
```
USE  : import { fhevm } from "hardhat"  ← named import, NOT hre.fhevm
USE  : fhevm.isMock to detect local vs. Sepolia (true = local mock, false = real network)
USE  : fhevm.createEncryptedInput(contractAddr, signerAddr).add64(val).encrypt()  ← fluent chain
USE  : encrypted.handles[0]  ← Uint8Array, index matches addXX() call order
USE  : encrypted.inputProof  ← ZK proof covering all handles in the batch
USE  : fhevm.userDecryptEuint(FhevmType.euintXX, handle, contractAddr, signer)
USE  : chai@^4 (not v5)
USE  : @fhevm/hardhat-plugin as first import in hardhat.config.ts
AVOID: hre.fhevm — plugin exposes fhevm as a named Hardhat export, not on hre
AVOID: reusing inputProof across transactions — generate fresh proof per tx
```

---

## Workflow

1. Read [SKILL.md](SKILL.md) for full routing and defaults
2. For Solidity → [references/solidity-patterns.md](references/solidity-patterns.md)
3. For fhevm-contracts / ERC-7984 → [references/oz-confidential.md](references/oz-confidential.md)
4. For testing → [references/testing.md](references/testing.md)
5. For frontend → [references/frontend-integration.md](references/frontend-integration.md)
6. For errors → [references/error-reference.md](references/error-reference.md)
7. Self-check → [references/validation.md](references/validation.md)

---

## Privacy Scope Reminder

Always state what IS and IS NOT private in any generated contract:
- Encrypted state values (balances, votes, bids): **private** — handle is public but value is not
- Mapping keys (addresses): **public** — the blockchain sees them
- Transaction sender (`msg.sender`): **public**
- Event topics: **public** — do not emit encrypted amounts in events
- `totalSupply` in ConfidentialERC20: **public** — plaintext uint64
- Mint amounts in ConfidentialERC20Mintable: **public** — emitted in Mint event
- Transfer direction (from/to): **public** — only amount is hidden
- Wrap/unwrap amounts in ConfidentialERC20Wrapped: **public** — in Wrap/Unwrap events

---

## Code Quality Reminders

### Standalone contracts
- Call `FHE.isInitialized(_balances[user])` before any FHE op on `_balances[user]` — uninitialized = bytes32(0) = crash
- Every `euintXX =` line must be immediately followed by `FHE.allowThis`
- Every `balanceOf` / `allowance` view returns a handle, not plaintext
- Provide both overloads if building ERC-7984-style: `(address, externalEuint64, bytes)` and `(address, euint64)`

### fhevm-contracts extensions
- Override point is `_transferNoEvent(address from, address to, euint64 amount, ebool isTransferable)` — not `_update`
- Call `super._transferNoEvent(...)` before adding custom logic
- After every `euintXX =` in an override: `TFHE.allowThis(handle)` + `TFHE.allow(handle, addr)`
- `_unsafeMint(address to, uint64 amount)` has NO overflow check — caller must enforce the supply invariant
- Update `_totalSupply += amount` after every `_unsafeMint`; `_totalSupply -= amount` after every `_unsafeBurn`
- `ConfidentialERC20WithErrors`: index 0 = NO_ERROR, custom codes start at index 1
- ERC-7984 is a **draft** standard — not ERC-20 compatible — always communicate this

---

## Example Imports by Package

```solidity
// ─── Standalone (@fhevm/solidity) ─────────────────────────────────────────────
import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity";
// Local Hardhat — no config class needed
// Sepolia (upcoming): import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
// Mainnet (v0.11.1): import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract MyVault /* is SepoliaFHEVMConfig for Sepolia */ {
    mapping(address => euint64) private _balances;

    function deposit(externalEuint64 encAmount, bytes calldata proof) external {
        euint64 amount = FHE.fromExternal(encAmount, proof);
        if (!FHE.isInitialized(_balances[msg.sender])) {  // ✅ isInitialized, not unwrap
            _balances[msg.sender] = FHE.asEuint64(0);
            FHE.allowThis(_balances[msg.sender]);
            FHE.allow(_balances[msg.sender], msg.sender);
        }
        _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
        FHE.allowThis(_balances[msg.sender]);
        FHE.allow(_balances[msg.sender], msg.sender);
    }
}

// ─── fhevm-contracts extension ────────────────────────────────────────────────
import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20Mintable } from
    "fhevm-contracts/contracts/token/ERC20/extensions/ConfidentialERC20Mintable.sol";

contract MyToken is SepoliaZamaFHEVMConfig, ConfidentialERC20Mintable {
    constructor(address owner) ConfidentialERC20Mintable("MyToken", "MTK", owner) {
        _unsafeMint(owner, 1_000_000); // address first, amount second; 1 MTK (decimals=6)
        _totalSupply = 1_000_000;      // must set manually — _unsafeMint doesn't do it
    }
}
```

---

## Test Pattern (Hardhat)

```typescript
// ✅ CORRECT — named import from "hardhat", NOT `import hre from "hardhat"`
import { ethers, fhevm } from "hardhat";
import { FhevmType } from "@fhevm/hardhat-plugin";

beforeEach(async function () {
    if (!fhevm.isMock) { this.skip(); } // skip on Sepolia for local-only tests
});

// Encrypt — fluent chain (all awaited together):
const encrypted = await fhevm
    .createEncryptedInput(contractAddr, signer.address)
    .add64(1_000n)   // add8 / add16 / add32 / add64 / addBool to match Solidity type
    .encrypt();
// → { handles: Uint8Array[], inputProof: Uint8Array }

await contract.deposit(encrypted.handles[0], encrypted.inputProof);

// Decrypt (signer must have FHE.allow):
const handle = await contract.balanceOf(signer.address);
const value = await fhevm.userDecryptEuint(FhevmType.euint64, handle, contractAddr, signer);
expect(value).to.equal(1_000n);
```

---

## Sepolia Contract Addresses

| Contract | Address |
|---|---|
| ACL | `0xFee8407e2f5e3Ee68ad77cAE98c434e637f516e5` |
| FHEVMExecutor | `0x687408aB54661ba0b4aeF3a44156c616c6955E07` |
| KMSVerifier | `0x9D6891A6240D6130c54ae243d8005063D05fE14b` |
| InputVerifier | `0x3a2DA6f1daE9eF988B48d9CF27523FA31a8eBE50` |

**Never hardcode these** — inherit `SepoliaFHEVMConfig` or `SepoliaZamaFHEVMConfig`. Addresses change on protocol upgrades.
