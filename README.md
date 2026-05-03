# Zama FHEVM Skill

A universal AI coding agent skill for building confidential smart contracts on the **Zama Protocol (FHEVM)**. Drop it into Claude Code, GitHub Copilot, Cursor, Windsurf, or Codex and get accurate, working FHEVM code on the first attempt.

## What This Skill Covers

- FHEVM architecture and how on-chain FHE computation works
- Hardhat template setup and project bootstrap
- All encrypted Solidity types (`euint8` through `euint256`, `ebool`, `eaddress`)
- FHE operations: arithmetic, comparison, conditional select
- Access control: `FHE.allowThis`, `FHE.allow`, `FHE.allowTransient`
- Input proofs: off-chain ZK proof generation and on-chain verification
- User decryption (EIP-712 re-encryption) and public decryption (`FHE.makePubliclyDecryptable`)
- Frontend integration with `@zama-fhe/relayer-sdk` and React
- Hardhat testing with `@fhevm/hardhat-plugin` and `fhevm` (named import from `"hardhat"`)
- Deployment to Sepolia testnet and Zama mainnet
- **Complete `fhevm-contracts` v0.2.4 reference** — all 11 contracts (tokens, governance, finance, utils)
- **ERC-7984 confidential token standard** (draft) with ground-truth API
- **50+ real errors** with root cause analysis and fixes
- **20 documented anti-patterns** with corrections
- **8 production-ready code examples**

## Quick Start

1. Install into your project (see [Installation](#installation))
2. Ask your AI tool for a confidential contract:
   - *"Write a confidential voting contract using FHEVM"*
   - *"Build a confidential ERC-7984 token using fhevm-contracts"*
   - *"Wrap USDC into a confidential token with ConfidentialERC20Wrapped"*
   - *"Debug this FHEVM error: TFHESenderNotAllowed"*
3. The skill routes to the right reference file and applies all correctness checks automatically

## Installation

### Claude Code
```bash
cp -r zama-fhevm-skill/ .skills/zama-fhevm-skill/
/load .skills/zama-fhevm-skill/SKILL.md
```

### GitHub Copilot (Agent Skills)
```bash
# Project-scoped
cp -r zama-fhevm-skill/ .github/skills/zama-fhevm-skill/

# Or user-scoped
cp -r zama-fhevm-skill/ ~/.copilot/skills/zama-fhevm-skill/
```

### Cursor
```bash
mkdir -p .cursor/rules
cp zama-fhevm-skill/.cursor/rules/zama-fhevm.mdc .cursor/rules/
```

### Codex
```bash
cp -r zama-fhevm-skill/ .agents/skills/zama-fhevm-skill/

# Or use plain-markdown adapter
cp zama-fhevm-skill/AGENTS.md ./AGENTS.md
```

### skills.sh
```bash
npx skills add <your-github-username>/zama-fhevm-skill
```

## The Two Package Families — Read This First

There are two active package families. Using the wrong one silently routes to the wrong network or causes compile errors.

| | Standalone (new) | fhevm-contracts extensions |
|---|---|---|
| **Package** | `@fhevm/solidity` v0.11.1 | `fhevm-contracts` v0.2.4 + `fhevm` ^0.6.x |
| **FHE namespace** | `FHE` | `TFHE` |
| **Input type** | `externalEuint64` | `einput` |
| **Verify input** | `FHE.fromExternal(enc, proof)` | `TFHE.asEuint64(enc, proof)` |
| **ACL** | `FHE.allowThis` / `FHE.allow` | `TFHE.allowThis` / `TFHE.allow` |
| **Mainnet config** (v0.11.1 npm) | `ZamaEthereumConfig` from `ZamaConfig.sol` | — |
| **Sepolia config** (main branch) | `SepoliaFHEVMConfig` from `FHEVMConfig.sol` | `SepoliaZamaFHEVMConfig` from `ZamaFHEVMConfig.sol` |
| **Config import base** | `@fhevm/solidity/config/` | `fhevm/config/` |

> **v0.11.1 note:** Run `ls node_modules/@fhevm/solidity/config/` to confirm which config file is present in your installed version — the file name differs between the npm release and the main branch.

When **writing a new contract from scratch**, use `@fhevm/solidity` + `FHE`.
When **extending** `ConfidentialERC20`, `ConfidentialERC20Votes`, or any `fhevm-contracts` base, use `TFHE` in your overrides to match the library.

## Three Rules to Keep in Mind

1. **Know which package you're on** — standalone uses `FHE` + `externalEuint64`; `fhevm-contracts` extensions use `TFHE` + `einput`. Config class names differ too.
2. **Every encrypted state mutation** produces a new handle — always call `allowThis` + `allow` immediately after, or the next read will fail silently.
3. **Plaintext values** (timestamps, counters, flags, roles) should stay plaintext unless the privacy model truly requires encryption.

**Initialization check:** Use `FHE.isInitialized(handle)` — not `euint64.unwrap(handle) == 0`. The unwrap pattern breaks on `ebool` and `eaddress`.

**Testing import:** `import { fhevm } from "hardhat"` (named export) — not `import hre from "hardhat"; hre.fhevm`. Use `fhevm.isMock` to gate local-only vs. Sepolia tests.

## Adapter Matrix

| File | Best for |
|---|---|
| `SKILL.md` | Claude Code, Copilot, Agent Skills loaders |
| `AGENTS.md` | Codex, plain-markdown environments |
| `.cursor/rules/zama-fhevm.mdc` | Cursor project or global rule |
| `agents/openai.yaml` | Codex app metadata |

## Validate Structure

```bash
node scripts/validate-skill.mjs
```

## Version Baseline

Protocol docs verified: **2026-05-02**

| Package | Version | Notes |
|---|---|---|
| `@fhevm/solidity` | **v0.11.1** | Standalone; `FHE` namespace; config in `ZamaConfig.sol` (npm) or `FHEVMConfig.sol` (main branch) |
| `@fhevm/hardhat-plugin` | **v0.4.2** | Must be first import in `hardhat.config.ts` |
| `@fhevm/mock-utils` | **v0.4.2** | Required peer dep — `npm install --save-dev @fhevm/mock-utils` |
| `@zama-fhe/relayer-sdk` | **v0.4.1–0.4.2** | Frontend relayer SDK (use instead of `fhevmjs` for new projects) |
| `fhevm-contracts` | **v0.2.4** (2025-03-06) | 11 contracts; `TFHE` namespace; depends on `fhevm` ^0.6.2 |
| `fhevm` (used by fhevm-contracts) | **^0.6.2** | NOT the same as `@fhevm/solidity` |

Key API notes:
- `FHE` namespace for standalone; `TFHE` for `fhevm-contracts` extensions
- `externalEuint64` for standalone inputs; `einput` in `fhevm-contracts` interfaces
- Config class for v0.11.1 standalone: `ZamaEthereumConfig` / check `ls node_modules/@fhevm/solidity/config/`
- `SepoliaZamaFHEVMConfig` for fhevm-contracts extensions
- `FHE.makePubliclyDecryptable` for public decryption (standalone)
- `ConfidentialERC20.decimals()` returns `6` by default (not 18)
- `ConfidentialERC20.totalSupply()` returns plaintext `uint64`
- `_transferNoEvent` is the override point in fhevm-contracts (NOT `_update`)
- `fhevm.isMock` is `true` on local Hardhat, `false` on Sepolia/mainnet

## File Structure

```
zama-fhevm-skill/
├── SKILL.md                    ← Main entry point (load this into your AI tool)
├── AGENTS.md                   ← Codex / plain-markdown adapter
├── README.md                   ← This file
├── agents/openai.yaml          ← Codex metadata
├── .cursor/rules/zama-fhevm.mdc ← Cursor adapter
├── scripts/validate-skill.mjs  ← Structural validator (0 errors)
├── references/                 ← 18 technical reference files
│   ├── architecture.md         ← How FHEVM works end-to-end
│   ├── setup.md                ← Hardhat + React project setup
│   ├── solidity-patterns.md    ← Contract design patterns
│   ├── encrypted-types.md      ← euint8–256, ebool, eaddress
│   ├── fhe-operations.md       ← Arithmetic, comparison, select
│   ├── access-control.md       ← allowThis, allow, allowTransient
│   ├── input-proofs.md         ← ZK proof generation and verification
│   ├── decryption.md           ← User (EIP-712) and public decryption
│   ├── frontend-integration.md ← fhevmjs + @zama-fhe/relayer-sdk + React
│   ├── testing.md              ← @fhevm/hardhat-plugin test patterns
│   ├── deployment.md           ← Sepolia and mainnet deployment
│   ├── oz-confidential.md      ← ALL 11 fhevm-contracts with ground-truth API
│   ├── error-reference.md      ← 50+ errors with root cause + fix
│   ├── anti-patterns.md        ← 20 documented mistakes with corrections
│   ├── addresses.md            ← Network addresses and faucets
│   ├── validation.md           ← Pre-deploy checklist
│   ├── distribution.md         ← Publishing and distribution guide
│   └── demo.md                 ← AI agent demo: prompt → compiled working app
└── examples/                   ← 8 production-ready examples
    ├── hardhat.config.ts        ← Canonical Hardhat config
    ├── ConfidentialCounter.sol  ← Start here — simplest FHEVM contract
    ├── ConfidentialToken.sol    ← Standalone token (FHE, externalEuint64)
    ├── ConfidentialTokenFhevmContracts.sol ← fhevm-contracts extension (TFHE, einput)
    ├── ConfidentialVoting.sol   ← Blind voting with public decryption
    ├── ConfidentialAuction.sol  ← Sealed-bid auction
    ├── frontend-integration.tsx ← React + relayer-sdk integration
    └── test-example.ts          ← Hardhat test suite
```

## Key fhevm-contracts Facts

When working with `fhevm-contracts` v0.2.4, these facts are non-negotiable:

- **11 contracts**: ConfidentialERC20 (abstract), ConfidentialERC20Mintable, ConfidentialERC20WithErrors, ConfidentialERC20WithErrorsMintable, ConfidentialERC20Wrapped, ConfidentialWETH, ConfidentialERC20Votes, ConfidentialGovernorAlpha, ConfidentialVestingWallet, ConfidentialVestingWalletCliff, EncryptedErrors
- **decimals() = 6** by default — not 18. Override if needed.
- **totalSupply is plaintext uint64** — update it manually after `_unsafeMint` / `_unsafeBurn`
- **Transfer events** use `_PLACEHOLDER = type(uint256).max` for amounts (base contract) or `transferId` counter (WithErrors variant) — never real amounts
- **ConfidentialERC20Wrapped**: source ERC-20 must have `decimals() >= 6`; `maxDecryptionDelay ≤ 1 day`; `isAccountRestricted` blocks movement during pending unwrap
- **ConfidentialERC20Votes**: delegation leaks the delegator's encrypted balance to the delegatee
- **EncryptedErrors**: index 0 is always NO_ERROR; start custom codes at index 1

See [`references/oz-confidential.md`](references/oz-confidential.md) for the complete ground-truth API reference.
