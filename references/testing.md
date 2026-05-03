# Testing FHEVM Contracts

## Overview

FHEVM contracts are tested using Hardhat with the `@fhevm/hardhat-plugin`. In **local mode** (Hardhat network), FHE operations run in **cleartext mock mode** — no real encryption, instant results. On Sepolia, real FHE is used with actual KMS decryption and network latency.

---

## Setup Requirements

### Install dependencies

```bash
npm install --save-dev @fhevm/hardhat-plugin @fhevm/mock-utils @fhevm/solidity
npm install --save-dev @nomicfoundation/hardhat-ethers @nomicfoundation/hardhat-chai-matchers
npm install --save-dev chai@^4 @types/chai mocha @types/mocha
npm install @zama-fhe/relayer-sdk  # required by hardhat-plugin peer deps
```

> **Use chai v4** — chai v5 has breaking changes that conflict with `@nomicfoundation/hardhat-chai-matchers`.

### hardhat.config.ts — plugin MUST be first

```typescript
import "@fhevm/hardhat-plugin";          // ← FIRST IMPORT — ALWAYS
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
// ... all other imports after
```

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "strict": true,
    "esModuleInterop": true,
    "types": ["hardhat/types", "@fhevm/hardhat-plugin"]
  }
}
```

---

## Importing `fhevm` in Tests

**The plugin exports `fhevm` as a named export from `"hardhat"`** — not via `hre`:

```typescript
// ✅ CORRECT — named import from "hardhat"
import { ethers, fhevm } from "hardhat";

// ❌ WRONG — do not use hre.fhevm
import hre from "hardhat";
// hre.fhevm.createEncryptedInput(...)  // ← do not do this
```

---

## `fhevm` API Reference

### `fhevm.isMock`

Boolean — `true` when running on the local Hardhat mock network, `false` on real networks (Sepolia, mainnet).

Use this to skip tests that only work in one environment:

```typescript
beforeEach(async function () {
  if (!fhevm.isMock) {
    console.warn("This test suite only runs against the local mock network");
    this.skip();
  }
});

// Or the reverse for Sepolia-only tests:
beforeEach(async function () {
  if (fhevm.isMock) {
    console.warn("This test suite only runs on Sepolia Testnet");
    this.skip();
  }
});
```

### `fhevm.createEncryptedInput(contractAddr, userAddr)`

Creates an encrypted input for a specific `(contract, user)` pair. Returns a fluent builder.

```typescript
const encrypted = await fhevm
  .createEncryptedInput(contractAddress, signers.alice.address)
  .add8(100)        // externalEuint8
  .add16(1000)      // externalEuint16
  .add32(50000)     // externalEuint32
  .add64(1_000_000n) // externalEuint64 — use BigInt for uint64+
  .addBool(true)    // externalEbool
  .encrypt();

// encrypted.handles  — array of Uint8Array (one per add* call, same order)
// encrypted.inputProof — Uint8Array, the ZK proof for all handles
```

### Sending encrypted inputs to a contract

```typescript
const encrypted = await fhevm
  .createEncryptedInput(contractAddr, signer.address)
  .add64(1000n)
  .encrypt();

await contract.connect(signer).deposit(encrypted.handles[0], encrypted.inputProof);
//                                                       ↑ index matches add* order
```

### `fhevm.userDecryptEuint(type, handle, contractAddr, signer)`

Decrypts an encrypted value for a specific user. The signer **must** have been granted `FHE.allow(handle, signer.address)` in the contract.

```typescript
import { FhevmType } from "@fhevm/hardhat-plugin";

const handle = await contract.balanceOf(signer.address);
const value = await fhevm.userDecryptEuint(
  FhevmType.euint64,              // type enum — must match the actual encrypted type
  handle,                          // the euintXX handle returned by the contract
  await contract.getAddress(),    // contract address (for ACL verification)
  signer,                          // MUST match who has FHE.allow
);
// Returns: bigint
```

### `FhevmType` enum

```typescript
import { FhevmType } from "@fhevm/hardhat-plugin";

FhevmType.ebool
FhevmType.euint8
FhevmType.euint16
FhevmType.euint32
FhevmType.euint64
FhevmType.euint128
FhevmType.euint256
FhevmType.eaddress
```

---

## Complete Test Example

Matching the official `fhevm-hardhat-template` pattern:

```typescript
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm } from "hardhat";   // ← named import from "hardhat"
import { FhevmType } from "@fhevm/hardhat-plugin";
import { expect } from "chai";
import type { MyToken } from "../types"; // TypeChain generated

describe("MyToken", function () {
  let signers: { deployer: HardhatEthersSigner; alice: HardhatEthersSigner };
  let contract: MyToken;
  let contractAddress: string;

  before(async function () {
    const ethSigners = await ethers.getSigners();
    signers = { deployer: ethSigners[0], alice: ethSigners[1] };
  });

  beforeEach(async function () {
    // Gate to mock-only — remove this block for Sepolia-compatible tests
    if (!fhevm.isMock) {
      console.warn("This test suite can only run on the local mock network");
      this.skip();
    }

    const factory = await ethers.getContractFactory("MyToken");
    contract = (await factory.deploy()) as MyToken;
    contractAddress = await contract.getAddress();
  });

  it("should increment by 1", async function () {
    const clearValue = 1;

    // Encrypt the input — fluent chain, awaited together
    const encrypted = await fhevm
      .createEncryptedInput(contractAddress, signers.alice.address)
      .add32(clearValue)   // use the correct add* for your encrypted type
      .encrypt();

    // Send to contract
    const tx = await contract
      .connect(signers.alice)
      .increment(encrypted.handles[0], encrypted.inputProof);
    await tx.wait();

    // Read and decrypt — alice must have FHE.allow(handle, alice.address)
    const handle = await contract.getCount();
    const decrypted = await fhevm.userDecryptEuint(
      FhevmType.euint32,
      handle,
      contractAddress,
      signers.alice,
    );

    expect(decrypted).to.eq(BigInt(clearValue));
  });
});
```

---

## Sepolia Test Pattern

On Sepolia, FHE computation and decryption are async with real latency. Use `this.timeout()`:

```typescript
import { ethers, fhevm, deployments } from "hardhat";

describe("MyTokenSepolia", function () {
  let contract: MyToken;
  let contractAddress: string;
  let alice: HardhatEthersSigner;

  before(async function () {
    if (fhevm.isMock) {
      console.warn("This test suite can only run on Sepolia Testnet");
      this.skip();
    }

    // Load deployed contract (requires prior `npx hardhat deploy --network sepolia`)
    const deployment = await deployments.get("MyToken");
    contractAddress = deployment.address;
    contract = await ethers.getContractAt("MyToken", contractAddress);
    [alice] = await ethers.getSigners();
  });

  it("should increment the counter on Sepolia", async function () {
    this.timeout(4 * 40_000); // 160s — KMS decryption can take 30-60s

    const encrypted = await fhevm
      .createEncryptedInput(contractAddress, alice.address)
      .add32(1)
      .encrypt();

    const tx = await contract.connect(alice).increment(encrypted.handles[0], encrypted.inputProof);
    await tx.wait();

    const handle = await contract.getCount();
    const value = await fhevm.userDecryptEuint(FhevmType.euint32, handle, contractAddress, alice);
    expect(value).to.be.gte(1n);
  });
});
```

---

## Testing Public Decryption

In Hardhat mock mode, the Gateway callback fires synchronously (same block or next):

```typescript
it("should reveal auction winner", async function () {
  // Submit bid
  const encrypted = await fhevm
    .createEncryptedInput(auctionAddr, bidder.address)
    .add64(500n)
    .encrypt();
  await auction.connect(bidder).bid(encrypted.handles[0], encrypted.inputProof);

  // Advance time past auction end
  await hre.network.provider.send("evm_increaseTime", [86401]);
  await hre.network.provider.send("evm_mine", []);

  // Request reveal (fires Gateway callback)
  await (await auction.revealResult()).wait();

  // In mock: callback fires synchronously, may need one tick
  await new Promise(r => setTimeout(r, 100));

  const revealed = await auction.revealedWinningBid();
  expect(revealed).to.equal(500n);
});
```

On Sepolia, poll until the callback fires (30–60 seconds typical):

```typescript
export async function waitForDecryption(
  check: () => Promise<boolean>,
  timeoutMs = 120_000,
  intervalMs = 5_000
): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await check()) return;
    await new Promise(r => setTimeout(r, intervalMs));
  }
  throw new Error("Timeout waiting for public decryption callback");
}
```

---

## `FHE.isInitialized(handle)` — Better Than Unwrap

Instead of checking `euint64.unwrap(handle) == 0`, prefer:

```solidity
if (!FHE.isInitialized(_balances[user])) {
    _balances[user] = FHE.asEuint64(0);
    FHE.allowThis(_balances[user]);
    FHE.allow(_balances[user], user);
}
```

`FHE.isInitialized` is defined for all encrypted types including `ebool`, `euint8`–`euint256`, `eaddress`.

---

## Common Testing Errors

| Error | Root Cause | Fix |
|---|---|---|
| `fhevm is not exported from "hardhat"` | Plugin not first import | Move `import "@fhevm/hardhat-plugin"` to first line of `hardhat.config.ts` |
| `fhevm.createEncryptedInput is not a function` | Using `hre.fhevm` instead of named `fhevm` | Change to `import { ethers, fhevm } from "hardhat"` |
| `TypeError: Cannot read 'euint64'` | Missing types in tsconfig | Add `"@fhevm/hardhat-plugin"` to `tsconfig.json` compilerOptions.types |
| `chai@5` assertion conflicts | Wrong chai version | Install `chai@^4` |
| `userDecryptEuint returns 0n` | Wrong signer — signer doesn't have `FHE.allow` | Use the signer who received the `FHE.allow(handle, addr)` grant |
| `evmVersion not cancun` | Missing EVM version | Add `evmVersion: "cancun"` to Hardhat solidity settings |
| Tests pass locally, fail on Sepolia | Missing timeout, no polling | Add `this.timeout(160_000)` and wait for KMS decryption |
| `handles[0] is undefined` | `.encrypt()` called before `.addXX()` | Ensure `.addXX()` is called before `.encrypt()` in the chain |
| `@fhevm/mock-utils not found` | Missing package | `npm install --save-dev @fhevm/mock-utils` |

---

## Running Tests

```bash
# Local (fast, cleartext mock FHE)
npx hardhat test

# Specific file
npx hardhat test test/MyToken.ts

# Sepolia (real FHE — slow, requires deployed contract)
npx hardhat test --network sepolia

# With gas reporting
REPORT_GAS=true npx hardhat test

# With coverage
npx hardhat coverage
```
