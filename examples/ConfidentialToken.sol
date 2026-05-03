// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity";
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ConfidentialToken
 * @notice A confidential ERC-20-style token using FHEVM.
 *         All balances and transfer amounts are encrypted.
 *         Users re-encrypt their balance off-chain to read it.
 *
 * Deploy on Sepolia — inherits SepoliaFHEVMConfig.
 * For local Hardhat testing, remove SepoliaFHEVMConfig inheritance.
 * For mainnet, use ZamaEthereumConfig.
 */
contract ConfidentialToken is SepoliaFHEVMConfig, Ownable {
    // ─── State ────────────────────────────────────────────────────────────────

    string public name;
    string public symbol;
    uint8  public constant decimals = 6;

    mapping(address => euint64) private _balances;
    mapping(address => mapping(address => euint64)) private _allowances;
    uint64 private _totalMinted; // plaintext for bookkeeping only

    // ─── Events ───────────────────────────────────────────────────────────────

    // Amounts are NOT emitted — keeping transfer amounts private
    event Transfer(address indexed from, address indexed to);
    event Approval(address indexed owner, address indexed spender);
    event Mint(address indexed to, uint64 amount); // plaintext for mint events is acceptable

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(string memory _name, string memory _symbol)
        Ownable(msg.sender)
    {
        name = _name;
        symbol = _symbol;
    }

    // ─── Public / External Functions ─────────────────────────────────────────

    /**
     * @notice Mint plaintext amount to address. Only owner.
     *         Amount is public here — use encryptedMint for private minting.
     */
    function mint(address to, uint64 amount) external onlyOwner {
        _ensureInit(to);
        euint64 encAmount = FHE.asEuint64(amount);
        _balances[to] = FHE.add(_balances[to], encAmount);
        FHE.allowThis(_balances[to]);
        FHE.allow(_balances[to], to);
        _totalMinted += amount;
        emit Mint(to, amount);
    }

    /**
     * @notice Transfer an encrypted amount to recipient.
     *         Uses FHE.select to ensure no-op if sender has insufficient balance
     *         (amount is clamped to 0 without revealing which case occurred).
     */
    function transfer(
        address to,
        externalEuint64 encAmount,
        bytes calldata proof
    ) external returns (bool) {
        euint64 amount = FHE.fromExternal(encAmount, proof);
        _transfer(msg.sender, to, amount);
        emit Transfer(msg.sender, to);
        return true;
    }

    /**
     * @notice Approve spender to transfer an encrypted amount.
     */
    function approve(
        address spender,
        externalEuint64 encAmount,
        bytes calldata proof
    ) external returns (bool) {
        euint64 amount = FHE.fromExternal(encAmount, proof);
        _approve(msg.sender, spender, amount);
        emit Approval(msg.sender, spender);
        return true;
    }

    /**
     * @notice Transfer from owner to recipient, spending allowance.
     */
    function transferFrom(
        address from,
        address to,
        externalEuint64 encAmount,
        bytes calldata proof
    ) external returns (bool) {
        euint64 amount = FHE.fromExternal(encAmount, proof);

        // Check and reduce allowance
        euint64 currentAllowance = _allowances[from][msg.sender];
        // Clamp transfer to available allowance
        ebool allowanceOk = FHE.gte(currentAllowance, amount);
        euint64 actualAmount = FHE.select(allowanceOk, amount, FHE.asEuint64(0));
        euint64 newAllowance = FHE.sub(currentAllowance, actualAmount);
        _allowances[from][msg.sender] = newAllowance;
        FHE.allowThis(_allowances[from][msg.sender]);
        FHE.allow(_allowances[from][msg.sender], from);
        FHE.allow(_allowances[from][msg.sender], msg.sender);

        _transfer(from, to, actualAmount);
        emit Transfer(from, to);
        return true;
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    /**
     * @notice Returns the encrypted balance handle for an account.
     *         Caller uses instance.reencrypt() off-chain to read actual value.
     *         Requires FHE.allow(handle, caller) to have been called.
     */
    function balanceOf(address account) external view returns (euint64) {
        return _balances[account];
    }

    /**
     * @notice Returns the encrypted allowance handle.
     */
    function allowance(address owner, address spender) external view returns (euint64) {
        return _allowances[owner][spender];
    }

    /**
     * @notice Total amount minted (plaintext).
     */
    function totalMinted() external view returns (uint64) {
        return _totalMinted;
    }

    // ─── Internal Functions ───────────────────────────────────────────────────

    /**
     * @dev Initialize encrypted balance for a new user.
     *      Must be called before any FHE operation on _balances[user].
     *      bytes32(0) is not a valid FHE handle.
     */
    function _ensureInit(address user) internal {
        if (!FHE.isInitialized(_balances[user])) {  // ✅ correct — works for all types
            _balances[user] = FHE.asEuint64(0);
            FHE.allowThis(_balances[user]);
            FHE.allow(_balances[user], user);
        }
        // ❌ AVOID: euint64.unwrap(_balances[user]) == 0 — fragile, breaks on ebool/eaddress
    }

    /**
     * @dev Internal transfer using FHE.select to handle insufficient balance:
     *      if sender doesn't have enough, actualAmount = 0 (silent no-op).
     *      This prevents leaking whether a transfer succeeded via revert behavior.
     */
    function _transfer(address from, address to, euint64 amount) internal {
        _ensureInit(from);
        _ensureInit(to);

        // Clamp amount to available balance (no-op if insufficient)
        ebool hasEnough = FHE.gte(_balances[from], amount);
        euint64 actualAmount = FHE.select(hasEnough, amount, FHE.asEuint64(0));

        // Update balances
        _balances[from] = FHE.sub(_balances[from], actualAmount);
        _balances[to]   = FHE.add(_balances[to], actualAmount);

        // Re-grant ACL — REQUIRED after every FHE assignment
        FHE.allowThis(_balances[from]);
        FHE.allow(_balances[from], from);
        FHE.allowThis(_balances[to]);
        FHE.allow(_balances[to], to);
    }

    function _approve(address owner, address spender, euint64 amount) internal {
        _allowances[owner][spender] = amount;
        FHE.allowThis(_allowances[owner][spender]);
        FHE.allow(_allowances[owner][spender], owner);
        FHE.allow(_allowances[owner][spender], spender);
    }
}
