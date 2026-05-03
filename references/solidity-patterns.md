# Solidity Patterns for FHEVM

This reference covers the canonical patterns for structuring confidential contracts.
For operation details see `fhe-operations.md`. For ACL rules see `access-control.md`.

---

## Contract Structure

### Minimal Contract (Local Hardhat)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity";

contract MyConfidential {
    // encrypted state — no network config needed for local Hardhat
    mapping(address => euint64) private _data;

    function store(externalEuint64 encValue, bytes calldata proof) external {
        euint64 value = FHE.fromExternal(encValue, proof); // verify ZK proof
        _data[msg.sender] = value;
        FHE.allowThis(_data[msg.sender]);         // contract can use handle
        FHE.allow(_data[msg.sender], msg.sender); // user can re-encrypt
    }

    function retrieve() external view returns (euint64) {
        return _data[msg.sender]; // returns handle; decrypt off-chain
    }
}
```

### Sepolia Testnet Contract

```solidity
import { FHE, euint64, externalEuint64 } from "@fhevm/solidity";
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";

contract MyConfidential is SepoliaFHEVMConfig {
    // ... same body
}
```

### Mainnet Contract

```solidity
import { FHE, euint64, externalEuint64 } from "@fhevm/solidity";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";

contract MyConfidential is ZamaEthereumConfig {
    // ... same body
}
```

**Rule**: Never hardcode ACL, KMS, coprocessor, or InputVerifier addresses. Always inherit the config contract for the target network.

---

## Initialization Pattern

Every encrypted mapping slot must be initialized before first use. Uninitialized slots are `bytes32(0)` which is not a valid ciphertext handle.

```solidity
mapping(address => euint64) private _balances;

function _ensureInit(address user) internal {
    if (!FHE.isInitialized(_balances[user])) {  // ✅ correct — not euint64.unwrap() == 0
        _balances[user] = FHE.asEuint64(0);
        FHE.allowThis(_balances[user]);
        FHE.allow(_balances[user], user);
    }
}

// Always call before any operation on the user's balance:
function deposit(externalEuint64 encAmount, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(encAmount, proof);
    _ensureInit(msg.sender);                                        // ← before FHE ops
    _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
    FHE.allowThis(_balances[msg.sender]);
    FHE.allow(_balances[msg.sender], msg.sender);
}
```

---

## Conditional Logic Pattern

**Never use `if/else` on `ebool`** — this leaks which branch was taken by executing different code paths.

```solidity
// ✅ Correct — FHE conditional (no leakage)
function transfer(address to, externalEuint64 encAmount, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(encAmount, proof);
    ebool canAfford = FHE.ge(_balances[msg.sender], amount);

    euint64 senderNew = FHE.select(canAfford, FHE.sub(_balances[msg.sender], amount), _balances[msg.sender]);
    euint64 receiverNew = FHE.select(canAfford, FHE.add(_balances[to], amount), _balances[to]);

    _balances[msg.sender] = senderNew;
    _balances[to] = receiverNew;

    FHE.allowThis(_balances[msg.sender]);
    FHE.allow(_balances[msg.sender], msg.sender);
    FHE.allowThis(_balances[to]);
    FHE.allow(_balances[to], to);
}

// ❌ Wrong — leaks whether sender could afford it
function transfer(address to, externalEuint64 encAmount, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(encAmount, proof);
    ebool canAfford = FHE.ge(_balances[msg.sender], amount);
    if (ebool.unwrap(canAfford) != 0) { // ← NEVER DO THIS
        // ... leaks branch
    }
}
```

---

## Mixed Plaintext + Encrypted State

Keep plaintext values plaintext unless the privacy model requires encryption. Unnecessary encryption wastes gas and adds ACL complexity.

```solidity
// Good: only the bid amount is private; timestamps and membership are public
contract Auction {
    mapping(address => euint64) private _bids;      // encrypted — amount is private
    mapping(address => bool) public hasBid;          // plaintext — participation is public
    uint256 public endTime;                          // plaintext — deadline is public
    uint256 public bidCount;                         // plaintext — count is public
    address[] public bidders;                        // plaintext — addresses are public

    function submitBid(externalEuint64 encAmount, bytes calldata proof) external {
        require(block.timestamp < endTime, "Auction ended");
        require(!hasBid[msg.sender], "Already bid");

        euint64 amount = FHE.fromExternal(encAmount, proof);
        _ensureInit(msg.sender);
        _bids[msg.sender] = amount;
        FHE.allowThis(_bids[msg.sender]);
        FHE.allow(_bids[msg.sender], msg.sender);

        hasBid[msg.sender] = true;   // plaintext — no FHE overhead
        bidCount++;                  // plaintext — no FHE overhead
        bidders.push(msg.sender);    // plaintext — no FHE overhead
    }
}
```

---

## Encrypted Accumulator Pattern

Running totals with FHE — always re-allow after each accumulation step.

```solidity
euint64 private _totalVotes;

function vote(externalEuint64 encWeight, bytes calldata proof) external {
    euint64 weight = FHE.fromExternal(encWeight, proof);

    if (!FHE.isInitialized(_totalVotes)) {  // ✅ not euint64.unwrap() == 0
        _totalVotes = FHE.asEuint64(0);
        FHE.allowThis(_totalVotes);
    }

    _totalVotes = FHE.add(_totalVotes, weight);
    FHE.allowThis(_totalVotes); // ← new handle after add, must re-allow
}
```

---

## Access Delegation Pattern

Allow another contract to use or compute with a handle.

```solidity
// Allow the router contract to use the handle
FHE.allow(encAmount, address(routerContract));

// Allow a third-party contract to decrypt for the user
FHE.allow(encBalance, address(escrowContract));
```

---

## Transient ACL Pattern

For values that are only needed within a single transaction (e.g., intermediate computation results passed to another contract in the same call stack).

```solidity
function computeAndForward(externalEuint64 enc, bytes calldata proof) external {
    euint64 value = FHE.fromExternal(enc, proof);
    euint64 doubled = FHE.mul(value, FHE.asEuint64(2));

    // Transient — only valid this transaction, cheaper than persistent allow
    FHE.allowTransient(doubled, address(downstreamContract));

    downstreamContract.process(doubled);
    // No FHE.allowThis needed here — value is not stored in this contract's state
}
```

**Use `FHE.allowTransient` when**:
- The handle crosses a contract boundary within the same transaction
- The handle is NOT stored in state — it's intermediate / temporary
- You want cheaper ACL overhead than a persistent `FHE.allow`

**Use `FHE.allow` when**:
- The handle is stored in state and must be accessible in future transactions

---

## Public Decryption Pattern

When the contract needs to reveal an encrypted value on-chain (e.g., announce auction winner, reveal final vote count):

```solidity
import { FHE, euint64, Gateway } from "@fhevm/solidity";

contract VotingReveal {
    euint64 private _encResult;
    uint64 public revealedResult;
    bool public isRevealed;
    uint256 private _pendingRequestId;

    function revealResult() external {
        require(!isRevealed, "Already revealed");

        // Step 1: mark handle as publicly decryptable
        FHE.makePubliclyDecryptable(_encResult);

        // Step 2: request gateway decryption (returns request ID)
        uint256[] memory handles = new uint256[](1);
        handles[0] = uint256(euint64.unwrap(_encResult));

        _pendingRequestId = Gateway.requestDecryption(
            handles,
            this.onResultRevealed.selector,
            0,
            block.timestamp + 100,
            false
        );
    }

    // Step 3: gateway calls this with the plaintext value
    function onResultRevealed(
        uint256 reqId,
        uint64 plaintext,
        bytes[] memory signatures
    ) public {
        require(reqId == _pendingRequestId, "Unknown request");
        FHE.checkSignatures(reqId, abi.encode(plaintext), abi.encode(signatures));
        revealedResult = plaintext;
        isRevealed = true;
    }
}
```

---

## Role-Based Access Pattern

Confidential data that different roles can access:

```solidity
contract ConfidentialReport {
    euint64 private _salary;
    address public employee;
    address public employer;
    address public auditor;

    constructor(address _employee, address _employer, address _auditor) {
        employee = _employee;
        employer = _employer;
        auditor  = _auditor;
    }

    function setSalary(externalEuint64 encSalary, bytes calldata proof) external {
        require(msg.sender == employer, "Only employer");
        euint64 s = FHE.fromExternal(encSalary, proof);
        _salary = s;
        FHE.allowThis(_salary);    // contract can compute
        FHE.allow(_salary, employee);  // employee can read their salary
        FHE.allow(_salary, employer);  // employer can re-check
        FHE.allow(_salary, auditor);   // auditor can verify
    }

    function getSalary() external view returns (euint64) {
        return _salary; // caller must have ACL permission to re-encrypt
    }
}
```

---

## Operator Pattern (ERC-7984 Style)

Delegate encrypted operations to an approved operator:

```solidity
mapping(address => mapping(address => euint64)) private _allowances;

function approve(address spender, externalEuint64 encAmount, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(encAmount, proof);
    _allowances[msg.sender][spender] = amount;
    FHE.allowThis(_allowances[msg.sender][spender]);
    FHE.allow(_allowances[msg.sender][spender], msg.sender);
    FHE.allow(_allowances[msg.sender][spender], spender); // ← spender can use the allowance
}
```

---

## Privacy Scope Disclaimer

Always clarify what is and is not private in any FHEVM contract:

| Data | Visibility |
|---|---|
| Mapping keys (addresses) | **Public** — blockchain sees all addresses |
| Transaction sender (`msg.sender`) | **Public** |
| Encrypted state VALUES (`euint64` contents) | **Private** — handle is public, value is not |
| Event topics and parameters | **Public** — do not emit plaintext values from decryption |
| Function call parameters (non-encrypted) | **Public** |
| `inputProof` bytes | **Public** (ZK proof, reveals nothing about the value) |
