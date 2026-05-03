# FHEVM Encrypted Types

## Type Overview

FHEVM introduces custom Solidity types for encrypted values. These are all backed by `bytes32` handles internally.

### Integer Types

| Solidity Type | Description | Range |
|---|---|---|
| `euint8` | Encrypted 8-bit unsigned int | 0 – 255 |
| `euint16` | Encrypted 16-bit unsigned int | 0 – 65,535 |
| `euint32` | Encrypted 32-bit unsigned int | 0 – 4,294,967,295 |
| `euint64` | Encrypted 64-bit unsigned int | 0 – 18,446,744,073,709,551,615 |
| `euint128` | Encrypted 128-bit unsigned int | 0 – 2^128 - 1 |
| `euint256` | Encrypted 256-bit unsigned int | 0 – 2^256 - 1 |

### Other Types

| Solidity Type | Description |
|---|---|
| `ebool` | Encrypted boolean |
| `eaddress` | Encrypted Ethereum address (160-bit) |

### External Input Types

These are used only as **function parameters** for user-submitted encrypted values. They are NOT valid in FHE operations — you must verify them first with `FHE.fromExternal()`.

| External Type | Corresponds To |
|---|---|
| `externalEuint8` | Input for `euint8` |
| `externalEuint16` | Input for `euint16` |
| `externalEuint32` | Input for `euint32` |
| `externalEuint64` | Input for `euint64` |
| `externalEuint128` | Input for `euint128` |
| `externalEuint256` | Input for `euint256` |
| `externalEbool` | Input for `ebool` |
| `externalEaddress` | Input for `eaddress` |

## Importing Types

```solidity
// Import specific types you need:
import { FHE, euint64, euint32, euint8, ebool, eaddress,
         externalEuint64, externalEuint32 } from "@fhevm/solidity";
```

## Creating Encrypted Values

### From a Plaintext Constant (on-chain)

```solidity
euint8  val8  = FHE.asEuint8(42);
euint16 val16 = FHE.asEuint16(1000);
euint32 val32 = FHE.asEuint32(1_000_000);
euint64 val64 = FHE.asEuint64(1_000_000_000);
ebool   flag  = FHE.asEbool(true);
eaddress addr = FHE.asEaddress(msg.sender);
```

**Note:** Using `FHE.asEuintXX(plaintext)` encodes a plaintext into a trivial ciphertext. The value is NOT secret — anyone who reads the contract source can see it. Only use this for public initialization values (like zero) or publicly known constants.

### From User Input (Off-Chain Encrypted)

```solidity
function deposit(externalEuint64 encAmount, bytes calldata proof) external {
    // FHE.fromExternal verifies the ZK proof and converts to a proper euint64
    euint64 amount = FHE.fromExternal(encAmount, proof);
    // Now 'amount' is a verified encrypted value — safe to use in FHE ops
}
```

## Type Casting

### Upcasting (Safe — No Data Loss)

```solidity
euint8  small = FHE.asEuint8(10);
euint32 mid   = FHE.asEuint32(small);   // safe upcast
euint64 big   = FHE.asEuint64(mid);     // safe upcast
euint128 huge = FHE.asEuint128(big);    // safe upcast
```

### Downcasting (Lossy — High Bits Truncated)

```solidity
euint64 big   = FHE.asEuint64(500);
euint32 small = FHE.asEuint32(big);     // ⚠️ truncates high 32 bits — use carefully
euint8  tiny  = FHE.asEuint8(big);      // ⚠️ only low 8 bits survive
```

### Forbidden Casts

```solidity
// ❌ Cannot directly cast euint64 to eaddress — addresses are 160-bit
euint64 x = FHE.asEuint64(100);
eaddress a = FHE.asEaddress(x);  // WRONG — use euint160 intermediate if needed

// ❌ Cannot cast euint64 to ebool — use comparison instead
ebool flag = FHE.asEbool(x);  // WRONG
ebool flag = FHE.gt(x, FHE.asEuint64(0));  // ✅ CORRECT
```

### Type Casting Rules

| From | To | Method | Safe? |
|---|---|---|---|
| `euint8` → `euint64` | upcast | `FHE.asEuint64(x)` | ✅ always |
| `euint64` → `euint8` | downcast | `FHE.asEuint8(x)` | ⚠️ truncates |
| `euint64` → `eaddress` | special | Only via `euint160` | ❌ usually wrong |
| `euint64` → `ebool` | comparison | `FHE.gt(x, zero)` | ✅ correct way |

## Unwrapping Handles

Sometimes you need the raw `bytes32` handle:

```solidity
euint64 balance = _balances[user];
bytes32 rawHandle = euint64.unwrap(balance);

// Check if initialized (zero handle = uninitialized):
bool isInitialized = (euint64.unwrap(_balances[user]) != 0);

// Wrap a raw handle back:
euint64 restored = euint64.wrap(rawHandle);
```

## Storage Patterns

```solidity
// Single encrypted value
euint64 private _totalSupply;

// Encrypted mapping (balances)
mapping(address => euint64) private _balances;

// Encrypted mapping of mappings (allowances)
mapping(address => mapping(address => euint64)) private _allowances;

// Array of encrypted values (be careful with gas)
euint64[] private _bids;
```

## Initialization (Critical)

All encrypted state variables and mapping entries default to `bytes32(0)`, which is **not a valid FHE handle**. You must initialize before first use:

```solidity
// Pattern 1: Constructor initialization
constructor() {
    _totalSupply = FHE.asEuint64(0);
    FHE.allowThis(_totalSupply);
}

// Pattern 2: Lazy initialization in functions
function _ensureInit(address user) internal {
    if (!FHE.isInitialized(_balances[user])) {  // ✅ correct — works for all types including ebool
        _balances[user] = FHE.asEuint64(0);
        FHE.allowThis(_balances[user]);
        FHE.allow(_balances[user], user);
    }
    // ❌ AVOID: euint64.unwrap(_balances[user]) == 0  — fragile, breaks on ebool/eaddress
}
```

## Frontend Type Mapping

Match the JavaScript encryption method to the Solidity parameter type exactly:

| Solidity Parameter | Frontend Call | Max Value |
|---|---|---|
| `externalEuint8` | `input.add8(n)` | 255 |
| `externalEuint16` | `input.add16(n)` | 65,535 |
| `externalEuint32` | `input.add32(n)` | 4,294,967,295 |
| `externalEuint64` | `input.add64(n)` | 18,446,744,073,709,551,615n |
| `externalEuint128` | `input.add128(n)` | 2n**128n - 1n |
| `externalEuint256` | `input.add256(n)` | 2n**256n - 1n |
| `externalEbool` | `input.addBool(b)` | true / false |
| `externalEaddress` | `input.addAddress(addr)` | any address string |

Mismatch → `InputLengthAbove64Bytes` or similar error. See [`error-reference.md`](error-reference.md).
