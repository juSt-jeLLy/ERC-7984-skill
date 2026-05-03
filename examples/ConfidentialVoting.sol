// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint64, euint32, ebool, externalEbool, externalEuint32 } from "@fhevm/solidity";
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ConfidentialVoting
 * @notice A confidential voting contract where:
 *         - Each voter's vote is encrypted (nobody can see who voted for what)
 *         - Vote tallies accumulate as encrypted values
 *         - Results are revealed via public decryption after voting ends
 *         - Bribery-resistant: can't prove how you voted while voting is open
 *
 * Voting options: 0 = Option A, 1 = Option B (using weighted votes for flexibility)
 */
contract ConfidentialVoting is SepoliaFHEVMConfig, Ownable {
    // ─── State ────────────────────────────────────────────────────────────────

    string public question;
    uint256 public votingEnd;
    bool    public isFinalized;

    // Encrypted vote tallies
    euint64 private _votesForA;
    euint64 private _votesForB;

    // Track who has voted (plaintext — just prevents double-voting, not secret)
    mapping(address => bool) public hasVoted;

    // Decryption results
    uint64  public revealedVotesA;
    uint64  public revealedVotesB;

    // Decryption request tracking
    uint256 private _decryptionRequestId;
    bool    private _decryptionPending;

    // ─── Events ───────────────────────────────────────────────────────────────

    event VoteCast(address indexed voter);  // no vote direction revealed
    event VotingEnded();
    event ResultsRevealed(uint64 votesA, uint64 votesB);
    event DecryptionRequested(uint256 requestId);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param _question The voting question
     * @param _duration Voting duration in seconds
     */
    constructor(string memory _question, uint256 _duration)
        Ownable(msg.sender)
    {
        question = _question;
        votingEnd = block.timestamp + _duration;

        // Initialize encrypted tallies — REQUIRED before any FHE operation
        _votesForA = FHE.asEuint64(0);
        FHE.allowThis(_votesForA);

        _votesForB = FHE.asEuint64(0);
        FHE.allowThis(_votesForB);
    }

    // ─── Voting ───────────────────────────────────────────────────────────────

    /**
     * @notice Cast a vote.
     * @param encVote Encrypted vote: 0 = Option A, any nonzero = Option B
     *                Encrypted so neither validators nor other users can see your choice.
     * @param proof   ZK proof that encVote is well-formed for this contract + sender.
     *
     * The vote is counted using FHE.select:
     *   - If voteIsB is true: add weight to B, add 0 to A
     *   - If voteIsB is false: add weight to A, add 0 to B
     * Neither the contract nor observers can determine which branch was taken.
     */
    function castVote(
        externalEuint32 encVote,
        bytes calldata proof
    ) external {
        require(block.timestamp < votingEnd, "Voting ended");
        require(!hasVoted[msg.sender], "Already voted");
        require(!isFinalized, "Election finalized");

        hasVoted[msg.sender] = true;

        // Verify + convert encrypted vote
        euint32 vote = FHE.fromExternal(encVote, proof);

        // Determine if vote is for B (nonzero)
        ebool voteIsB = FHE.gt(vote, FHE.asEuint32(0));

        // Weight = 1 vote per person (use euint64 for accumulation headroom)
        euint64 one = FHE.asEuint64(1);
        euint64 zero = FHE.asEuint64(0);

        // Conditionally add to tallies — NEVER reveal which branch
        euint64 addToB = FHE.select(voteIsB, one, zero);
        euint64 addToA = FHE.select(voteIsB, zero, one);

        _votesForA = FHE.add(_votesForA, addToA);
        _votesForB = FHE.add(_votesForB, addToB);

        // Re-grant ACL — REQUIRED after every FHE assignment
        FHE.allowThis(_votesForA);
        FHE.allowThis(_votesForB);

        emit VoteCast(msg.sender);
    }

    // ─── Reveal ───────────────────────────────────────────────────────────────

    /**
     * @notice Request public decryption of vote tallies.
     *         Can only be called after voting ends.
     *         Results arrive asynchronously via onDecryptResult() callback.
     */
    function requestResults() external {
        require(block.timestamp >= votingEnd, "Voting not ended");
        require(!_decryptionPending, "Decryption already pending");
        require(!isFinalized, "Already finalized");

        _decryptionPending = true;
        isFinalized = true;

        // Build handles array for decryption
        bytes32[] memory handles = new bytes32[](2);
        handles[0] = euint64.unwrap(_votesForA);
        handles[1] = euint64.unwrap(_votesForB);

        // Submit decryption request to Gateway
        uint256 reqId = FHE.requestDecryption(handles, this.onDecryptResult.selector);
        _decryptionRequestId = reqId;

        emit VotingEnded();
        emit DecryptionRequested(reqId);
    }

    /**
     * @notice Callback invoked by the Gateway with decrypted results.
     *         Parameter types must match EXACTLY — do not change signatures.
     */
    function onDecryptResult(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory signatures
    ) public returns (bool) {
        // Verify caller is the authorized Gateway oracle
        require(msg.sender == address(FHE.getDecryptionOracle()), "Only oracle");
        require(requestId == _decryptionRequestId, "Wrong requestId");

        // Verify KMS signatures — always required
        FHE.checkSignatures(requestId, cleartexts, signatures);

        // Decode both vote tallies (order matches handles[] order in requestResults)
        (uint64 votesA, uint64 votesB) = abi.decode(cleartexts, (uint64, uint64));

        revealedVotesA = votesA;
        revealedVotesB = votesB;
        _decryptionPending = false;

        emit ResultsRevealed(votesA, votesB);
        return true;
    }

    // ─── Views ────────────────────────────────────────────────────────────────

    /**
     * @notice Check if voting is still open.
     */
    function isVotingOpen() external view returns (bool) {
        return block.timestamp < votingEnd && !isFinalized;
    }

    /**
     * @notice Time remaining in voting period (0 if ended).
     */
    function timeRemaining() external view returns (uint256) {
        if (block.timestamp >= votingEnd) return 0;
        return votingEnd - block.timestamp;
    }

    /**
     * @notice Get the winner after results are revealed.
     *         Returns 0 for Option A, 1 for Option B, 2 for tie.
     */
    function getWinner() external view returns (uint8) {
        require(isFinalized && !_decryptionPending, "Results not revealed");
        if (revealedVotesA > revealedVotesB) return 0;
        if (revealedVotesB > revealedVotesA) return 1;
        return 2; // tie
    }
}
