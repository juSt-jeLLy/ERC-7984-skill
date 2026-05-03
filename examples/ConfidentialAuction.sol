// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity";
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";

/**
 * @title ConfidentialAuction
 * @notice A blind auction where bids are encrypted.
 *         - No bidder can see competitors' bids
 *         - The contract tracks the highest bid using FHE comparisons
 *         - Winner and amount are revealed via public decryption after auction ends
 *         - Losing bidders can claim refunds after reveal
 *
 * Pattern: encrypted running maximum
 */
contract ConfidentialAuction is SepoliaFHEVMConfig {
    // ─── State ────────────────────────────────────────────────────────────────

    address public immutable seller;
    uint256 public immutable auctionEndTime;
    string  public itemDescription;

    // Encrypted highest bid and bidder
    euint64  private _highestBid;
    eaddress private _highestBidder;  // encrypted so competitors can't see who's winning

    // Track bids for refunds (plaintext amount stored for refund purposes)
    mapping(address => uint256) public depositedEth; // ETH deposited alongside bid
    mapping(address => bool)    public hasBid;

    // Decryption state
    bool    public isFinalized;
    bool    private _decryptionPending;
    uint256 private _decryptionRequestId;

    // Revealed results
    uint64  public revealedHighestBid;
    address public winner;
    bool    public resultsRevealed;

    // ─── Events ───────────────────────────────────────────────────────────────

    event BidPlaced(address indexed bidder);  // amount NOT revealed
    event AuctionEnded();
    event ResultsRevealed(address indexed winner, uint64 highestBid);

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(string memory _item, uint256 _duration) {
        seller = msg.sender;
        itemDescription = _item;
        auctionEndTime = block.timestamp + _duration;

        // Initialize encrypted state — REQUIRED (bytes32(0) is invalid handle)
        _highestBid = FHE.asEuint64(0);
        FHE.allowThis(_highestBid);

        _highestBidder = FHE.asEaddress(address(0));
        FHE.allowThis(_highestBidder);
    }

    // ─── Bidding ──────────────────────────────────────────────────────────────

    /**
     * @notice Place a confidential bid.
     * @param encBid  Encrypted bid amount (must exceed current highest to win)
     * @param proof   ZK proof for this (contract, sender) pair
     *
     * The new highest is computed using FHE.select:
     *   newHighest = FHE.select(newBid > currentHighest, newBid, currentHighest)
     * No information about whether the bid was the new highest is leaked.
     *
     * ETH deposit: Bidders send ETH to prove intent. Losers get it back after reveal.
     */
    function bid(externalEuint64 encBid, bytes calldata proof) external payable {
        require(block.timestamp < auctionEndTime, "Auction ended");
        require(!hasBid[msg.sender], "Already bid (use increaseBid)");
        require(msg.value > 0, "Must deposit ETH");

        hasBid[msg.sender] = true;
        depositedEth[msg.sender] = msg.value;

        // Verify + convert encrypted bid
        euint64 newBid = FHE.fromExternal(encBid, proof);

        // Encrypted comparison: is new bid higher?
        ebool isHigher = FHE.gt(newBid, _highestBid);

        // Update highest bid and bidder — both using FHE.select to avoid info leak
        _highestBid    = FHE.select(isHigher, newBid, _highestBid);
        _highestBidder = FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder);

        // Re-grant ACL — REQUIRED after every FHE assignment
        FHE.allowThis(_highestBid);
        FHE.allowThis(_highestBidder);

        emit BidPlaced(msg.sender);
    }

    // ─── Finalization ─────────────────────────────────────────────────────────

    /**
     * @notice Request public decryption of winner and winning bid.
     *         Can only be called after auction ends.
     */
    function finalizeAuction() external {
        require(block.timestamp >= auctionEndTime, "Auction not ended");
        require(!isFinalized, "Already finalized");
        require(!_decryptionPending, "Decryption pending");

        isFinalized = true;
        _decryptionPending = true;

        // Request decryption of both highest bid and bidder
        bytes32[] memory handles = new bytes32[](2);
        handles[0] = euint64.unwrap(_highestBid);
        handles[1] = eaddress.unwrap(_highestBidder);

        uint256 reqId = FHE.requestDecryption(handles, this.onDecrypt.selector);
        _decryptionRequestId = reqId;

        emit AuctionEnded();
    }

    /**
     * @notice Gateway callback — receives decrypted winner and bid.
     */
    function onDecrypt(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory signatures
    ) public returns (bool) {
        require(msg.sender == address(FHE.getDecryptionOracle()), "Only oracle");
        require(requestId == _decryptionRequestId, "Wrong requestId");

        FHE.checkSignatures(requestId, cleartexts, signatures);

        // Decode: first handle was euint64 (bid), second was eaddress
        (uint64 highBid, address winnerAddr) = abi.decode(cleartexts, (uint64, address));

        revealedHighestBid = highBid;
        winner = winnerAddr;
        resultsRevealed = true;
        _decryptionPending = false;

        emit ResultsRevealed(winnerAddr, highBid);
        return true;
    }

    // ─── Refunds ──────────────────────────────────────────────────────────────

    /**
     * @notice Non-winners claim their ETH deposit back.
     *         Can only be called after results are revealed.
     */
    function claimRefund() external {
        require(resultsRevealed, "Results not yet revealed");
        require(msg.sender != winner, "Winner cannot refund");
        require(depositedEth[msg.sender] > 0, "Nothing to refund");

        uint256 amount = depositedEth[msg.sender];
        depositedEth[msg.sender] = 0;

        (bool ok, ) = msg.sender.call{ value: amount }("");
        require(ok, "Refund failed");
    }

    /**
     * @notice Seller collects the winning bid amount.
     */
    function sellerWithdraw() external {
        require(msg.sender == seller, "Only seller");
        require(resultsRevealed, "Results not revealed");
        require(winner != address(0), "No bids");

        uint256 amount = depositedEth[winner];
        depositedEth[winner] = 0;

        (bool ok, ) = seller.call{ value: amount }("");
        require(ok, "Withdraw failed");
    }

    // ─── Views ────────────────────────────────────────────────────────────────

    function isActive() external view returns (bool) {
        return block.timestamp < auctionEndTime && !isFinalized;
    }

    function timeRemaining() external view returns (uint256) {
        if (block.timestamp >= auctionEndTime) return 0;
        return auctionEndTime - block.timestamp;
    }
}
