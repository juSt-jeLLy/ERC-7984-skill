// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ConfidentialTokenFhevmContracts
 * @notice Demonstrates how to build a confidential token by EXTENDING fhevm-contracts.
 *         This is the recommended approach when you want a full ERC-7984-compatible token.
 *
 * KEY DIFFERENCES from standalone ConfidentialToken.sol:
 *   - Uses "fhevm/lib/TFHE.sol" (NOT @fhevm/solidity)
 *   - Uses "einput" input type (NOT externalEuint64)
 *   - Uses "TFHE.asEuint64(enc, proof)" (NOT FHE.fromExternal)
 *   - Uses TFHE.allowThis / TFHE.allow (same functions, different namespace)
 *   - Config: SepoliaZamaFHEVMConfig from "fhevm/config/ZamaFHEVMConfig.sol"
 *   - totalSupply is plaintext uint64 (NOT encrypted)
 *   - decimals() returns 6 by default (NOT 18)
 *   - Provides dual overloads: (address, einput, bytes) and (address, euint64)
 *
 * Privacy scope:
 *   PRIVATE:  individual balances, transfer amounts, allowances
 *   PUBLIC:   total supply, mint amounts, transfer direction, participant addresses
 *
 * ERC-7984 is a draft standard — NOT ERC-20 compatible.
 */

import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20Mintable } from
    "fhevm-contracts/contracts/token/ERC20/extensions/ConfidentialERC20Mintable.sol";

/**
 * @title MyConfidentialToken
 * @notice A mintable confidential ERC-7984-style token built on fhevm-contracts.
 * @dev    Inherits full transfer, approve, transferFrom, balanceOf, allowance from ConfidentialERC20.
 *         The owner can mint plaintext amounts to any address.
 *         Balances and allowances are encrypted euint64.
 *         decimals() = 6  (1 MTK = 1_000_000 in base units)
 */
contract MyConfidentialToken is SepoliaZamaFHEVMConfig, ConfidentialERC20Mintable {
    constructor(address owner)
        ConfidentialERC20Mintable("MyToken", "MTK", owner)
    {
        // Mint 1,000,000 MTK to owner at deployment
        // Amount is PLAINTEXT — visible on-chain in the Mint event
        // 1 MTK = 1_000_000 in 6-decimal base units
        _unsafeMint(owner, 1_000_000_000_000); // 1,000,000 MTK
        _totalSupply = 1_000_000_000_000;
    }
}

// ─── Usage Examples ────────────────────────────────────────────────────────────
//
// DEPLOY on Sepolia:
//   MyConfidentialToken token = new MyConfidentialToken(ownerAddress);
//
// MINT more tokens (owner only, plaintext amount):
//   token.mint(recipientAddress, 1_000_000); // mints 1 MTK
//
// TRANSFER (encrypted amount, from test or script):
//   import { fhevm } from "hardhat";  // named import — NOT hre.fhevm
//   const encrypted = await fhevm
//     .createEncryptedInput(contractAddr, senderAddr)
//     .add64(1_000_000n)
//     .encrypt();
//   await token["transfer(address,bytes32,bytes)"](recipientAddr, encrypted.handles[0], encrypted.inputProof);
//
// READ BALANCE (returns encrypted handle):
//   const handle = await token.balanceOf(userAddress);
//   const balance = await fhevm.userDecryptEuint(FhevmType.euint64, handle, contractAddr, signer);
//
// APPROVE (encrypted amount):
//   await token["approve(address,bytes32,bytes)"](spenderAddr, handles[0], inputProof);
//
// READ ALLOWANCE (returns encrypted handle):
//   const allowanceHandle = await token.allowance(ownerAddr, spenderAddr);
//
// READ TOTAL SUPPLY (plaintext):
//   const supply = await token.totalSupply(); // returns uint64
//
// ─────────────────────────────────────────────────────────────────────────────


// ─── Extended Token: Add Custom Logic ─────────────────────────────────────────
//
// If you need custom logic on top of ConfidentialERC20Mintable, extend it and
// use TFHE in your overrides (same namespace as the base contract).

import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20Mintable } from
    "fhevm-contracts/contracts/token/ERC20/extensions/ConfidentialERC20Mintable.sol";

/**
 * @title MyTokenWithFee
 * @notice Extends ConfidentialERC20Mintable to collect an encrypted fee on transfers.
 * @dev    Uses TFHE (same namespace as fhevm-contracts) in the override.
 *         Fee is encrypted — nobody can see individual transfer fees.
 */
contract MyTokenWithFee is SepoliaZamaFHEVMConfig, ConfidentialERC20Mintable {
    /// @notice Encrypted accumulated fees (only feeRecipient can read)
    euint64 public feePool;

    /// @notice Address that receives fees
    address public immutable feeRecipient;

    /// @notice Fee in basis points (plaintext — publicly observable)
    uint64 public constant FEE_BPS = 50; // 0.5%

    constructor(address owner, address _feeRecipient)
        ConfidentialERC20Mintable("FeeToken", "FTK", owner)
    {
        feeRecipient = _feeRecipient;
        // Initialize feePool to zero
        feePool = TFHE.asEuint64(0);
        TFHE.allowThis(feePool);
        TFHE.allow(feePool, feeRecipient);
    }

    /**
     * @dev Override _transferNoEvent to collect a fee on each transfer.
     *      IMPORTANT: use TFHE (not FHE) — must match fhevm-contracts namespace.
     */
    function _transferNoEvent(
        address from,
        address to,
        euint64 amount,
        ebool isTransferable
    ) internal virtual override {
        // Calculate fee (plaintext BPS applied to encrypted amount)
        euint64 fee = TFHE.div(TFHE.mul(amount, FEE_BPS), 10_000);
        euint64 netAmount = TFHE.sub(amount, fee);

        // Collect fee into pool
        feePool = TFHE.add(feePool, fee);
        TFHE.allowThis(feePool);
        TFHE.allow(feePool, feeRecipient); // only fee recipient can read pool

        // Execute the transfer with net amount (after fee)
        super._transferNoEvent(from, to, netAmount, isTransferable);
    }
}
