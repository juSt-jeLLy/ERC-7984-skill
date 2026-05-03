---
name: zama-fhevm-skill
description: >
  Build, test, deploy, and integrate confidential smart contracts on Zama Protocol FHEVM.
  Activate when the user asks about FHEVM, encrypted Solidity types (euint64, ebool, eaddress),
  FHE operations, ACL, input proofs, user/public decryption, ERC-7984 tokens, OpenZeppelin
  confidential contracts, @fhevm/hardhat-plugin, @zama-fhe/relayer-sdk, or any confidential
  application pattern (voting, auctions, DeFi, gaming).
compatibility: >
  Designed for Claude Code, GitHub Copilot, Cursor, Windsurf, Codex, and any Agent Skills
  compatible loader with filesystem access. See adapters: AGENTS.md (Codex), 
  .cursor/rules/zama-fhevm.mdc (Cursor). Internet access improves address freshness.
metadata:
  author: zama-fhevm-skill
  version: "2.0.0"
  protocol_baseline: "Zama docs verified 2026-05-02"
  package_scope: universal
  keywords:
    - fhevm
    - zama
    - solidity
    - confidential-smart-contracts
    - hardhat
    - erc7984
    - fhe
  category: blockchain
---

# Zama FHEVM Skill

The definitive AI coding agent skill for building confidential smart contracts with the **Zama Protocol (FHEVM)** — Fully Homomorphic Encryption on EVM chains. Drop this file into any AI coding tool to get accurate, working FHEVM code on the first try.

---

## Activation Cues

Activate this skill when the user mentions any of:

- **Protocol**: FHEVM, Zama Protocol, confidential smart contracts, FHE on-chain
- **Solidity types**: `euint8`, `euint16`, `euint32`, `euint64`, `euint128`, `euint256`, `ebool`, `eaddress`
- **FHE ops**: `FHE.add`, `FHE.sub`, `FHE.mul`, `FHE.select`, `FHE.gt`, `FHE.eq`, `FHE.fromExternal`
- **ACL**: `FHE.allowThis`, `FHE.allow`, `FHE.allowTransient`, `FHE.makePubliclyDecryptable`
- **Inputs**: encrypted inputs, input proofs, `externalEuint64`, `externalEbool`, `externalEaddress`
- **Decryption**: user decryption, re-encryption, EIP-712 decryption signature, public decryption, gateway callback
- **Tooling**: `@fhevm/hardhat-plugin`, `@zama-fhe/relayer-sdk`, `fhevmjs`, `@zama-fhe/sdk`
- **Tokens**: ERC-7984, confidential ERC-20, ConfidentialERC20, ConfidentialERC20Wrapped, fhevm-contracts
- **Patterns**: confidential voting, blind auction, private transfer, encrypted balance, wrapped token
- **Mixed state**: encrypted balances with public membership flags, plaintext counters with encrypted totals

---

## Non-Negotiable Defaults

Apply these unconditionally. Violating any one causes correctness bugs or security vulnerabilities.

1. **Use `FHE` for standalone contracts; use `TFHE` when extending `fhevm-contracts`** — Two active package families exist: standalone `@fhevm/solidity` (v0.11.1) uses the `FHE` namespace; `fhevm-contracts` (v0.2.4) uses the `TFHE` namespace internally. When writing a new contract from scratch, use `@fhevm/solidity` + `FHE`. When extending `ConfidentialERC20` or any `fhevm-contracts` base, use `TFHE` in overrides to match the package. Config class also differs: standalone → `ZamaEthereumConfig` from `@fhevm/solidity/config/ZamaConfig.sol` (v0.11.1 npm) or `SepoliaFHEVMConfig` from `@fhevm/solidity/config/FHEVMConfig.sol` (main branch — run `ls node_modules/@fhevm/solidity/config/` to confirm); fhevm-contracts → `SepoliaZamaFHEVMConfig` from `fhevm/config/ZamaFHEVMConfig.sol`.
2. **Use `externalE...` + `bytes inputProof` for fresh user inputs** — never accept raw ciphertexts without ZK proof verification.
3. **Call `FHE.fromExternal(enc, proof)` before any FHE operation** — `externalEuintXX` is untrusted until verified.
4. **Call `FHE.allowThis(handle)` after EVERY encrypted assignment** — each FHE op produces a new handle. The previous ACL entry is now stale.
5. **Call `FHE.allow(handle, addr)` for every address that must read or re-encrypt the value** — missing this returns 0 silently on re-encryption.
6. **Initialize encrypted mappings before first use** — uninitialized slots are `bytes32(0)`, not a valid handle. Use `FHE.asEuintXX(0)`. Check with `FHE.isInitialized(handle)` — **not** `euintXX.unwrap(handle) == 0` (fragile; breaks on `ebool` and `eaddress`).
7. **Use `FHE.select()` instead of `if/else` on `ebool`** — branching on encrypted booleans leaks which branch was taken.
8. **Inherit network config in your contract** — `ZamaEthereumConfig` (mainnet), `SepoliaFHEVMConfig` (testnet), nothing (local Hardhat — plugin auto-configures).
9. **Set `evmVersion: "cancun"` in `hardhat.config.ts`** — FHEVM requires Cancun transient storage and precompile opcodes.
10. **Import `@fhevm/hardhat-plugin` FIRST** in `hardhat.config.ts` — loading order determines correct setup. In test code, access the plugin via the named export: `import { fhevm } from "hardhat"` — NOT `import hre from "hardhat"; hre.fhevm`.
11. **Generate a fresh `inputProof` per transaction** — proofs are bound to `(contractAddress, msg.sender)` and expire after one use.
12. **Never hardcode Zama infrastructure addresses** — inherit `ZamaEthereumConfig` / `SepoliaFHEVMConfig` instead. Addresses change with upgrades.
13. **`euintXX` return values from `view` functions are handles, not plaintext** — callers re-encrypt off-chain. Never imply they see the raw value.
14. **Keep plaintext values plaintext** — flags, roles, timestamps, counters, and loop bounds should stay `uint` / `bool` unless the privacy model truly requires encryption. Unnecessary encryption wastes gas and adds ACL complexity.
15. **Decryption batches must stay under 2048 bits total** — sum the bit widths of all handles in one `requestDecryption` call.

---

## Default Workflow

Follow this order for any new confidential contract task:

1. **Load architecture context** → [`references/architecture.md`](references/architecture.md)
2. **Choose the right Solidity pattern** → [`references/solidity-patterns.md`](references/solidity-patterns.md)
3. **Write the contract** applying defaults above. For each encrypted state mutation:
   - Identify every assignment that produces a new handle
   - Add `FHE.allowThis` + `FHE.allow` for every relevant actor immediately after
   - Keep plaintext values plaintext
4. **Write matching tests** using `fhevm` (named import from `"hardhat"`) → [`references/testing.md`](references/testing.md)
5. **Add frontend/decryption code** if needed → [`references/frontend-integration.md`](references/frontend-integration.md)
6. **Deploy** → [`references/deployment.md`](references/deployment.md)
7. **Self-check** against the validation checklist → [`references/validation.md`](references/validation.md)

---

## Architecture Rules

- The EVM stores ciphertext **handles** (`bytes32`) — not ciphertexts. Computation is offloaded to Zama's coprocessor.
- Fresh encrypted user inputs are created off-chain via `@zama-fhe/relayer-sdk`, submitted on-chain with a ZK `inputProof`, and verified via `FHE.fromExternal`.
- The **ACL contract** tracks who can use or decrypt each handle. Permissions must be explicitly granted after every handle-producing operation.
- **User decryption** = off-chain re-encryption flow. User signs an EIP-712 message authorizing their relayer public key. KMS re-encrypts the handle under that key. No on-chain state change.
- **Public decryption** = `FHE.makePubliclyDecryptable(handle)` marks a handle as decryptable by the gateway, then the plaintext is returned on-chain to a callback function. Use `FHE.checkSignatures` in the callback.
- FHE operations are **symbolic** on-chain — actual homomorphic computation happens asynchronously in the coprocessor. Reads after write may need a short delay on testnets.

---

## Output Requirements by Task

### New contract request
Produce:
- Solidity contract with correct imports, `externalE...` inputs, ACL grants, and network config inheritance
- Hardhat test file using `import { fhevm } from "hardhat"` with `fhevm.createEncryptedInput(...)` and `fhevm.userDecryptEuint(...)`
- Deployment script or task
- Minimal frontend snippet for any user-interaction or decryption flow
- Short note on privacy scope (what IS and IS NOT private) and version assumptions

### Debug or review request
Check for:
- `TFHE` usage (deprecated) → replace with `FHE`
- `einput` patterns (deprecated) → replace with `externalE...` + `inputProof`
- Deprecated `requestDecryption` oracle patterns → use `FHE.makePubliclyDecryptable`
- Missing `ZamaEthereumConfig` / `SepoliaFHEVMConfig` inheritance
- Missing `FHE.allowThis` / `FHE.allow` / `FHE.allowTransient` after any encrypted assignment
- Missing or mismatched `inputProof` parameter
- `view` functions returning plaintext from encrypted values (impossible without decryption)
- Unnecessary encryption of plaintext-safe values (timestamps, counters, roles)
- Ciphertext-heavy loops → prefer plaintext loop bounds with encrypted accumulators
- Decryption batch exceeding 2048 bits

### ERC-7984 / OpenZeppelin request
- State that **ERC-7984 is a draft standard** and is not ERC-20 compatible
- Prefer `ConfidentialERC20` from `fhevm-contracts` as the starting point
- When extending `fhevm-contracts`: use `TFHE` namespace + `einput` + `SepoliaZamaFHEVMConfig`; internal override point is `_transferNoEvent` (not `_update` — that is OpenZeppelin ERC-20 API, not fhevm-contracts)
- After any new encrypted state assignment in an override, call `TFHE.allowThis(handle)` + `TFHE.allow(handle, addr)` for each authorized actor
- Do not claim participant addresses are private on-chain unless the design hides them elsewhere
- `totalSupply` is plaintext `uint64`; `decimals()` defaults to `6` (not 18); update `_totalSupply` manually after `_unsafeMint`/`_unsafeBurn`
- See [`references/oz-confidential.md`](references/oz-confidential.md)

---

## Required Correctness Checks

Before returning any contract code, verify all of the following:

1. Every `externalE...` parameter has a matching `bytes inputProof` and is converted via `FHE.fromExternal(enc, proof)`.
2. Every line that assigns to an encrypted state variable (`euintXX =`) is immediately followed by `FHE.allowThis`.
3. Every actor who must read or re-encrypt a handle has `FHE.allow(handle, actorAddress)`.
4. No infrastructure addresses (ACL, KMS, coprocessor) are hardcoded — use config inheritance.
5. Tests import `fhevm` as a named export from `"hardhat"` and use `fhevm.createEncryptedInput(...)` / `fhevm.userDecryptEuint(...)` — not `hre.fhevm`.
6. `@fhevm/hardhat-plugin` is the first import in `hardhat.config.ts`.
7. `evmVersion: "cancun"` is set in Hardhat solidity settings.
8. Public decryption uses `FHE.makePubliclyDecryptable(handle)` and the callback calls `FHE.checkSignatures`.
9. Decryption batch bit-width sum ≤ 2048 bits.
10. `fhevm-contracts` extensions override `_transferNoEvent` (not `_update`) and call `super._transferNoEvent(...)` first.

---

## Version Guardrails

Apply these to avoid obsolete patterns. Note the **two active package families** that coexist:

| Context | Old / deprecated | Current / correct |
|---|---|---|
| **Standalone contracts** | `TFHE` namespace (old `fhevm` package) | `FHE` namespace (`@fhevm/solidity`) |
| **Standalone contracts** | `einput` parameter type | `externalEuint64` / `externalEbool` / etc. |
| **Standalone contracts** | `SepoliaZamaFHEVMConfig` | `SepoliaFHEVMConfig` from `@fhevm/solidity/config/FHEVMConfig.sol` |
| **fhevm-contracts extensions** | `FHE` namespace (wrong package) | `TFHE` namespace (matches `fhevm` ^0.6.x which fhevm-contracts depends on) |
| **fhevm-contracts extensions** | `externalEuint64` | `einput` (what fhevm-contracts uses internally) |
| **fhevm-contracts extensions** | `SepoliaFHEVMConfig` | `SepoliaZamaFHEVMConfig` from `"fhevm/config/ZamaFHEVMConfig.sol"` |
| **Both** | `fhevmjs` | `@zama-fhe/relayer-sdk` (use `fhevmjs` as migration reference only) |
| **Both** | Hardcoded coprocessor addresses | Config inheritance |
| **Both** | `gateway.requestDecryption()` oracle API | `FHE.makePubliclyDecryptable(handle)` (standalone) |

**Package versions (verified 2026-05-02 from npm + official hardhat template):**
- `@fhevm/solidity`: **v0.11.1** (standalone, `FHE` namespace; config in `ZamaConfig.sol` for v0.11.1, `FHEVMConfig.sol` for main branch)
- `@fhevm/hardhat-plugin`: **v0.4.2** (must be first import in `hardhat.config.ts`)
- `@fhevm/mock-utils`: **v0.4.2** (required peer dependency of hardhat-plugin — install separately)
- `@zama-fhe/relayer-sdk`: **v0.4.1–0.4.2** (frontend SDK)
- `fhevm-contracts`: **v0.2.4** (depends on `fhevm` ^0.6.2, uses `TFHE` namespace)
- `fhevm` (core, used by fhevm-contracts): **^0.6.2** (NOT the same as `@fhevm/solidity`)

**Sepolia contract addresses (from `FHEVMConfig.getSepoliaConfig()`):**
- ACL: `0xFee8407e2f5e3Ee68ad77cAE98c434e637f516e5`
- FHEVMExecutor: `0x687408aB54661ba0b4aeF3a44156c616c6955E07`
- KMSVerifier: `0x9D6891A6240D6130c54ae243d8005063D05fE14b`
- InputVerifier: `0x3a2DA6f1daE9eF988B48d9CF27523FA31a8eBE50`
- **Never hardcode these** — use `SepoliaFHEVMConfig` / `SepoliaZamaFHEVMConfig` instead.

When existing code uses deprecated patterns, migrate to current API before extending it.

---

## When Documentation Conflicts

Priority order (highest wins):

1. Current Zama Protocol docs (https://docs.zama.org/protocol)
2. `@fhevm/hardhat-plugin` and `@zama-fhe/relayer-sdk` current docs
3. OpenZeppelin confidential contracts docs (move fast, breaking changes possible)
4. ERC-7984 draft specification
5. `fhevmjs` examples — migration reference only, not the default implementation path

---

## Quick Reference

```solidity
// Minimal correct confidential vault — local Hardhat (no config inheritance)
// For Sepolia: add "is SepoliaFHEVMConfig"
// For mainnet: add "is ZamaEthereumConfig"
import { FHE, euint64, externalEuint64 } from "@fhevm/solidity";

contract Vault {
    mapping(address => euint64) private _balances;

    function deposit(externalEuint64 encAmount, bytes calldata proof) external {
        euint64 amount = FHE.fromExternal(encAmount, proof); // verify ZK proof
        _ensureInit(msg.sender);
        _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
        FHE.allowThis(_balances[msg.sender]);          // REQUIRED — new handle
        FHE.allow(_balances[msg.sender], msg.sender); // REQUIRED — user can re-encrypt
    }

    function balanceOf(address user) external view returns (euint64) {
        return _balances[user]; // returns handle; user re-encrypts off-chain
    }

    function _ensureInit(address user) internal {
        if (!FHE.isInitialized(_balances[user])) {  // ✅ correct check — not unwrap() == 0
            _balances[user] = FHE.asEuint64(0);
            FHE.allowThis(_balances[user]);
            FHE.allow(_balances[user], user);
        }
    }
}
```

---

## Reference Map

| Topic | File |
|---|---|
| FHEVM architecture and FHE on-chain | [`references/architecture.md`](references/architecture.md) |
| Dev environment setup (Hardhat + React) | [`references/setup.md`](references/setup.md) |
| Solidity patterns and contract structure | [`references/solidity-patterns.md`](references/solidity-patterns.md) |
| Encrypted types: euint8–256, ebool, eaddress | [`references/encrypted-types.md`](references/encrypted-types.md) |
| FHE operations: arithmetic, compare, select | [`references/fhe-operations.md`](references/fhe-operations.md) |
| ACL: allowThis, allow, allowTransient | [`references/access-control.md`](references/access-control.md) |
| Input proofs: ZK proof generation and use | [`references/input-proofs.md`](references/input-proofs.md) |
| Decryption: user (EIP-712) and public | [`references/decryption.md`](references/decryption.md) |
| Frontend: fhevmjs + @zama-fhe/relayer-sdk + React | [`references/frontend-integration.md`](references/frontend-integration.md) |
| Testing with @fhevm/hardhat-plugin | [`references/testing.md`](references/testing.md) |
| Deploying to Sepolia and mainnet | [`references/deployment.md`](references/deployment.md) |
| OpenZeppelin confidential + ERC-7984 | [`references/oz-confidential.md`](references/oz-confidential.md) |
| 50+ errors with root cause + fix | [`references/error-reference.md`](references/error-reference.md) |
| 20 anti-patterns with corrections | [`references/anti-patterns.md`](references/anti-patterns.md) |
| Network addresses and faucets | [`references/addresses.md`](references/addresses.md) |
| Validation prompts and checklist | [`references/validation.md`](references/validation.md) |
| Distribution and installation guide | [`references/distribution.md`](references/distribution.md) |
| AI agent demo: prompt → compiled working app | [`references/demo.md`](references/demo.md) |

## Examples

| Contract / File | What It Demonstrates |
|---|---|
| [`examples/hardhat.config.ts`](examples/hardhat.config.ts) | Canonical Hardhat config with all required settings |
| [`examples/ConfidentialCounter.sol`](examples/ConfidentialCounter.sol) | Simplest possible FHEVM contract — start here |
| [`examples/ConfidentialToken.sol`](examples/ConfidentialToken.sol) | Standalone confidential token (FHE namespace, externalEuint64) |
| [`examples/ConfidentialTokenFhevmContracts.sol`](examples/ConfidentialTokenFhevmContracts.sol) | Token extending fhevm-contracts (TFHE namespace, einput, SepoliaZamaFHEVMConfig) |
| [`examples/ConfidentialVoting.sol`](examples/ConfidentialVoting.sol) | Blind voting with `FHE.makePubliclyDecryptable` |
| [`examples/ConfidentialAuction.sol`](examples/ConfidentialAuction.sol) | Sealed-bid auction with encrypted running maximum |
| [`examples/frontend-integration.tsx`](examples/frontend-integration.tsx) | React + @zama-fhe/relayer-sdk full integration |
| [`examples/test-example.ts`](examples/test-example.ts) | Hardhat test suite with encrypt/decrypt helpers |

---

## When Something Goes Wrong

1. Check [`references/error-reference.md`](references/error-reference.md) — 50+ real errors mapped to root cause and fix
2. Run through the **Quick Diagnostic Checklist** at the top of that file
3. Check [`references/anti-patterns.md`](references/anti-patterns.md) — 20 documented mistakes with corrections
4. Run `node scripts/validate-skill.mjs` to verify skill file structure is intact
