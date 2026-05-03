// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint64, externalEuint64 } from "@fhevm/solidity";

// ── Network config ────────────────────────────────────────────────────────────
//
// For LOCAL Hardhat (default): No inheritance — @fhevm/hardhat-plugin configures automatically.
//
// For SEPOLIA testnet:
//   Option A (main branch / upcoming @fhevm/solidity):
//     import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
//     contract ConfidentialCounter is SepoliaFHEVMConfig { ... }
//
//   Option B (current npm v0.11.1, as used in official fhevm-hardhat-template):
//     import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
//     contract ConfidentialCounter is ZamaEthereumConfig { ... }
//     (verify: ls node_modules/@fhevm/solidity/config/ to see available classes)
//
// For ETHEREUM MAINNET:
//   import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol"; // v0.11.1
//   import { EthereumFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol"; // upcoming
//
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @title ConfidentialCounter
 * @notice Simplest possible FHEVM contract — a private per-user counter.
 *
 * This is the recommended starting point for learning FHEVM.
 * It demonstrates all four core patterns:
 *   1. Network config inheritance (comment/uncomment for local vs. testnet/mainnet)
 *   2. FHE.isInitialized() — correct way to check for uninitialized encrypted slots
 *   3. FHE.fromExternal — verifying ZK proofs on encrypted inputs
 *   4. FHE.allowThis + FHE.allow — the two required ACL calls after every assignment
 *
 * Based on the official Zama FHECounter example:
 *   https://github.com/zama-ai/fhevm-hardhat-template/blob/main/contracts/FHECounter.sol
 */
contract ConfidentialCounter {
    /// @notice Encrypted counter per user.
    /// @dev Handle is public (bytes32); value is private.
    ///      bytes32(0) means uninitialized — always check FHE.isInitialized() before use.
    mapping(address => euint64) private _counters;

    /// @notice Emitted when a user increments their counter.
    ///         The encrypted amount is NOT emitted — that would reveal the private value.
    event CounterIncremented(address indexed user);

    /// @notice Emitted when a user resets their counter.
    event CounterReset(address indexed user);

    // ─── External Functions ─────────────────────────────────────────────────

    /**
     * @notice Increment your counter by an encrypted amount.
     * @param encAmount Encrypted increment value (produced off-chain via @zama-fhe/relayer-sdk)
     * @param proof     ZK proof binding encAmount to this contract + msg.sender
     *
     * @dev Example omits overflow checks for clarity. In production, use range proofs
     *      or FHE.min() to guard against overflow.
     */
    function increment(externalEuint64 encAmount, bytes calldata proof) external {
        // Step 1: Verify the ZK proof and convert to an on-chain encrypted value.
        //         NEVER use encAmount directly in FHE operations without this call.
        euint64 amount = FHE.fromExternal(encAmount, proof);

        // Step 2: Initialize if first use. FHE.isInitialized() checks handle != bytes32(0).
        if (!FHE.isInitialized(_counters[msg.sender])) {
            _counters[msg.sender] = FHE.asEuint64(0);
            FHE.allowThis(_counters[msg.sender]);
            FHE.allow(_counters[msg.sender], msg.sender);
        }

        // Step 3: Compute new value. FHE.add returns a NEW handle — the old ACL entry is stale.
        _counters[msg.sender] = FHE.add(_counters[msg.sender], amount);

        // Step 4: Grant ACL permissions on the NEW handle.
        //         Without allowThis: the contract cannot use the handle in future FHE ops.
        //         Without allow(user): the user cannot re-encrypt (read) the value off-chain.
        FHE.allowThis(_counters[msg.sender]);
        FHE.allow(_counters[msg.sender], msg.sender);

        emit CounterIncremented(msg.sender);
    }

    /**
     * @notice Decrement your counter by an encrypted amount.
     * @dev No underflow protection — add FHE.min() or a conditional check in production.
     */
    function decrement(externalEuint64 encAmount, bytes calldata proof) external {
        euint64 amount = FHE.fromExternal(encAmount, proof);

        if (!FHE.isInitialized(_counters[msg.sender])) {
            _counters[msg.sender] = FHE.asEuint64(0);
            FHE.allowThis(_counters[msg.sender]);
            FHE.allow(_counters[msg.sender], msg.sender);
        }

        _counters[msg.sender] = FHE.sub(_counters[msg.sender], amount);
        FHE.allowThis(_counters[msg.sender]);
        FHE.allow(_counters[msg.sender], msg.sender);

        emit CounterIncremented(msg.sender);
    }

    /**
     * @notice Reset your counter to zero.
     */
    function reset() external {
        _counters[msg.sender] = FHE.asEuint64(0);
        FHE.allowThis(_counters[msg.sender]);
        FHE.allow(_counters[msg.sender], msg.sender);
        emit CounterReset(msg.sender);
    }

    /**
     * @notice Allow another address to read your counter (e.g., a trusted auditor).
     */
    function grantReadAccess(address reader) external {
        require(FHE.isInitialized(_counters[msg.sender]), "Counter not initialized");
        FHE.allow(_counters[msg.sender], reader);
    }

    // ─── View Functions ─────────────────────────────────────────────────────

    /**
     * @notice Get the encrypted counter handle for a user.
     * @dev Returns a ciphertext handle (bytes32 under the hood), NOT a plaintext value.
     *      The caller must hold ACL permission and re-encrypt off-chain to see the value.
     *      In tests: fhevm.userDecryptEuint(FhevmType.euint64, handle, contractAddr, signer)
     */
    function getCounter(address user) external view returns (euint64) {
        return _counters[user];
    }

    /**
     * @notice Returns whether a user's counter has been initialized.
     */
    function isInitialized(address user) external view returns (bool) {
        return FHE.isInitialized(_counters[user]);
    }
}
