# FHEVM Architecture

## What Is FHEVM?

**FHEVM** (Fully Homomorphic Encryption Virtual Machine) is the core of the **Zama Confidential Blockchain Protocol**. It enables confidential smart contracts on Ethereum and EVM-compatible chains by letting smart contracts compute on **encrypted data** without ever decrypting it.

Key guarantees:
- **End-to-end encryption**: Transaction inputs and contract state are encrypted — no party can see them during computation.
- **On-chain composability**: Encrypted state can be composed across contracts, just like normal state.
- **Programmable privacy**: Developers define exactly what is encrypted and who can decrypt.
- **No impact on existing contracts**: Encrypted state coexists with public state.

## How FHE Works On-Chain

Traditional blockchains: every validator sees all data.

FHEVM model:
1. User encrypts a value client-side using the **network's public key**.
2. The ciphertext is submitted on-chain with a **ZK proof** (input proof) proving it is well-formed.
3. The smart contract performs FHE operations (add, compare, select, etc.) — all on ciphertexts. The results are new ciphertexts stored as **handles** (`bytes32` references).
4. The **coprocessor** (off-chain FHE compute engine) executes the actual homomorphic operations asynchronously.
5. A **Key Management System (KMS)** using MPC manages decryption keys — no single party holds the full key.
6. Authorized users request **re-encryption** of a handle under their own public key (user decryption) or trigger **public decryption** via a Gateway callback.

## Component Map

```
User Browser
  │  encrypts input → ciphertext + ZK proof
  │
  ▼
Smart Contract (Solidity)
  │  FHE.fromExternal(enc, proof)  → verified euintXX handle
  │  FHE.add / FHE.mul / FHE.cmux → new handle (bytes32)
  │  FHE.allowThis / FHE.allow    → ACL permissions
  │
  ▼
Ethereum (Host Chain)
  │  symbolic execution of FHE ops
  │  stores handles in state
  │
  ▼
Coprocessor (Off-chain, Zama)
  │  actually executes homomorphic math
  │  produces ciphertext results
  │
  ▼
KMS (Key Management Service)
  │  MPC-based — decentralized key custody
  │  handles re-encryption + public decryption
  │
  ▼
User / dApp
     re-encrypts handle → plaintext (for user only)
     OR: public decrypt callback → plaintext on-chain
```

## Key Concepts

### Handles
Every encrypted value is represented as a `bytes32` **handle** in Solidity — a reference to the ciphertext managed by the coprocessor. The handle itself is public; the value it references is private.

```solidity
euint64 private _balance;  // internally a bytes32 handle
```

### ACL (Access Control List)
The ACL contract tracks which addresses and contracts are allowed to use each handle:
- `FHE.allowThis(handle)` — grants the current contract permission to use the handle in future transactions
- `FHE.allow(handle, addr)` — grants an address permission to re-encrypt the handle
- `FHE.allowTransient(handle, addr)` — grants transient permission (current tx only, for cross-contract calls)

**Critical**: Every FHE operation produces a NEW handle. You must re-grant ACL permissions after every assignment.

### The Coprocessor
FHE operations in Solidity are **symbolic** — the EVM just records what operation was requested. The actual homomorphic computation happens asynchronously in Zama's coprocessor, which produces the encrypted result and stores it under the handle.

### Input Proofs
When a user sends an encrypted value to a contract, they must include a **ZK proof** (`inputProof`) proving:
- The ciphertext is well-formed (correct encryption)
- It was encrypted for this specific contract and sender

This prevents malleability attacks. The proof is bound to `(contractAddress, userAddress)` — it cannot be reused for other contracts or transactions.

## Deployment Environments

| Environment | Description | Use Case |
|---|---|---|
| `hardhat` (local) | Cleartext mock mode — FHE ops run as plain math, no real encryption | Fast dev/testing |
| Sepolia testnet | Real FHE with Zama's testnet coprocessor + KMS | Pre-production testing |
| Ethereum mainnet | Production FHE | Production dApps |

## Use Cases

- **Confidential token transfers**: Keep balances and amounts private (ERC-7984)
- **Blind auctions**: Bids hidden until reveal
- **Confidential voting**: Votes private until tally
- **On-chain gaming**: Hidden game state (cards, moves)
- **Encrypted DIDs**: Private identity on-chain
- **Private DeFi**: MEV-resistant swaps, private order books
