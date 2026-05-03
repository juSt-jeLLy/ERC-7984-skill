# FHE Operations Reference

All FHE operations are performed via the `FHE` library imported from `@fhevm/solidity`. Operations produce new handles — you must re-grant ACL permissions after every assignment.

## Arithmetic Operations

All arithmetic is **modular** (wraps around the type's max value, no overflow reverts).

```solidity
import { FHE, euint64 } from "@fhevm/solidity";

euint64 a = FHE.asEuint64(100);
euint64 b = FHE.asEuint64(50);

// Addition
euint64 sum = FHE.add(a, b);        // 150
FHE.allowThis(sum);

// Subtraction (wraps on underflow — 0 - 1 = 2^64 - 1 for euint64)
euint64 diff = FHE.sub(a, b);       // 50
FHE.allowThis(diff);

// Multiplication
euint64 product = FHE.mul(a, b);    // 5000
FHE.allowThis(product);

// Division (by plaintext scalar only — encrypted divisor not supported)
euint64 quotient = FHE.div(a, 10);  // 10
FHE.allowThis(quotient);

// Remainder (by plaintext scalar only)
euint64 rem = FHE.rem(a, 7);        // 2
FHE.allowThis(rem);
```

## Bitwise Operations

```solidity
euint64 x = FHE.asEuint64(0xFF);
euint64 y = FHE.asEuint64(0x0F);

euint64 andResult = FHE.and(x, y);   // 0x0F
euint64 orResult  = FHE.or(x, y);    // 0xFF
euint64 xorResult = FHE.xor(x, y);   // 0xF0
euint64 notResult = FHE.not(x);      // bitwise NOT

// Shifts (by plaintext amount)
euint64 leftShift  = FHE.shl(x, 4);  // shift left by 4 bits
euint64 rightShift = FHE.shr(x, 4);  // shift right by 4 bits
euint64 rotLeft    = FHE.rotl(x, 4); // rotate left by 4 bits
euint64 rotRight   = FHE.rotr(x, 4); // rotate right by 4 bits
```

## Comparison Operations (Return `ebool`)

Comparisons operate on encrypted values and return an encrypted boolean.

```solidity
euint64 a = FHE.asEuint64(100);
euint64 b = FHE.asEuint64(50);

ebool isGt  = FHE.gt(a, b);   // a > b  → true
ebool isGte = FHE.gte(a, b);  // a >= b → true
ebool isLt  = FHE.lt(a, b);   // a < b  → false
ebool isLte = FHE.lte(a, b);  // a <= b → false
ebool isEq  = FHE.eq(a, b);   // a == b → false
ebool isNeq = FHE.ne(a, b);   // a != b → true

// Min and Max (return encrypted value, not boolean)
euint64 minVal = FHE.min(a, b);   // 50
euint64 maxVal = FHE.max(a, b);   // 100
FHE.allowThis(minVal);
FHE.allowThis(maxVal);
```

### Comparison With Plaintext Scalar

You can compare an encrypted value to an unencrypted scalar:

```solidity
euint64 balance = _balances[msg.sender];
euint64 threshold = FHE.asEuint64(1000);

ebool isAboveThreshold = FHE.gt(balance, threshold);
// Or with scalar directly (may not be supported in all versions — use asEuintXX):
ebool isAbove = FHE.gt(balance, FHE.asEuint64(1000));
```

## Conditional Selection (`FHE.select`)

**Never use `if/else` on encrypted booleans** — branching on `ebool` leaks information about which branch was taken. Use `FHE.select()` instead (equivalent to a ternary operator on ciphertexts):

```solidity
ebool condition = FHE.gt(a, b);

// FHE.select(condition, ifTrue, ifFalse)
euint64 result = FHE.select(condition, a, b);  // if a > b then a else b → max(a, b)
FHE.allowThis(result);
```

### Conditional Transfer Pattern

```solidity
// ✅ Safe confidential transfer — no leaking whether transfer succeeded
function transfer(address to, externalEuint64 encAmount, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(encAmount, proof);

    _ensureInit(to);

    ebool hasEnough = FHE.gte(_balances[msg.sender], amount);

    // If sender has enough: actualAmount = amount, else actualAmount = 0
    euint64 actualAmount = FHE.select(hasEnough, amount, FHE.asEuint64(0));

    _balances[msg.sender] = FHE.sub(_balances[msg.sender], actualAmount);
    _balances[to]         = FHE.add(_balances[to], actualAmount);

    FHE.allowThis(_balances[msg.sender]);
    FHE.allow(_balances[msg.sender], msg.sender);
    FHE.allowThis(_balances[to]);
    FHE.allow(_balances[to], to);
}
```

## Boolean Operations

```solidity
ebool a = FHE.asEbool(true);
ebool b = FHE.asEbool(false);

ebool andResult = FHE.and(a, b);  // false
ebool orResult  = FHE.or(a, b);   // true
ebool xorResult = FHE.xor(a, b);  // true
ebool notResult = FHE.not(a);     // false
```

## Address Operations

```solidity
eaddress encAddr = FHE.asEaddress(msg.sender);

// Compare two encrypted addresses
ebool isSame = FHE.eq(encAddr, otherEncAddr);

// Select based on condition
eaddress winner = FHE.select(condition, encAddr1, encAddr2);
FHE.allowThis(winner);
```

## Gas Cost Guidelines

FHE operations are expensive compared to regular EVM ops. Approximate relative costs (higher = more expensive):

| Operation | Relative Gas |
|---|---|
| `FHE.add` / `FHE.sub` | Low |
| `FHE.gt` / `FHE.lt` / `FHE.eq` | Low |
| `FHE.select` | Low |
| `FHE.mul` | Medium |
| `FHE.div` / `FHE.rem` | High |
| `FHE.fromExternal` | Medium (ZK verification) |
| `FHE.requestDecryption` | Medium (gateway call) |

**Tips:**
- Minimize the number of FHE operations per transaction
- Prefer `euint32` or `euint64` over `euint256` when possible — smaller types are cheaper
- Batch related operations in a single transaction
- Use `FHE.select()` instead of multiple conditional paths

## Operation Availability by Type

Most operations work on all integer types. Not all operations are available on all types:

| Operation | `euint8-256` | `ebool` | `eaddress` |
|---|---|---|---|
| `add`, `sub`, `mul` | ✅ | ❌ | ❌ |
| `div`, `rem` | ✅ | ❌ | ❌ |
| `gt`, `lt`, `gte`, `lte` | ✅ | ❌ | ❌ |
| `eq`, `ne` | ✅ | ✅ | ✅ |
| `and`, `or`, `xor`, `not` | ✅ | ✅ | ❌ |
| `min`, `max` | ✅ | ❌ | ❌ |
| `select` | ✅ | ✅ | ✅ |
| `shl`, `shr`, `rotl`, `rotr` | ✅ | ❌ | ❌ |
