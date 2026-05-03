# fhEVM Complete Error Reference

> Version: v2.2.6 | Source: Zama fhEVM contracts, community forum, real deployment experience

## Quick Diagnostic Checklist

Run through this before digging deeper:

1. Did you call `FHE.allowThis(handle)` after **every** ciphertext assignment?
2. Did you call `FHE.allow(handle, userAddress)` for every address that reads it?
3. Is every encrypted mapping initialized before first use (not `bytes32(0)`)?
4. Did you convert `externalEuintXX` via `FHE.fromExternal(enc, proof)` before use?
5. Is `evmVersion: "cancun"` set in `hardhat.config.ts`?
6. Does your contract inherit the right config for the deployment network?
7. Is your `inputProof` generated for the exact `(contractAddress, msg.sender)` pair?
8. Are you using `chai@^4` (not v5)?
9. Are the CORS headers set in Vite for WASM?
10. Is `@fhevm/hardhat-plugin` the **first** import in `hardhat.config.ts`?
11. Is your encrypted input value within the range of the type? (e.g. euint8 max = 255)

---

## 1. ACL / Access Control Errors

### `ACL: Not allowed` / `ACL_NotAllowed`

**Source:** `ACL.sol` — `checkAllowedCaller()` / `isAllowed()`
**When:** Any tx where a contract tries to use a ciphertext handle it no longer has permission to access.
**Root cause:** `FHE.allowThis()` was not called after the last ciphertext assignment. Each assignment produces a **new handle** — the old ACL entry is invalid.

```solidity
// ❌ WRONG — _balances[user] reassigned, new handle has no ACL entry
_balances[user] = FHE.add(_balances[user], amount);
// Next tx: ACL: Not allowed

// ✅ CORRECT — re-grant after every assignment
_balances[user] = FHE.add(_balances[user], amount);
FHE.allowThis(_balances[user]);       // this contract reads it next tx
FHE.allow(_balances[user], user);     // user reads/re-encrypts it
```

---

### `ACL: handle is not allowed for decryption`

**Source:** `ACL.sol` — `allowForDecryption()` check
**When:** `FHE.requestDecryption()` called on a handle the KMS isn't permitted to decrypt.

```solidity
// ✅ Correct pattern for on-chain decryption request
function requestReveal() external {
    FHE.allowThis(_encryptedResult);
    bytes32[] memory handles = new bytes32[](1);
    handles[0] = euint64.unwrap(_encryptedResult);
    FHE.requestDecryption(handles, this.onReveal.selector);
}
```

---

### `ACL: handle does not exist` / `ACL: Non-existing handle`

**Source:** `ACL.sol`
**When:** `bytes32(0)` or any unregistered bytes32 passed to an FHE operation.
**Root cause:** Reading from an uninitialized encrypted mapping slot.

```solidity
// ❌ newUser has never deposited — _balances[newUser] is bytes32(0)
_balances[newUser] = FHE.add(_balances[newUser], amount); // crash

// ✅ Initialize before first FHE operation
function _ensureInit(address user) internal {
    if (euint64.unwrap(_balances[user]) == 0) {
        _balances[user] = FHE.asEuint64(0);
        FHE.allowThis(_balances[user]);
        FHE.allow(_balances[user], user);
    }
}
```

---

### `Sender not allowed` / Transient permission failure

**Source:** `ACL.sol` — `allowedTransient()` check
**When:** Cross-contract ciphertext use without transient ACL grant.

```solidity
// ❌ WRONG — otherContract has no ACL for myHandle
function executeViaRouter(euint64 myHandle) external {
    router.process(myHandle);  // fails

// ✅ CORRECT
function executeViaRouter(euint64 myHandle) external {
    FHE.allowTransient(myHandle, address(router));
    router.process(myHandle);
}
```

---

### Re-encryption returns 0 / `FHE.allow()` missing for user

**When:** `instance.reencrypt()` returns 0 even though contract stores correct value.
**Root cause:** `FHE.allow(handle, userAddress)` was never called — only `FHE.allowThis()`.

```solidity
// Must call BOTH after every assignment:
FHE.allowThis(_balances[user]);   // contract can read next tx
FHE.allow(_balances[user], user); // user can re-encrypt
```

---

## 2. Handle Errors

### `Zero handle not allowed`

**When:** `bytes32(0)` passed to any FHE operation.
**Root cause:** Uninitialized mapping slot or unassigned state variable.

```solidity
// ✅ Initialize in constructor
constructor() {
    _secret = FHE.asEuint64(0);
    FHE.allowThis(_secret);
}
```

---

### `Invalid handle type` / `UnsupportedHandleType`

**When:** Handle's type bits don't match expected FHE operation type.

```solidity
// Explicit casts required:
euint32 small = FHE.fromExternal(enc32, proof);
euint64 big   = FHE.asEuint64(small);   // ✅ explicit upcast

// Type casting rules:
// euint8 → euint64:  safe upcast  ✅
// euint64 → euint8:  downcast, truncates  ⚠️
// euint64 → eaddress: forbidden  ❌
// euint64 → ebool:   use FHE.gt(x, FHE.asEuint64(0))  ✅
```

---

### `Handle not verified` / Unverified external handle used

**When:** `externalEuintXX` used in FHE computation before `FHE.fromExternal()`.

```solidity
// ❌ WRONG
function deposit(externalEuint64 enc, bytes calldata proof) external {
    _balance = FHE.add(_balance, enc);  // wrong type + unverified

// ✅ CORRECT
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    _balance = FHE.add(_balance, amount);
    FHE.allowThis(_balance);
    FHE.allow(_balance, msg.sender);
}
```

---

### `HandlesAlreadySavedForRequestID`

**When:** `FHE.requestDecryption()` called twice with same `requestId`.

```solidity
// ✅ Guard against duplicate requests
mapping(uint256 => bool) private _pendingDecryption;
function requestReveal() external {
    require(!_pendingDecryption[currentRequestId], "Already pending");
    uint256 reqId = FHE.requestDecryption(handles, this.onReveal.selector);
    _pendingDecryption[reqId] = true;
}
```

---

### `NoHandleFoundForRequestID`

**When:** Decryption callback called with wrong or stale `requestId`.

```solidity
// ✅ Always verify caller and signatures in callback
function onReveal(uint256 requestId, bytes memory cleartexts, bytes memory sigs)
    public returns (bool)
{
    require(msg.sender == address(FHE.getDecryptionOracle()), "Only oracle");
    FHE.checkSignatures(requestId, cleartexts, sigs);
    return true;
}
```

---

## 3. Input Proof / ZK Verification Errors

### `Proof verification failed` / `InvalidKMSSignatures` / `Invalid ZK proof`

**Root causes (in order of frequency):**
1. Proof generated for wrong `contractAddress`
2. Proof generated for wrong `msg.sender`
3. Stale proof reused from previous transaction
4. Wrong network (Sepolia proof used on mainnet)
5. Input value out of range for encrypted type

```typescript
// ✅ Always generate fresh proof for exact contract + sender pair
const contractAddress = await myContract.getAddress(); // NOT hardcoded
const userAddress = await signer.getAddress();
const input = instance.createEncryptedInput(contractAddress, userAddress);
input.add64(1000n);
const { handles, inputProof } = await input.encrypt();
// NEVER reuse this proof
await myContract.deposit(handles[0], inputProof);
```

---

### `Proof bound to wrong contract`

```typescript
// ❌ Wrong: hardcoded stale address
const input = instance.createEncryptedInput("0xOldAddress", userAddress);

// ✅ Correct: always fetch current address
const input = instance.createEncryptedInput(
    await contract.getAddress(),
    await signer.getAddress()
);
```

---

### `InputLengthAbove64Bytes` / `InputLengthAbove128Bytes` / `InputLengthAbove256Bytes`

**When:** Encrypted ciphertext is longer than target type can accept.
**Root cause:** Mismatched encryption type.

```typescript
// ❌ WRONG — add256 creates 256-bit ciphertext, contract expects euint64
input.add256(bigValue);

// ✅ CORRECT — match type to Solidity parameter
input.add64(value);    // for externalEuint64
input.add32(value);    // for externalEuint32
input.add8(value);     // for externalEuint8
input.addBool(value);  // for externalEbool
```

| Solidity type | Frontend call | Max value |
|---|---|---|
| `euint8` | `input.add8(n)` | 255 |
| `euint16` | `input.add16(n)` | 65,535 |
| `euint32` | `input.add32(n)` | 4,294,967,295 |
| `euint64` | `input.add64(n)` | 18,446,744,073,709,551,615 |
| `euint128` | `input.add128(n)` | 2^128 - 1 |
| `euint256` | `input.add256(n)` | 2^256 - 1 |
| `ebool` | `input.addBool(b)` | true / false |
| `eaddress` | `input.addAddress(addr)` | any address |

---

## 4. Decryption / KMS / Callback Errors

### Callback never triggered after `FHE.requestDecryption()`

**Root causes:**
1. Wrong callback selector (parameter types don't match)
2. Handle not ACL-approved for the Gateway
3. Callback gas limit exceeded

```solidity
// ✅ Exact callback signature required
function onReveal(
    uint256 requestId,        // uint256, always first
    bytes memory cleartexts,  // ABI-encoded decrypted values
    bytes memory proof        // KMS signatures
) public returns (bool) {     // must return bool
    FHE.checkSignatures(requestId, cleartexts, proof);
    uint64 result = abi.decode(cleartexts, (uint64));
    // for 2 handles: (uint64 a, uint64 b) = abi.decode(cleartexts, (uint64, uint64));
    // for bool:      bool b = abi.decode(cleartexts, (bool));
    return true;
}
```

---

### `InvalidKMSSignatures`

**When:** KMS signature bundle in decryption callback is invalid.

```solidity
// ✅ Always call FHE.checkSignatures() first in every callback
function onReveal(uint256 reqId, bytes memory cleartexts, bytes memory sigs)
    public returns (bool)
{
    FHE.checkSignatures(reqId, cleartexts, sigs);  // reverts if invalid
    uint64 value = abi.decode(cleartexts, (uint64));
    emit Revealed(value);
    return true;
}
```

---

### `Re-encryption signature invalid` / KMS returns 0

**Root causes:**
1. `FHE.allow(handle, userAddress)` was never called
2. Wrong contract address in re-encryption request
3. Expired or invalid EIP-712 signature
4. Keypair reused across sessions

```typescript
// ✅ Complete re-encryption pattern
const { publicKey, privateKey } = instance.generateKeypair(); // always fresh
const eip712 = instance.createEIP712(publicKey, contractAddress); // bound to contract
const signature = await signer.signTypedData(
    eip712.domain,
    { Reencrypt: eip712.types.Reencrypt },
    eip712.message
);
const handle = await contract.balanceOf(userAddress);
return await instance.reencrypt(
    handle, privateKey, publicKey, signature,
    contractAddress, userAddress  // must match
);
```

---

## 5. Hardhat / Compilation Errors

### Missing `evmVersion: "cancun"`

```typescript
// hardhat.config.ts
solidity: {
    version: "0.8.28",
    settings: {
        evmVersion: "cancun",    // ← REQUIRED
        optimizer: { enabled: true, runs: 800 },
    },
},
```

---

### `hre.fhevm is undefined`

**Root cause:** `@fhevm/hardhat-plugin` is not the first import.

```typescript
// hardhat.config.ts — order matters!
import "@fhevm/hardhat-plugin";               // ← MUST be first
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
```

---

### Wrong network config contract

```solidity
// ✅ Sepolia:
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
contract MyToken is SepoliaFHEVMConfig { }

// ✅ Mainnet:
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
contract MyToken is ZamaEthereumConfig { }

// ✅ Local Hardhat:
contract MyToken { }  // no config needed
```

---

### `Cannot find module '@fhevm/solidity'`

```bash
npm install @fhevm/solidity @fhevm/hardhat-plugin
```

---

### `TypeScript error: Property 'fhevm' does not exist on type 'HardhatRuntimeEnvironment'`

```json
// tsconfig.json
{
    "compilerOptions": {
        "types": ["hardhat/types", "@fhevm/hardhat-plugin"]
    }
}
```

---

### Missing CORS headers in vite.config.ts

```typescript
export default defineConfig({
    server: {
        headers: {
            "Cross-Origin-Opener-Policy": "same-origin",
            "Cross-Origin-Embedder-Policy": "require-corp",
        },
    },
    optimizeDeps: {
        exclude: ["@zama-fhe/relayer-sdk"],
    },
});
```

---

## 6. Solidity Type Errors

### `externalEuint64 is not implicitly convertible to expected type euint64`

```solidity
// ❌ WRONG
function deposit(externalEuint64 enc, bytes calldata proof) external {
    _balance = FHE.add(_balance, enc);  // type mismatch

// ✅ CORRECT
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    _balance = FHE.add(_balance, amount);
}
```

---

### `ebool cannot be used in if statements`

```solidity
// ❌ WRONG
ebool condition = FHE.gt(a, b);
if (condition) { ... }  // can't use ebool in if

// ✅ CORRECT — use FHE.select
euint64 result = FHE.select(condition, valueIfTrue, valueIfFalse);
```

---

## 7. Testing Errors

### `chai@5` compatibility issues

```bash
# ✅ Use chai v4
npm install chai@^4
```

---

### Decryption returns wrong value in tests

```typescript
import { fhevm } from "hardhat";  // named import

// ❌ Wrong signer — must match who has FHE.allow
const balance = await fhevm.userDecryptEuint(
    FhevmType.euint64, handle, addr, owner  // owner doesn't have allow for alice's balance
);

// ✅ Use the correct signer (the one who has FHE.allow)
const aliceBalance = await fhevm.userDecryptEuint(
    FhevmType.euint64, handle, addr, alice  // alice has allow for her own balance
);
```

---

## 8. Deployment / Network Errors

### `not enough ETH` / insufficient funds

| Faucet | URL | Limit |
|---|---|---|
| Alchemy | https://sepoliafaucet.com | 0.5 ETH/day |
| Infura | https://www.infura.io/faucet/sepolia | 0.5 ETH/day |
| QuickNode | https://faucet.quicknode.com/ethereum/sepolia | 1 ETH/day |
| pk910 | https://sepolia-faucet.pk910.de | Variable |

---

### `Nonce too high` / nonce mismatch

```bash
npx hardhat clean
# For Sepolia: wait for pending txs to confirm
```

---

### `Cannot estimate gas` / transaction always fails in estimation

```typescript
// Try static call to see actual revert reason
try {
    await contract.myFunction.staticCall(...params);
} catch (e) {
    console.log("Revert reason:", e.message);
}
```

---

## 9. OpenZeppelin Confidential Contracts Errors

### Missing `_update()` override

```solidity
// ✅ Override _update to grant ACL on balance updates
function _update(address from, address to, euint64 value) internal override {
    super._update(from, to, value);
    if (from != address(0)) FHE.allow(_balances[from], from);
    if (to != address(0)) FHE.allow(_balances[to], to);
}
```

---

### Confidential ERC-20 approval confusion

```solidity
// ✅ Approve takes encrypted amount
function approve(address spender, externalEuint64 encAmount, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(encAmount, proof);
    _approve(msg.sender, spender, amount);
    FHE.allow(_allowances[msg.sender][spender], spender);
    FHE.allowThis(_allowances[msg.sender][spender]);
}
```

---

## Error → Fix Quick Reference

| Error Message | Fix |
|---|---|
| `ACL: Not allowed` | Add `FHE.allowThis(handle)` after every assignment |
| `ACL: handle does not exist` | Initialize mapping with `FHE.asEuint64(0)` |
| `Sender not allowed` | Add `FHE.allowTransient(handle, contractAddr)` |
| `re-encryption returns 0` | Add `FHE.allow(handle, userAddr)` |
| `Proof verification failed` | Use `contract.getAddress()` not hardcoded; generate fresh proof |
| `InputLengthAbove64Bytes` | Match `input.addXX()` to Solidity param type |
| `fhevm not exported from "hardhat"` | Move `@fhevm/hardhat-plugin` to be first import in `hardhat.config.ts` |
| `evmVersion not cancun` | Add `evmVersion: "cancun"` to hardhat config |
| `Cannot find @fhevm/solidity` | `npm install @fhevm/solidity @fhevm/hardhat-plugin` |
| Callback never fires | Verify callback signature exactly: `(uint256, bytes, bytes) returns (bool)` |
| `SharedArrayBuffer not defined` | Add COOP/COEP headers to Vite config |
| `chai@5` errors | `npm install chai@^4` |
| `InvalidKMSSignatures` | Call `FHE.checkSignatures(reqId, ct, sigs)` in callback |
