# OpenZeppelin Confidential Contracts & ERC-7984

## Critical Notes Before You Begin

> **ERC-7984 is a draft standard.** It is not yet merged into the official Ethereum EIPs repository and is **not ERC-20 compatible**. Do not describe it as ERC-20 compatible to users.

> **API split — read this first.** `fhevm-contracts` v0.2.4 depends on `fhevm` ^0.6.x and uses the **`TFHE` namespace** with **`einput`** types. The newer standalone `@fhevm/solidity` package uses the **`FHE` namespace** with **`externalEuint64`** types. When extending `fhevm-contracts`, use `TFHE` in overrides. When writing standalone contracts, use `FHE`.

> **Config class name differs between packages** — see the table below. Using the wrong one silently routes FHE calls to the wrong network.

---

## Package Information

| Package | Version | Namespace | Input type | Config class |
|---|---|---|---|---|
| `fhevm-contracts` | 0.2.4 (2025-03-06) | `TFHE` | `einput` | `SepoliaZamaFHEVMConfig` |
| `fhevm` (core, used by fhevm-contracts) | 0.6.2 | `TFHE` | `einput` | `SepoliaZamaFHEVMConfig` |
| `fhevm` (core, latest standalone) | 0.12.2 (2026-04-28) | `TFHE` | — | — |
| `@fhevm/solidity` | separate newer package | `FHE` | `externalEuint64` | `SepoliaFHEVMConfig` |

```bash
# Install fhevm-contracts (includes fhevm as dependency)
npm install fhevm-contracts
pnpm add fhevm-contracts

# Dependencies pulled in automatically:
#   fhevm ^0.6.2
#   @openzeppelin/contracts ^5.1.0
#   @openzeppelin/contracts-upgradeable ^5.1.0
```

---

## Config Import — The Most Commonly Confused Difference

```solidity
// ─── When using fhevm-contracts ──────────────────────────────────────────────
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
// Class:  SepoliaZamaFHEVMConfig
// Source: "fhevm/..."

// ─── When using standalone @fhevm/solidity ────────────────────────────────────
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
// Class:  SepoliaFHEVMConfig
// Source: "@fhevm/solidity/..."
```

**Do not mix these.** Using `SepoliaFHEVMConfig` with `fhevm-contracts` (which uses the other package path) will fail to compile. Using `SepoliaZamaFHEVMConfig` with standalone `@fhevm/solidity` code will also fail.

---

## Complete Contract Inventory (fhevm-contracts v0.2.4)

### Token contracts

| Contract | Extends | Purpose |
|---|---|---|
| `ConfidentialERC20` | `IConfidentialERC20`, `TFHEErrors` | **Abstract base** — encrypted `euint64` balances and allowances |
| `ConfidentialERC20Mintable` | `ConfidentialERC20`, `Ownable2Step` | Adds owner-only `mint(address, uint64)` with plaintext amount |
| `ConfidentialERC20WithErrors` | `ConfidentialERC20`, `EncryptedErrors` | Encrypted error codes per transfer (see `EncryptedErrors`) |
| `ConfidentialERC20WithErrorsMintable` | `ConfidentialERC20WithErrors`, `Ownable2Step` | WithErrors + minting |
| `ConfidentialERC20Wrapped` | `ConfidentialERC20`, `GatewayCaller`, `ReentrancyGuardTransient` | Wrap/unwrap ERC-20 ↔ confidential ERC-20 |
| `ConfidentialWETH` | `ConfidentialERC20`, `GatewayCaller`, `ReentrancyGuardTransient` | Wrap/unwrap native ETH ↔ confidential ERC-20 |

### Governance contracts

| Contract | Purpose |
|---|---|
| `ConfidentialERC20Votes` | Governance token — encrypted delegate voting, based on Compound Comp.sol |
| `ConfidentialGovernorAlpha` | Full on-chain governance — encrypted voting, based on Compound GovernorAlpha |
| `CompoundTimelock` | Timelock for governance execution |

### Finance contracts

| Contract | Purpose |
|---|---|
| `ConfidentialVestingWallet` | Linear vesting schedule for ConfidentialERC20 tokens |
| `ConfidentialVestingWalletCliff` | Linear vesting with a cliff |

### Utility contracts

| Contract | Purpose |
|---|---|
| `EncryptedErrors` | Abstract utility — encrypted per-operation error codes using `euint8` |
| `TFHEErrors` | Interface — `TFHESenderNotAllowed` error for ACL failures |

---

## ConfidentialERC20 — The Base Contract

All confidential tokens inherit from this abstract contract.

### Key storage and properties

```solidity
// From ConfidentialERC20.sol (actual source):
uint256 internal constant _PLACEHOLDER = type(uint256).max; // used in events
uint64 internal _totalSupply;       // PLAINTEXT — publicly visible
string internal _name;
string internal _symbol;
mapping(address => euint64) internal _balances;             // encrypted
mapping(address => mapping(address => euint64)) internal _allowances; // encrypted

function decimals() public view virtual returns (uint8) {
    return 6;  // DEFAULT IS 6, not 18 — override if needed
}
function totalSupply() public view virtual returns (uint64) {
    return _totalSupply;  // plaintext uint64
}
```

### Interface (IConfidentialERC20) — actual source

```solidity
interface IConfidentialERC20 {
    // Events use _PLACEHOLDER (type(uint256).max) for amounts — never reveal values
    event Approval(address indexed owner, address indexed spender, uint256 placeholder);
    event Transfer(address indexed from, address indexed to, uint256 transferId);
    //              ↑ transferId = _PLACEHOLDER in base; counter index in WithErrors

    // Two overloads per function: (einput, proof) for fresh input; (euint64) for verified handle
    function approve(address spender, einput encryptedAmount, bytes calldata inputProof) external returns (bool);
    function approve(address spender, euint64 amount) external returns (bool);

    function transfer(address to, einput encryptedAmount, bytes calldata inputProof) external returns (bool);
    function transfer(address to, euint64 amount) external returns (bool);

    function transferFrom(address from, address to, einput encryptedAmount, bytes calldata inputProof) external returns (bool);
    function transferFrom(address from, address to, euint64 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (euint64);
    function balanceOf(address account) external view returns (euint64);
    function decimals() external view returns (uint8);   // returns 6
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint64); // PLAINTEXT
}
```

### Internal transfer — actual implementation

```solidity
// This is the exact logic from ConfidentialERC20._transferNoEvent:
function _transferNoEvent(address from, address to, euint64 amount, ebool isTransferable) internal virtual {
    // FHE conditional: if isTransferable, move amount; else move 0
    // This prevents leaking whether transfer succeeded via gas difference
    euint64 transferValue = TFHE.select(isTransferable, amount, TFHE.asEuint64(0));

    euint64 newBalanceTo = TFHE.add(_balances[to], transferValue);
    _balances[to] = newBalanceTo;
    TFHE.allowThis(newBalanceTo);
    TFHE.allow(newBalanceTo, to);   // receiver can re-encrypt their balance

    euint64 newBalanceFrom = TFHE.sub(_balances[from], transferValue);
    _balances[from] = newBalanceFrom;
    TFHE.allowThis(newBalanceFrom);
    TFHE.allow(newBalanceFrom, from); // sender can re-encrypt their balance
}
```

### ACL on approval — actual implementation

```solidity
// From ConfidentialERC20._approve:
function _approve(address owner, address spender, euint64 amount) internal virtual {
    _allowances[owner][spender] = amount;
    TFHE.allowThis(amount);          // contract can use it
    TFHE.allow(amount, owner);       // owner can re-read their own allowance
    TFHE.allow(amount, spender);     // spender can use / re-read the allowance
}
```

### ACL caller check — actual implementation

```solidity
// Called before every transfer/approve in ConfidentialERC20:
function _isSenderAllowedForAmount(euint64 amount) internal view virtual {
    if (!TFHE.isSenderAllowed(amount)) {
        revert TFHESenderNotAllowed();
    }
}
// Consequence: if you pass a euint64 handle that msg.sender doesn't have ACL for,
// the call reverts with TFHESenderNotAllowed — not a generic revert.
```

### Minting — no overflow check

```solidity
// _unsafeMint has NO overflow check. Caller must maintain invariant.
function _unsafeMintNoEvent(address account, uint64 amount) internal virtual {
    euint64 newBalance = TFHE.add(_balances[account], amount); // adds plaintext to encrypted
    _balances[account] = newBalance;
    TFHE.allowThis(newBalance);
    TFHE.allow(newBalance, account);
}
// After calling _unsafeMint, always update _totalSupply manually:
// _totalSupply += amount;
```

### Minimal concrete implementation

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20.sol";

/**
 * @notice Minimal confidential token on Sepolia.
 * @dev    ERC-7984 draft — NOT ERC-20 compatible.
 *         decimals() = 6 (default). totalSupply is plaintext.
 *         Balances and transfer amounts are encrypted.
 */
contract MyToken is SepoliaZamaFHEVMConfig, ConfidentialERC20 {
    constructor() ConfidentialERC20("MyToken", "MTK") {
        _unsafeMint(msg.sender, 1_000_000); // 1 MTK in 6-decimal units = 1_000_000
        _totalSupply = 1_000_000;
    }
}
```

---

## ConfidentialERC20Mintable

Adds owner-controlled minting. Mint amounts are **plaintext** (publicly observable on-chain).

```solidity
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20Mintable } from "fhevm-contracts/contracts/token/ERC20/extensions/ConfidentialERC20Mintable.sol";

contract MyMintableToken is SepoliaZamaFHEVMConfig, ConfidentialERC20Mintable {
    constructor(address owner)
        ConfidentialERC20Mintable("MyToken", "MTK", owner) {}
}

// Usage:
// token.mint(recipientAddress, 1_000_000); // mints 1 MTK (plaintext amount)
// token.totalSupply()                      // returns plaintext uint64
```

Key notes:
- `mint(address to, uint64 amount)` — `amount` is plaintext and observable by everyone
- Enforces `_totalSupply + amount` supply invariant to prevent overflow in encrypted arithmetic
- Uses `Ownable2Step` — new owner must explicitly accept ownership via `acceptOwnership()`
- Emits `Mint(address indexed to, uint64 amount)` event

---

## ConfidentialERC20WithErrors

Extends the base with **encrypted error codes** per transfer. Every transfer stores an encrypted `euint8` error code that only the sender and receiver can decrypt.

### Error codes

```solidity
enum ErrorCodes {
    NO_ERROR,              // 0 — transfer completed (amount may still be 0 if balance low)
    UNSUFFICIENT_BALANCE,  // 1 — sender's encrypted balance was too low
    UNSUFFICIENT_APPROVAL  // 2 — allowance was too low (transferFrom only)
}
```

### Transfer event difference

```solidity
// Base ConfidentialERC20:
emit Transfer(from, to, _PLACEHOLDER);  // _PLACEHOLDER = type(uint256).max

// ConfidentialERC20WithErrors:
emit Transfer(from, to, transferId);    // transferId = error counter index (incrementing)
// Save transferId from the event to later query the error code
```

### Reading an error code

```solidity
// Get the encrypted error handle using the saved transferId:
euint8 encError = token.getErrorCodeForTransferId(transferId);

// Decrypt off-chain with re-encryption — only sender or receiver can:
// Error 0 = success, 1 = insufficient balance, 2 = insufficient approval
```

### Full example

```solidity
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20WithErrorsMintable } from
    "fhevm-contracts/contracts/token/ERC20/extensions/ConfidentialERC20WithErrorsMintable.sol";

/**
 * @notice Confidential token with encrypted transfer error reporting.
 * @dev    Privacy: transfer direction and error existence are public.
 *         Transfer amounts and error reasons are private.
 */
contract AuditableToken is SepoliaZamaFHEVMConfig, ConfidentialERC20WithErrorsMintable {
    constructor(address owner)
        ConfidentialERC20WithErrorsMintable("AuditableToken", "AUDIT", owner) {}
}
```

Use `ConfidentialERC20WithErrors` when:
- You need privacy-preserving transfer failure reasons (DeFi, lending, DEX)
- Compliance flows need per-transfer audit trails without revealing amounts
- You want to distinguish "balance too low" from "allowance too low" in encrypted form

---

## ConfidentialERC20Wrapped

Wraps a standard ERC-20 into a confidential token using the Gateway for unwrap decryption.

### Key constraints and requirements

- Source ERC-20 must have `decimals() >= 6` — lower precision tokens are not supported
- Does **NOT** support rebase tokens or tokens with fee-on-transfer
- `maxDecryptionDelay` ≤ 1 day (86400 seconds), recommend ≥ 100s in production
- `isAccountRestricted[account]` blocks transfer + new unwrap during a pending unwrap
- Uses `ReentrancyGuardTransient` in the `callbackUnwrap` function
- Auto-generates name/symbol: "Wrapped Ether" → "Confidential Wrapped Ether" / "WETHc"

### Decimal adjustment

```
wrap(uint256 amount):
    amountAdjusted = amount / (10 ** (erc20.decimals() - 6))
    // e.g. USDC (6 dec): no adjustment
    // e.g. DAI  (18 dec): amountAdjusted = amount / 10^12
    // If amountAdjusted > type(uint64).max → revert AmountTooHigh
```

### Wrap / Unwrap flow — actual Gateway callback pattern

```solidity
// STEP 1: User wraps ERC-20 → encrypted balance (synchronous)
//   User calls: erc20.approve(address(wrapper), amount);
//   User calls: wrapper.wrap(uint256 amount);
//     → ERC20 safeTransferFrom → _unsafeMint(sender, amountUint64)

// STEP 2: User initiates unwrap (async — requires Gateway)
//   User calls: wrapper.unwrap(uint64 amount);  // plaintext requested amount
//     → isAccountRestricted[sender] = true      // blocks movement
//     → canUnwrap = TFHE.le(amount, _balances[sender])  // encrypted comparison
//     → Gateway.requestDecryption(canUnwrap, this.callbackUnwrap.selector, ...)

// STEP 3: Gateway calls back with plaintext boolean
//   Gateway calls: wrapper.callbackUnwrap(requestId, bool canUnwrap)
//     → if canUnwrap: _unsafeBurn + ERC20.transfer back to user
//     → else: emit UnwrapFailNotEnoughBalance
//     → isAccountRestricted[sender] = false  // unblock regardless
```

### Deploying a wrapped ERC-20

```solidity
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20Wrapped } from
    "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20Wrapped.sol";

// Wraps USDC (6 decimals — no adjustment needed):
contract ConfidentialUSDC is SepoliaZamaFHEVMConfig, ConfidentialERC20Wrapped {
    constructor() ConfidentialERC20Wrapped(
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC mainnet
        300  // maxDecryptionDelay 5 minutes — use ≥ 100s in production
    ) {}
    // Name: "Confidential USD Coin"  Symbol: "USDCc"  decimals: 6
}

// Wraps DAI (18 decimals — auto-adjusted to 6):
contract ConfidentialDAI is SepoliaZamaFHEVMConfig, ConfidentialERC20Wrapped {
    constructor() ConfidentialERC20Wrapped(
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI mainnet
        300
    ) {}
    // 1 DAI = 1e18 wei → stored as 1_000_000 in 6-decimal units
}
```

### Events (IConfidentialERC20Wrapped)

```solidity
event Wrap(address indexed account, uint64 amount);               // successful wrap
event Unwrap(address indexed account, uint64 amount);             // successful unwrap
event UnwrapFailNotEnoughBalance(address account, uint64 amount); // encrypted balance insufficient
event UnwrapFailTransferFail(address account, uint64 amount);     // ERC20.transfer reverted
```

### Error types

```solidity
error AmountTooHigh();          // wrap amount > type(uint64).max after decimal adjustment
error CannotTransferOrUnwrap(); // account has a pending unwrap (isAccountRestricted = true)
error MaxDecryptionDelayTooHigh(); // constructor: delay > 1 day
```

### UnwrapRequest struct

```solidity
struct UnwrapRequest {
    address account;
    uint64 amount;
}
mapping(uint256 requestId => UnwrapRequest) public unwrapRequests;
```

---

## ConfidentialWETH

Same pattern as `ConfidentialERC20Wrapped` but for native ETH. The `receive()` function calls `wrap()`.

```solidity
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialWETH } from "fhevm-contracts/contracts/token/ERC20/ConfidentialWETH.sol";

contract MyConfidentialWETH is SepoliaZamaFHEVMConfig, ConfidentialWETH {
    constructor() ConfidentialWETH(300) {}  // 300s max decryption delay
}

// Wrap: send ETH directly (receive() calls wrap()):
// (bool ok,) = address(weth).call{value: 1 ether}("");
// or:
// weth.wrap{value: 1 ether}();
// → amountAdjusted = msg.value / 10^(18-6) = msg.value / 1e12

// Unwrap (uint64 in 6-decimal units):
// weth.unwrap(1_000_000);  // unwrap 1 WETH (in 6-decimal units)
```

Key difference from `ConfidentialERC20Wrapped`:
- Wrapping takes `msg.value` (ETH), not ERC-20 `safeTransferFrom`
- No `wrap(uint256)` with approval step — just send ETH
- Error on unwrap: ETH transfer failure → `ETHTransferFail`

---

## ConfidentialERC20Votes

Governance token with encrypted voting power delegation. Based on Compound's Comp.sol.

### Critical privacy warning

> **Delegation leaks balance information to the delegatee.** When an account delegates to another address, the delegatee gains read access to the delegator's encrypted vote balance. Do not use if this level of information leakage is unacceptable for your privacy model.

### Key data structures

```solidity
struct Checkpoint {
    uint256 fromBlock;
    euint64 votes;  // encrypted vote count at checkpoint block
}

mapping(address => address) public delegates;              // current delegate per account
mapping(address => uint256) public nonces;                 // EIP-712 signature nonces
mapping(address => uint32) public numCheckpoints;          // checkpoint count per account
mapping(address => mapping(uint32 => Checkpoint)) internal _checkpoints;

address public governor;  // only this address can access encrypted votes
                          // set via setGovernor() (owner only)

bytes32 public constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");
```

### Constructor and deployment

```solidity
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20Votes } from
    "fhevm-contracts/contracts/governance/ConfidentialERC20Votes.sol";

contract MyGovernanceToken is SepoliaZamaFHEVMConfig, ConfidentialERC20Votes {
    constructor(address owner, uint64 totalSupply)
        ConfidentialERC20Votes(
            owner,
            "MyGovToken",    // name
            "MGT",           // symbol
            "1",             // version for EIP-712
            totalSupply      // minted to owner at deployment
        ) {}
}
```

### Usage

```solidity
// On-chain delegation:
token.delegate(delegateeAddress);

// Gasless delegation via EIP-712 signature:
token.delegateBySig(delegator, delegatee, nonce, expiry, signature);

// Cancel a delegation signature (increments nonce):
token.incrementNonce();

// Set governor contract (owner only):
token.setGovernor(governorContractAddress);
```

### Events

```solidity
event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
event NewGovernor(address indexed governor);
event NonceIncremented(address account, uint256 newNonce);
```

---

## ConfidentialGovernorAlpha

Full on-chain governance based on Compound GovernorAlpha. Uses Gateway decryption to tally encrypted votes.

### Proposal lifecycle

```
Pending
  → PendingThresholdVerification  (created, awaiting proposer threshold check)
     → Rejected                   (proposer below token threshold)
     → Active                     (threshold verified, voting open)
        → Succeeded               (quorum + for > against, after endBlock)
           → Queued               (proposal queued in Timelock)
              → Executed          (Timelock delay elapsed, executed)
        → Defeated                (quorum not met, or against ≥ for)
  → Canceled                      (proposer cancels at any state)
```

### Constructor

```solidity
constructor(
    address owner_,
    address timelock_,            // ICompoundTimelock address
    address governanceToken_,     // ConfidentialERC20Votes address
    uint256 maxDecryptionDelay_   // ≤ 1 day
)
```

### Creating a proposal

```solidity
uint256 proposalId = governor.propose(
    targets,      // address[] — contract addresses to call
    values,       // uint256[] — ETH to send per call
    signatures,   // string[]  — function signatures (e.g. "transfer(address,uint256)")
    calldatas,    // bytes[]   — ABI-encoded arguments
    "Fund the community treasury"  // description
);
```

### Casting an encrypted vote

```solidity
// Votes are encrypted — only the voter knows how they voted
governor.castVote(
    proposalId,
    encryptedSupport,  // einput — encrypted bool: true=for, false=against
    inputProof         // bytes — ZK proof
);
```

### Error types

```solidity
error LengthAboveMaxOperations();   // too many actions in proposal
error LengthIsNull();               // empty arrays
error LengthsDoNotMatch();          // array length mismatch
error MaxDecryptionDelayTooHigh();  // > 1 day
error ProposalActionsAlreadyQueued();
error ProposalStateInvalid();       // wrong state for the operation
error ProposalStateNotActive();     // block.number > endBlock
error ProposalStateStillActive();   // voting not yet finished
error ProposerHasAnotherProposal(); // one active proposal per proposer
error VoterHasAlreadyVoted();       // duplicate vote
```

---

## EncryptedErrors

Abstract utility contract for encrypted error tracking. Provides per-operation encrypted error codes using `euint8`.

### Constructor

```solidity
constructor(uint8 totalNumberErrorCodes_)
// totalNumberErrorCodes_ must be > 0
// Index 0 is always NO_ERROR
// All error code definitions are pre-encrypted in the constructor
```

### Full API

```solidity
// ─── Conditional error setters ───────────────────────────────────────────────

// Set error to indexCode if condition is true, else NO_ERROR
_errorDefineIf(ebool condition, uint8 indexCode) → euint8

// Set error to indexCode if condition is false, else NO_ERROR
_errorDefineIfNot(ebool condition, uint8 indexCode) → euint8

// Replace errorCode with indexCode if condition is true, else keep errorCode
_errorChangeIf(ebool condition, uint8 indexCode, euint8 errorCode) → euint8

// Replace errorCode with indexCode if condition is false, else keep errorCode
_errorChangeIfNot(ebool condition, uint8 indexCode, euint8 errorCode) → euint8

// ─── Storage ─────────────────────────────────────────────────────────────────

// Save errorCode to storage, grants TFHE.allowThis, returns storage index
_errorSave(euint8 errorCode) → uint256 errorId

// ─── Readers ─────────────────────────────────────────────────────────────────

// Get saved error by storage index (must be < _errorGetCounter())
_errorGetCodeEmitted(uint256 errorId) → euint8

// Get pre-defined error code by index (0 = NO_ERROR)
_errorGetCodeDefinition(uint8 indexCodeDefinition) → euint8

// Total number of errors emitted so far
_errorGetCounter() → uint256

// Total number of possible error codes (set in constructor)
_errorGetNumCodesDefined() → uint8
```

### Custom error code example

```solidity
import "fhevm/lib/TFHE.sol";
import { EncryptedErrors } from "fhevm-contracts/contracts/utils/EncryptedErrors.sol";

contract ConfidentialLending is EncryptedErrors {
    enum ErrorCodes {
        NO_ERROR,                   // 0
        INSUFFICIENT_COLLATERAL,    // 1
        BORROW_CAP_EXCEEDED,        // 2
        LIQUIDATION_REQUIRED        // 3
    }

    constructor() EncryptedErrors(uint8(type(ErrorCodes).max)) {
        // Encrypts error codes 0–3 in constructor storage
    }

    function borrow(address user, euint64 amount) external returns (uint256 transferId) {
        ebool hasCollateral = TFHE.ge(_collateral[user], amount);
        ebool underCap = TFHE.lt(TFHE.add(_totalBorrowed, amount), _borrowCap);

        // Define initial error (insufficient collateral)
        euint8 error = _errorDefineIfNot(hasCollateral, uint8(ErrorCodes.INSUFFICIENT_COLLATERAL));

        // Upgrade error if cap exceeded AND collateral was fine
        error = _errorChangeIf(
            TFHE.and(hasCollateral, TFHE.not(underCap)),
            uint8(ErrorCodes.BORROW_CAP_EXCEEDED),
            error
        );

        // Save to storage
        transferId = _errorSave(error);
        TFHE.allow(error, user);  // only user can decrypt their error

        // Conditional borrow: only if both checks pass
        ebool canBorrow = TFHE.and(hasCollateral, underCap);
        euint64 actualBorrow = TFHE.select(canBorrow, amount, TFHE.asEuint64(0));
        // ... update _borrowed[user], _totalBorrowed
    }
}
```

---

## ConfidentialVestingWallet

Linear vesting schedule for ConfidentialERC20 tokens. Based on OZ's VestingWallet.

### Key properties

```solidity
address public immutable BENEFICIARY;
uint128 public immutable DURATION;
uint128 public immutable START_TIMESTAMP;
uint128 public immutable END_TIMESTAMP;    // = START_TIMESTAMP + DURATION
euint64 internal immutable _EUINT64_ZERO;  // cached FHE zero (expensive to recompute)

mapping(address token => euint64 amountReleased) internal _amountReleased;
```

### Constructor and deployment

```solidity
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialVestingWallet } from
    "fhevm-contracts/contracts/finance/ConfidentialVestingWallet.sol";

// Linear vesting, no cliff:
contract MyVesting is SepoliaZamaFHEVMConfig, ConfidentialVestingWallet {
    constructor(address beneficiary)
        ConfidentialVestingWallet(
            beneficiary,
            uint128(block.timestamp),   // start now
            uint128(365 days)           // vest over 1 year
        ) {}
}
```

### Important: ACL setup in constructor

```solidity
// From ConfidentialVestingWallet constructor:
_EUINT64_ZERO = TFHE.asEuint64(0);
TFHE.allow(_EUINT64_ZERO, beneficiary_);  // beneficiary can read zero handle
TFHE.allowThis(_EUINT64_ZERO);
```

### Usage

```solidity
// Anyone can trigger release — beneficiary receives tokens:
wallet.release(address(tokenContract));

// Beneficiary reads released amount (re-encryption required):
euint64 releasedHandle = wallet.released(address(tokenContract));
// → decrypt off-chain: only BENEFICIARY can re-encrypt (ACL set in constructor)
```

### Cross-contract transfer pattern (actual source)

```solidity
// From ConfidentialVestingWallet.release():
TFHE.allowTransient(amount, token);  // transient ACL for the transfer call
IConfidentialERC20(token).transfer(BENEFICIARY, amount);
// Note: uses TFHE.allowTransient (not TFHE.allow) since amount is not stored
```

---

## ConfidentialVestingWalletCliff

Extends `ConfidentialVestingWallet` with a cliff — no tokens vest before the cliff date.

```solidity
import { ConfidentialVestingWalletCliff } from
    "fhevm-contracts/contracts/finance/ConfidentialVestingWalletCliff.sol";

contract CliffVesting is SepoliaZamaFHEVMConfig, ConfidentialVestingWalletCliff {
    constructor(address beneficiary)
        ConfidentialVestingWalletCliff(
            beneficiary,
            uint128(block.timestamp),  // start now
            uint128(4 * 365 days),     // 4-year total vesting
            uint128(365 days)          // 1-year cliff: nothing until year 1
        ) {}
    // CLIFF = START_TIMESTAMP + cliffSeconds
    // error InvalidCliffDuration if cliffSeconds > duration
}

// The override:
function _vestingSchedule(euint64 totalAllocation, uint128 timestamp)
    internal virtual override returns (euint64) {
    // Before cliff: return _EUINT64_ZERO (0 tokens, no FHE cost)
    // After cliff:  fall through to parent linear schedule
    return timestamp < CLIFF ? _EUINT64_ZERO : super._vestingSchedule(totalAllocation, timestamp);
}
```

---

## Transfer Events and Privacy

```solidity
// Base ConfidentialERC20: amounts replaced with _PLACEHOLDER
event Transfer(from, to, type(uint256).max);   // direction public, amount private
event Approval(owner, spender, type(uint256).max);  // parties public, amount private

// ConfidentialERC20WithErrors: transferId is the error counter index
event Transfer(from, to, transferId);  // transferId used to look up encrypted error
```

**What is and is NOT private:**

| Data | Visibility |
|---|---|
| Transfer direction (from → to) | **Public** |
| Transfer existence (event on-chain) | **Public** |
| Transfer amount | **Private** (encrypted handle) |
| Approval parties | **Public** |
| Approval amount | **Private** |
| Total supply | **Public** (plaintext `uint64`) |
| Mint amounts | **Public** (plaintext in events) |
| Participant addresses | **Public** |
| `isAccountRestricted` status | **Public** (unwrap in progress) |
| Wrap/unwrap amounts | **Public** (in Wrap/Unwrap events) |

---

## Integration Checklist

When building on top of `fhevm-contracts`, verify before deploying:

- [ ] Using `TFHE` namespace (not `FHE`) in overrides and extensions
- [ ] Using `einput encryptedAmount, bytes calldata inputProof` in public functions accepting fresh user input
- [ ] Using `TFHE.asEuint64(encryptedAmount, inputProof)` to unwrap `einput` (not `FHE.fromExternal`)
- [ ] Config: `SepoliaZamaFHEVMConfig` from `"fhevm/config/ZamaFHEVMConfig.sol"` (not `@fhevm/solidity` path)
- [ ] `_totalSupply` updated manually after `_unsafeMint` / `_unsafeBurn`
- [ ] `decimals()` overridden if you need 18 (default is 6)
- [ ] `_EUINT64_ZERO` / `_EUINT64_TFHE_ZERO` stored if needed frequently (FHE zero is expensive)
- [ ] `isAccountRestricted` respected in any `_transferNoEvent` override
- [ ] `maxDecryptionDelay` ≥ 100 seconds in production
- [ ] Source ERC-20 for Wrapped: `decimals() >= 6`, no rebase, no fee-on-transfer
- [ ] `ConfidentialERC20Votes`: governor set before governance begins
- [ ] `cliffSeconds ≤ duration` for `ConfidentialVestingWalletCliff`
- [ ] ERC-7984 draft warning communicated to users

---

## Common Errors Specific to fhevm-contracts

| Error | Cause | Fix |
|---|---|---|
| `TFHESenderNotAllowed` | Transfer/approve called with handle caller doesn't own | Ensure `TFHE.allow(handle, caller)` was called |
| `AmountTooHigh` | Wrap amount > `uint64.max` after decimal adjustment | Check: 18-dec token / 1e12; cap at ~1.84e13 |
| `CannotTransferOrUnwrap` | Account has pending unwrap (`isAccountRestricted = true`) | Wait for Gateway callback to complete |
| `MaxDecryptionDelayTooHigh` | Constructor `maxDecryptionDelay > 1 days` | Set ≤ 86400 |
| `InvalidCliffDuration` | Cliff > vesting duration in VestingWalletCliff | Ensure cliff ≤ duration |
| `GovernorInvalid` | Governor-only function called from wrong address | Set via `setGovernor()` (owner only) |
| `ErrorIndexInvalid` | EncryptedErrors index ≥ totalNumberErrorCodes | Check constructor count; use correct index |
| `ErrorIndexIsNull` | EncryptedErrors index 0 used in define/change (0 = NO_ERROR) | Start error codes at index 1 |
| Gateway callback never fires | Delay too short or Gateway not configured on testnet | Use ≥ 100s delay; verify Sepolia Gateway address |
| Balance stays 0 after transfer | Missing `TFHE.allow(newBalance, receiver)` in override | Call `super._transferNoEvent(...)` first |
| Wrong `transferId` from event | Reading `_PLACEHOLDER` as transferId on base contract | Only `WithErrors` variant uses meaningful transferId |
| Approval not working | Using plaintext amount instead of `(spender, einput, proof)` | Use the `einput` overload |
| `SepoliaZamaFHEVMConfig` not found | Using `@fhevm/solidity` import path instead of `fhevm` | Use `"fhevm/config/ZamaFHEVMConfig.sol"` |

See [`error-reference.md`](error-reference.md) for the full 50+ error catalog.
