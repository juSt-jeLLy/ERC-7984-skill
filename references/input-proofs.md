# Input Proofs

## What Is an Input Proof?

When a user submits an encrypted value to an FHEVM contract, they must include a **ZK (zero-knowledge) proof** alongside it. This proof cryptographically demonstrates that:

1. The ciphertext is well-formed and correctly encrypted
2. The value is within range for the target type
3. The ciphertext was created specifically for this **contract address** and this **sender address**

Without the input proof, a malicious user could submit arbitrary bytes as a ciphertext, or replay someone else's ciphertext in a different context.

## Key Properties of Input Proofs

- **Bound to a specific `(contractAddress, senderAddress)` pair** — a proof generated for one combination is invalid for another
- **Single-use** — never reuse a proof across transactions; generate a fresh one per tx
- **Network-specific** — a Sepolia proof is invalid on mainnet and vice versa
- **Type-checked** — the proof certifies the type (`euint64`, `euint32`, etc.) and range

## Solidity Side: `FHE.fromExternal()`

```solidity
// WRONG: using externalEuintXX directly in FHE operations
function deposit(externalEuint64 encAmount, bytes calldata proof) external {
    _balance = FHE.add(_balance, encAmount);  // ❌ type error + unverified
}

// CORRECT: verify first, then use
function deposit(externalEuint64 encAmount, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(encAmount, proof);  // ✅ verify + convert
    _balance = FHE.add(_balance, amount);
    FHE.allowThis(_balance);
    FHE.allow(_balance, msg.sender);
}
```

**`FHE.fromExternal(enc, proof)` does three things:**
1. Verifies the ZK proof against the KMS
2. Registers the ciphertext handle with the ACL
3. Returns a valid `euintXX` handle you can use in FHE operations

## Multiple Inputs in One Call

```solidity
function swap(
    externalEuint64 encAmountIn,
    externalEuint64 encMinAmountOut,
    bytes calldata proof  // single proof covers both inputs
) external {
    euint64 amountIn     = FHE.fromExternal(encAmountIn, proof);
    euint64 minAmountOut = FHE.fromExternal(encMinAmountOut, proof);
    // ...
}
```

A single `proof` blob can contain proofs for multiple encrypted inputs added in the same `createEncryptedInput` session.

## Frontend Side: Generating Input Proofs

Using `@zama-fhe/sdk` (Foundry/React template):

```typescript
import { getInstance } from "./fhevm";
// getInstance() returns a configured FhevmInstance

async function depositEncrypted(
  contract: ethers.Contract,
  signer: ethers.Signer,
  amount: bigint
): Promise<void> {
  const instance = await getInstance();
  
  // ALWAYS fetch live addresses — never hardcode
  const contractAddress = await contract.getAddress();
  const userAddress = await signer.getAddress();
  
  // Create encrypted input session for this specific (contract, sender) pair
  const input = instance.createEncryptedInput(contractAddress, userAddress);
  
  // Add the value — must match Solidity parameter type exactly
  // externalEuint64 → input.add64()
  input.add64(amount);  // amount must be <= 2^64 - 1
  
  // Encrypt + generate ZK proof
  const { handles, inputProof } = await input.encrypt();
  
  // handles[0] is the externalEuint64 parameter
  // inputProof is the bytes calldata proof parameter
  await contract.deposit(handles[0], inputProof);
}
```

### Multiple Inputs

```typescript
const input = instance.createEncryptedInput(contractAddress, userAddress);
input.add64(amountIn);       // first externalEuint64
input.add64(minAmountOut);   // second externalEuint64
input.addBool(isMarket);     // an externalEbool

const { handles, inputProof } = await input.encrypt();

// handles[0] → first externalEuint64
// handles[1] → second externalEuint64
// handles[2] → externalEbool
// inputProof → single proof for all three

await contract.swap(handles[0], handles[1], handles[2], inputProof);
```

## Hardhat Testing: Input Proofs

In tests, use `fhevm` (named import from `"hardhat"`) to create encrypted inputs — this runs in cleartext mock mode locally:

```typescript
import { ethers, fhevm } from "hardhat";  // named import — NOT `import hre from "hardhat"`
import { FhevmType } from "@fhevm/hardhat-plugin";

it("should deposit correctly", async function () {
  const [owner] = await ethers.getSigners();
  const contract = await ethers.getContractAt("Vault", deployedAddress);
  const contractAddr = await contract.getAddress();

  // Fluent chain: createEncryptedInput(...).add64(...).encrypt()
  const encrypted = await fhevm
    .createEncryptedInput(contractAddr, owner.address)
    .add64(1000n)
    .encrypt();
  // encrypted.handles[0] — Uint8Array handle for this value
  // encrypted.inputProof  — ZK proof binding handle to (contract, owner)
  
  // Send the transaction
  await contract.connect(owner).deposit(encrypted.handles[0], encrypted.inputProof);
  
  // Decrypt and check — owner must have FHE.allow(handle, owner.address)
  const balanceHandle = await contract.balanceOf(owner.address);
  const balance = await fhevm.userDecryptEuint(
    FhevmType.euint64,
    balanceHandle,
    contractAddr,
    owner
  );
  expect(balance).to.equal(1000n);
});
```

## Common Input Proof Errors

| Error | Cause | Fix |
|---|---|---|
| `Proof verification failed` | Wrong contract address in proof | Use `await contract.getAddress()`, never hardcode |
| `Proof bound to wrong contract` | Reused proof from different tx/contract | Generate fresh proof per transaction |
| `InputLengthAbove64Bytes` | Used `add256()` but contract expects `euint64` | Match `addXX()` call to Solidity parameter type |
| `Invalid ZK proof` | Wrong network or stale proof | Check you're on the right network; generate fresh proof |
| `Proof verification failed` | Value out of range for type | Ensure value fits: `euint8` ≤ 255, `euint64` ≤ 2^64-1 |

## Type Matching Table

Always match the frontend `add` method to the Solidity external type:

| Solidity Parameter | Frontend Call |
|---|---|
| `externalEuint8 enc` | `input.add8(value)` |
| `externalEuint16 enc` | `input.add16(value)` |
| `externalEuint32 enc` | `input.add32(value)` |
| `externalEuint64 enc` | `input.add64(value)` |
| `externalEuint128 enc` | `input.add128(value)` |
| `externalEuint256 enc` | `input.add256(value)` |
| `externalEbool enc` | `input.addBool(value)` |
| `externalEaddress enc` | `input.addAddress(address)` |
