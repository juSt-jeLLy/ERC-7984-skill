# Validation Prompts and Correctness Checklist

Use this file to validate skill output quality and to self-check generated contracts before presenting them to the user.

---

## Self-Check Checklist

Run through every item before returning contract code to the user:

### Input Handling
- [ ] Every `externalE...` parameter has a matching `bytes calldata proof` parameter
- [ ] Every external input is converted via `FHE.fromExternal(enc, proof)` before any FHE operation
- [ ] No raw `externalE...` value is passed directly to `FHE.add`, `FHE.eq`, etc.

### ACL / Access Control
- [ ] Every line that assigns to an `euintXX` state variable is immediately followed by `FHE.allowThis`
- [ ] Every actor who must re-encrypt or read a handle has `FHE.allow(handle, actorAddress)`
- [ ] `FHE.allowTransient` is used for temporary/intermediate handles, not persistent ones
- [ ] No Zama infrastructure addresses (ACL, KMS, coprocessor) are hardcoded

### Initialization
- [ ] Every encrypted mapping is initialized via `_ensureInit()` or equivalent before first FHE operation
- [ ] `FHE.asEuintXX(0)` is used for initialization (not `bytes32(0)`)

### Control Flow
- [ ] No `if/else` branching directly on `ebool` values or `euintXX.unwrap()` results
- [ ] `FHE.select(condition, trueVal, falseVal)` is used instead

### Network Configuration
- [ ] Contract inherits `SepoliaFHEVMConfig` (Sepolia), `ZamaEthereumConfig` (mainnet), or nothing (local)
- [ ] `@fhevm/hardhat-plugin` is the first import in `hardhat.config.ts`
- [ ] `evmVersion: "cancun"` is set in Hardhat solidity config

### Decryption
- [ ] Public decryption uses `FHE.makePubliclyDecryptable(handle)` before calling Gateway
- [ ] Decryption callback calls `FHE.checkSignatures(reqId, ct, sigs)`
- [ ] Total bit width of handles in any single decryption batch ≤ 2048 bits
- [ ] User decryption flow uses `fhevm.userDecryptEuint` in tests (named import from `"hardhat"`)

### Testing
- [ ] Tests import `fhevm` via `import { ethers, fhevm } from "hardhat"` (not `import hre from "hardhat"`)
- [ ] Tests use `fhevm.createEncryptedInput(...).addXX(val).encrypt()` fluent chain to produce `{ handles, inputProof }`
- [ ] Tests use `fhevm.userDecryptEuint(FhevmType.euintXX, handle, contractAddr, signer)` to decrypt and assert
- [ ] `fhevm.isMock` is checked to gate local-only or Sepolia-only test suites

### ERC-7984 / fhevm-contracts Specific
- [ ] `_transferNoEvent(address from, address to, euint64 amount, ebool isTransferable)` is overridden (NOT `_update()`) with `super._transferNoEvent(...)` called first
- [ ] After every `euintXX =` in a `_transferNoEvent` override: `TFHE.allowThis` + `TFHE.allow` re-granted
- [ ] `_unsafeMint(to, amount)` followed by `_totalSupply += amount` (both required)
- [ ] Contract clearly states it is NOT ERC-20 compatible (ERC-7984 is a draft standard)
- [ ] `ConfidentialERC20WithErrors` custom error codes start at index 1 (index 0 = NO_ERROR)
- [ ] Callback variants are guarded with reentrancy protection if used

---

## Agent Evaluation Prompts

Use these prompts in a fresh Zama FHEVM Hardhat template project to evaluate skill quality.

### Prompt 1 — Simplest possible contract
```
Write an encrypted counter using FHEVM. The counter should be private per user.
Each user can increment their counter by an encrypted amount. They can retrieve
their current counter value as a handle for off-chain decryption.
```
**Expected result**: Contract with `externalEuint64` input, `FHE.fromExternal`, `FHE.add`, `FHE.allowThis`, `FHE.allow`, and matching Hardhat test.

### Prompt 2 — Transfer flow
```
Write a confidential token contract using FHEVM where balances are encrypted.
Users should be able to deposit encrypted amounts, transfer to other users, and
retrieve their balance handle for off-chain decryption.
```
**Expected result**: Correct `FHE.select`-based transfer (not if/else), `_ensureInit`, ACL re-granted on both sender and receiver.

### Prompt 3 — Voting with public reveal
```
Write a confidential voting contract using FHEVM. Votes are encrypted. After
the voting period ends, the owner can trigger public decryption to reveal the
final tally on-chain.
```
**Expected result**: Uses `FHE.makePubliclyDecryptable` + `Gateway.requestDecryption` + callback with `FHE.checkSignatures`.

### Prompt 4 — Debug request
```
Fix this FHEVM contract:
    _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
    // missing FHE.allowThis and FHE.allow
    if (ebool.unwrap(FHE.ge(amount, _balances[to])) != 0) {
        // branch on encrypted bool
    }
```
**Expected result**: Agent identifies the missing ACL grants and the forbidden if/else on ebool. Corrects both.

### Prompt 5 — ERC-7984 token
```
Create a confidential ERC-7984 token using OpenZeppelin's fhevm-contracts library.
Users can wrap plaintext ERC-20 tokens into encrypted balances and transfer them
privately.
```
**Expected result**: Extends `ConfidentialERC20Wrapped`, overrides `_update()` with ACL re-grant, notes ERC-7984 is a draft.

### Prompt 6 — Anti-pattern detection
```
Review this contract and identify any FHEVM correctness issues:
    mapping(address => euint64) private _scores;
    function addScore(uint64 plainAmount) external {
        _scores[msg.sender] = FHE.add(_scores[msg.sender], FHE.asEuint64(plainAmount));
    }
```
**Expected result**: Agent identifies: (1) uninitialized mapping, (2) missing `FHE.allowThis` after assignment, (3) missing `FHE.allow` for user.

---

## Structural Validator

Run after any edits to verify file structure is intact:

```bash
node scripts/validate-skill.mjs
```

---

## Version Compatibility Test

Ask the skill: "What is the current way to handle public decryption in FHEVM?"

**Correct answer must include**:
- `FHE.makePubliclyDecryptable(handle)` — not the old oracle-request API
- `Gateway.requestDecryption` with a callback selector
- `FHE.checkSignatures` in the callback

**Red flags** (outdated answer):
- Only mentions `TFHE.allowPublicDecryption`
- Mentions `gateway.requestDecryption()` as a standalone API without `FHE.makePubliclyDecryptable`
- References `einput` types instead of `externalEuint64`

---

## Correctness Scoring Rubric

For each generated contract, score 1 point per item:

| Check | Points |
|---|---|
| Uses `FHE` namespace (not `TFHE`) | 1 |
| All external inputs use `externalE...` + `proof` | 1 |
| All `FHE.fromExternal` calls present | 1 |
| All `FHE.allowThis` calls after assignments | 1 |
| All `FHE.allow` calls for relevant actors | 1 |
| No hardcoded Zama addresses | 1 |
| No `if/else` on `ebool` | 1 |
| Initialization handled | 1 |
| Network config inherited correctly | 1 |
| Hardhat test uses `fhevm` named import from `"hardhat"` | 1 |
| **Maximum** | **10** |

A score of 10/10 means the contract is structurally correct. Scores below 8/10 indicate missing ACL or input handling that will cause runtime failures.
