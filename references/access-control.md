# FHEVM Access Control (ACL)

The **ACL (Access Control List)** contract governs who can use, compute on, or decrypt each ciphertext handle. Without correct ACL setup, contracts fail silently or revert on the next transaction.

## The Core Problem

Each FHE operation produces a **new handle**. The old ACL entry for the previous handle is now invalid. If you do not re-grant permission for the new handle, the next transaction that tries to use it will get `ACL: Not allowed`.

```solidity
// ❌ WRONG — after add(), _balance has a NEW handle with no ACL
_balance = FHE.add(_balance, amount);
// next tx: ACL: Not allowed ← the new handle has no permissions

// ✅ CORRECT — re-grant after every assignment
_balance = FHE.add(_balance, amount);
FHE.allowThis(_balance);    // contract can use it next tx
FHE.allow(_balance, user);  // user can re-encrypt it
```

## ACL Functions

### `FHE.allowThis(handle)`

Grants the **current contract** (`address(this)`) permission to use the handle in future transactions.

```solidity
_balance = FHE.add(_balance, amount);
FHE.allowThis(_balance);  // REQUIRED after every assignment
```

**When to call:** After every line that assigns to an encrypted state variable.

---

### `FHE.allow(handle, address)`

Grants a specific **external address** (user wallet or other contract) permission to re-encrypt the handle (read its value off-chain).

```solidity
_balances[user] = FHE.add(_balances[user], amount);
FHE.allowThis(_balances[user]);          // contract can use it
FHE.allow(_balances[user], user);        // user can re-encrypt/view it
FHE.allow(_balances[user], address(this)); // also allow this contract explicitly
```

**When to call:** Whenever a user needs to read/decrypt a value. Always call alongside `FHE.allowThis`.

---

### `FHE.allowTransient(handle, address)`

Grants **transient** permission that expires at the end of the current transaction. Used for **cross-contract ciphertext passing** within a single tx.

```solidity
// Caller grants transient access to router contract before passing handle
function executeViaRouter(euint64 amount) external {
    FHE.allowTransient(amount, address(router));
    router.process(amount);  // router can now use it within this tx only
}
```

**When to use:** Any time you pass an encrypted handle to another contract within the same transaction.

**Important:** Transient permissions expire at tx end. Use `FHE.allow()` for persistent cross-contract access.

---

### `FHE.allowForDecryption(handle)`

Marks a handle as approved for on-chain public decryption via the Gateway. Called before `FHE.requestDecryption()`.

```solidity
FHE.allowThis(_encryptedResult);           // contract keeps access
FHE.allowForDecryption(_encryptedResult);  // not needed — requestDecryption handles this
// Usually requestDecryption does this internally, but explicit is safer
```

## Complete ACL Pattern for Every Operation

```solidity
// Standard pattern — apply this template after every FHE assignment
function _updateBalance(address user, euint64 newBalance) internal {
    _balances[user] = newBalance;
    FHE.allowThis(_balances[user]);           // this contract can use it
    FHE.allow(_balances[user], user);         // user can view/re-encrypt
    // Optional: allow other trusted contracts
    // FHE.allow(_balances[user], address(vault));
}
```

## ACL for Encrypted Allowances

When implementing ERC-20-style allowances with encrypted amounts:

```solidity
function _approve(address owner, address spender, euint64 amount) internal {
    _allowances[owner][spender] = amount;
    FHE.allowThis(_allowances[owner][spender]);
    FHE.allow(_allowances[owner][spender], owner);    // owner can check their own allowance
    FHE.allow(_allowances[owner][spender], spender);  // spender can use the allowance
}
```

## ACL for Public Decryption

```solidity
function requestPublicReveal() external {
    euint64 val = _encryptedResult;
    
    // Build handles array for decryption request
    bytes32[] memory handles = new bytes32[](1);
    handles[0] = euint64.unwrap(val);
    
    // ACL: contract must still have allowThis — call it again to be safe
    FHE.allowThis(val);
    
    // Request decryption via Gateway — callback will be called
    uint256 reqId = FHE.requestDecryption(handles, this.onReveal.selector);
    _pendingRequests[reqId] = true;
}

function onReveal(
    uint256 requestId,
    bytes memory cleartexts,
    bytes memory signatures
) public returns (bool) {
    require(msg.sender == address(FHE.getDecryptionOracle()), "Only oracle");
    FHE.checkSignatures(requestId, cleartexts, signatures);
    uint64 result = abi.decode(cleartexts, (uint64));
    emit ResultRevealed(result);
    return true;
}
```

## Cross-Contract ACL

When Contract A passes a ciphertext to Contract B:

```solidity
// Contract A:
function callContractB(euint64 myHandle) external {
    FHE.allowTransient(myHandle, address(contractB));  // transient: this tx only
    contractB.process(myHandle);
}

// For persistent access (Contract B can use it in future txs):
function grantPersistentAccess(euint64 myHandle, address contractB) external {
    FHE.allow(myHandle, contractB);
    // Note: still need FHE.allowThis for this contract too
}
```

## ACL Checklist

Apply this to every function that modifies encrypted state:

```
□ After every "x = FHE.op(...)":     FHE.allowThis(x)
□ For every user who reads x:        FHE.allow(x, userAddress)
□ Before cross-contract call:        FHE.allowTransient(x, contractAddr)
□ For mapping initialization:        both allowThis + allow in _ensureInit
□ For decryption requests:           FHE.allowThis before requestDecryption
```

## Debugging ACL Errors

| Error | Cause | Fix |
|---|---|---|
| `ACL: Not allowed` | Missing `FHE.allowThis` after assignment | Add `FHE.allowThis(handle)` after every `=` |
| `Re-encryption returns 0` | Missing `FHE.allow(handle, user)` | Add `FHE.allow` for the user |
| `Sender not allowed` | Cross-contract without `allowTransient` | Add `FHE.allowTransient` before cross-call |
| `ACL: handle does not exist` | Uninitialized mapping slot (`bytes32(0)`) | Initialize with `FHE.asEuintXX(0)` |

See [`error-reference.md`](error-reference.md) for full error details.
