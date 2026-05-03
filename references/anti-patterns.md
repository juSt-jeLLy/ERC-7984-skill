# FHEVM Anti-Patterns and Common Mistakes

This document catalogs the most frequent mistakes developers make with FHEVM and how to fix them.

---

## 1. Missing `FHE.allowThis` After Assignment

**The most common FHEVM bug.** Every FHE operation produces a NEW handle. The previous ACL entry is now for a stale handle.

```solidity
// ❌ WRONG — new handle, no ACL
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
    // Missing FHE.allowThis!
    // Next tx: ACL: Not allowed
}

// ✅ CORRECT
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
    FHE.allowThis(_balances[msg.sender]);           // ← required
    FHE.allow(_balances[msg.sender], msg.sender);  // ← required for user read
}
```

**Rule:** `FHE.allowThis()` must be called after EVERY `euintXX =` assignment.

---

## 2. Using `externalEuintXX` Directly in FHE Operations

`externalEuintXX` is an untrusted, unverified input. It is NOT a valid FHE handle until verified.

```solidity
// ❌ WRONG — type error + security vulnerability
function deposit(externalEuint64 enc, bytes calldata proof) external {
    _balance = FHE.add(_balance, enc);  // enc is not euint64
}

// ✅ CORRECT
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);  // verify + convert
    _balance = FHE.add(_balance, amount);
    FHE.allowThis(_balance);
}
```

---

## 3. Uninitialized Encrypted Mappings

Mapping slots default to `bytes32(0)`, which is not a valid FHE handle. Calling FHE operations on it crashes.

```solidity
// ❌ WRONG — newUser's _balances[newUser] is bytes32(0)
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);  // crash!
}

// ✅ CORRECT — initialize before first use using FHE.isInitialized (not unwrap)
function _ensureInit(address user) internal {
    if (!FHE.isInitialized(_balances[user])) {  // ✅ works for euintXX, ebool, eaddress
        _balances[user] = FHE.asEuint64(0);
        FHE.allowThis(_balances[user]);
        FHE.allow(_balances[user], user);
    }
    // ❌ NEVER: euint64.unwrap(_balances[user]) == 0  ← breaks on ebool, fragile for euint
}

function deposit(externalEuint64 enc, bytes calldata proof) external {
    _ensureInit(msg.sender);  // ← always call first
    euint64 amount = FHE.fromExternal(enc, proof);
    _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
    FHE.allowThis(_balances[msg.sender]);
    FHE.allow(_balances[msg.sender], msg.sender);
}
```

---

## 4. Branching on `ebool` with `if/else`

Branching on an encrypted boolean leaks information — it reveals WHICH branch was taken.

```solidity
// ❌ WRONG — leaks whether condition is true or false
ebool hasEnough = FHE.gte(_balances[msg.sender], amount);
if (hasEnough) {  // can't use ebool in if — also type error
    _balances[msg.sender] = FHE.sub(_balances[msg.sender], amount);
    _balances[to] = FHE.add(_balances[to], amount);
}

// ✅ CORRECT — use FHE.select (ternary on ciphertexts)
ebool hasEnough = FHE.gte(_balances[msg.sender], amount);
euint64 actualAmount = FHE.select(hasEnough, amount, FHE.asEuint64(0));
_balances[msg.sender] = FHE.sub(_balances[msg.sender], actualAmount);
_balances[to] = FHE.add(_balances[to], actualAmount);
FHE.allowThis(_balances[msg.sender]);
FHE.allow(_balances[msg.sender], msg.sender);
FHE.allowThis(_balances[to]);
FHE.allow(_balances[to], to);
```

---

## 5. Reusing Input Proofs

Input proofs are single-use, bound to a specific `(contractAddress, senderAddress, tx)` pair.

```typescript
// ❌ WRONG — reusing proof across transactions
const { handles, inputProof } = await input.encrypt();
await contract.deposit(handles[0], inputProof);
// Later...
await contract.deposit(handles[0], inputProof);  // fails — proof is stale

// ✅ CORRECT — generate fresh proof for each transaction
async function deposit(amount: bigint) {
    const input = instance.createEncryptedInput(contractAddr, userAddr);
    input.add64(amount);
    const { handles, inputProof } = await input.encrypt();  // fresh each time
    await contract.deposit(handles[0], inputProof);
}
```

---

## 6. Hardcoding Contract Address in Proof Generation

```typescript
// ❌ WRONG — hardcoded address becomes stale after redeployment
const input = instance.createEncryptedInput("0x1234...OldAddress", userAddr);

// ✅ CORRECT — always fetch the live address
const contractAddress = await contract.getAddress();
const input = instance.createEncryptedInput(contractAddress, userAddr);
```

---

## 7. Wrong Network Config Inheritance

Using the wrong config class routes FHE operations to the wrong network silently.

```solidity
// ❌ WRONG for Sepolia — no config means using mainnet coprocessor addresses
contract MyToken {
    // ...
}

// ❌ WRONG — importing wrong config for the target network
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
contract MyToken is ZamaEthereumConfig {  // mainnet config on Sepolia!
}

// ✅ CORRECT — match config to network
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
contract MyToken is SepoliaFHEVMConfig {  // for Sepolia
}

// ✅ For local Hardhat: no config needed
contract MyToken {
    // plugin auto-configures addresses
}
```

---

## 8. Missing `evmVersion: "cancun"` in Hardhat Config

```typescript
// ❌ WRONG — default evmVersion will fail at runtime
solidity: {
    version: "0.8.27",
    settings: {
        optimizer: { enabled: true, runs: 200 },
        // Missing evmVersion!
    },
}

// ✅ CORRECT
solidity: {
    version: "0.8.27",
    settings: {
        optimizer: { enabled: true, runs: 800 },
        evmVersion: "cancun",  // ← REQUIRED
    },
}
```

---

## 9. `@fhevm/hardhat-plugin` Not First Import

```typescript
// ❌ WRONG — hre.fhevm will be undefined
import "@nomicfoundation/hardhat-ethers";  // loaded before plugin
import "@fhevm/hardhat-plugin";

// ✅ CORRECT — plugin MUST be first
import "@fhevm/hardhat-plugin";            // ← MUST be first
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
```

---

## 10. View Functions That Try to Return Decrypted Values

You cannot return a plaintext from a view function by decrypting on-chain. Decryption via Gateway is async (callback-based).

```solidity
// ❌ IMPOSSIBLE — can't decrypt synchronously in a view function
function getMyBalance() external view returns (uint64) {
    euint64 handle = _balances[msg.sender];
    return FHE.decrypt(handle);  // FHE.decrypt() does not exist in this form
}

// ✅ CORRECT pattern 1 — return handle, user re-encrypts off-chain
function balanceOf(address user) external view returns (euint64) {
    return _balances[user];  // caller uses instance.reencrypt() off-chain
}

// ✅ CORRECT pattern 2 — public decryption via Gateway (async, 2 txs)
function requestReveal() external {
    bytes32[] memory handles = new bytes32[](1);
    handles[0] = euint64.unwrap(_secret);
    FHE.requestDecryption(handles, this.onReveal.selector);
}
uint64 public revealedValue;
function onReveal(uint256 reqId, bytes memory ct, bytes memory sigs) public returns (bool) {
    FHE.checkSignatures(reqId, ct, sigs);
    revealedValue = abi.decode(ct, (uint64));
    return true;
}
```

---

## 11. Missing `FHE.allow` for the Recipient in Transfers

```solidity
// ❌ WRONG — recipient can't read their balance
function transfer(address to, euint64 amount) internal {
    _balances[to] = FHE.add(_balances[to], amount);
    FHE.allowThis(_balances[to]);
    // Missing: FHE.allow(_balances[to], to) ← recipient can't re-encrypt!
}

// ✅ CORRECT
function transfer(address to, euint64 amount) internal {
    _balances[to] = FHE.add(_balances[to], amount);
    FHE.allowThis(_balances[to]);
    FHE.allow(_balances[to], to);  // ← recipient can now read their balance
}
```

---

## 12. Using `chai@5` in Tests

```bash
# ❌ chai@5 breaks hardhat-chai-matchers
npm install chai@latest  # installs v5 — WRONG

# ✅ use chai@4
npm install chai@^4
```

---

## 13. Encrypting Out-of-Range Values

```typescript
// ❌ WRONG — value too large for euint8
input.add8(300);  // max is 255 → proof verification fails

// ✅ CORRECT — value within range
input.add8(100);   // fits in euint8
input.add64(1_000_000n);  // fits in euint64
```

---

## 14. Cross-Contract Calls Without `allowTransient`

```solidity
// ❌ WRONG — other contract has no ACL for myHandle
function processViaRouter(euint64 myHandle) external {
    router.process(myHandle);  // Sender not allowed error

// ✅ CORRECT
function processViaRouter(euint64 myHandle) external {
    FHE.allowTransient(myHandle, address(router));
    router.process(myHandle);
}
```

---

## 15. Missing CORS Headers for Frontend WASM

---

## 16. Wrong Config Class Name When Using fhevm-contracts

`fhevm-contracts` uses a **different config class name and import path** than standalone `@fhevm/solidity`. Mixing them causes compile errors or silent routing to the wrong network.

```solidity
// ❌ WRONG — using @fhevm/solidity class name with fhevm-contracts
import { ConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20.sol";
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";  // wrong package!
contract MyToken is SepoliaFHEVMConfig, ConfidentialERC20 { ... }

// ✅ CORRECT — fhevm-contracts style
import { ConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";  // fhevm package
contract MyToken is SepoliaZamaFHEVMConfig, ConfidentialERC20 { ... }

// ✅ CORRECT — standalone @fhevm/solidity style (no fhevm-contracts)
import { FHE, euint64, externalEuint64 } from "@fhevm/solidity";
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
contract MyToken is SepoliaFHEVMConfig { ... }
```

**Quick reference:**

| Using | Config class | Import path |
|---|---|---|
| `fhevm-contracts` | `SepoliaZamaFHEVMConfig` | `"fhevm/config/ZamaFHEVMConfig.sol"` |
| `@fhevm/solidity` standalone | `SepoliaFHEVMConfig` | `"@fhevm/solidity/config/FHEVMConfig.sol"` |

---

## 17. Using `TFHE` Namespace in Standalone Contracts (or `FHE` in fhevm-contracts Extensions)

```solidity
// ❌ WRONG — using deprecated TFHE in a new standalone contract
import "fhevm/lib/TFHE.sol";  // old package
contract MyVault {
    TFHE.allowThis(_balance);  // using old API
}

// ✅ CORRECT — standalone contracts use @fhevm/solidity with FHE namespace
import { FHE, euint64, externalEuint64 } from "@fhevm/solidity";
contract MyVault {
    FHE.allowThis(_balance);   // new API
}

// ❌ WRONG — using FHE namespace inside a fhevm-contracts extension
import { ConfidentialERC20 } from "fhevm-contracts/...";
import { FHE } from "@fhevm/solidity";  // wrong package for this extension
contract MyToken is ConfidentialERC20 {
    function _transferNoEvent(...) internal override {
        super._transferNoEvent(...);
        FHE.allowThis(newFeeHandle);  // FHE not available in this context
    }
}

// ✅ CORRECT — use TFHE in fhevm-contracts extensions (same package as base)
import "fhevm/lib/TFHE.sol";
contract MyToken is ConfidentialERC20 {
    function _transferNoEvent(...) internal override {
        super._transferNoEvent(...);
        TFHE.allowThis(newFeeHandle);  // matches fhevm-contracts dependency
    }
}
```

---

## 18. Assuming `decimals()` is 18 in ConfidentialERC20

```solidity
// ❌ WRONG — ConfidentialERC20 default is 6, not 18
// 1 token in 18-decimal units:
_unsafeMint(user, 1_000_000_000_000_000_000); // This is 1e18 — overflows uint64!
// uint64 max ≈ 1.84e19 — but this amount in 18-dec context would be 1e18

// ✅ CORRECT — default decimals = 6
// 1 token in 6-decimal units:
_unsafeMint(user, 1_000_000);  // 1 MTK

// ✅ To use 18 decimals, override decimals():
function decimals() public view virtual override returns (uint8) {
    return 18;
}
// Then mint: _unsafeMint(user, 1_000_000_000_000_000_000) — within uint64 max for small amounts
```

---

## 19. Not Updating `_totalSupply` After `_unsafeMint` / `_unsafeBurn`

```solidity
// ❌ WRONG — _totalSupply stays 0 forever
function initialize() internal {
    _unsafeMint(owner, 1_000_000);
    // Missing: _totalSupply = 1_000_000;
}

// ✅ CORRECT
function initialize() internal {
    _unsafeMint(owner, 1_000_000);
    _totalSupply = 1_000_000;         // ← required: totalSupply is NOT auto-updated
}

// When minting more (ConfidentialERC20Mintable pattern):
function mint(address to, uint64 amount) external onlyOwner {
    _unsafeMint(to, amount);
    _totalSupply = _totalSupply + amount;  // ← also enforces overflow invariant
    emit Mint(to, amount);
}
```

---

## 20. Calling `unwrap` While Account Already Has a Pending Unwrap

```solidity
// ❌ WRONG — second unwrap while first is pending Gateway callback
wrappedToken.unwrap(1_000_000);
wrappedToken.unwrap(500_000);  // reverts: CannotTransferOrUnwrap
// isAccountRestricted[msg.sender] = true after first unwrap

// ✅ CORRECT — wait for callbackUnwrap to fire before calling again
// isAccountRestricted resets to false in callbackUnwrap (success or failure)
// On Sepolia: poll isAccountRestricted[address] until false, then unwrap again
```

```typescript
// ❌ WRONG — SharedArrayBuffer not available without CORS headers
export default defineConfig({ plugins: [react()] });

// ✅ CORRECT
export default defineConfig({
    plugins: [react()],
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
