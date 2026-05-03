/**
 * FHEVM Test Suite Example
 *
 * Tests a ConfidentialToken (confidential ERC-20-style token).
 *
 * Key API pattern (verified against official fhevm-hardhat-template):
 *   - Import `fhevm` as a named export from "hardhat" (NOT `hre.fhevm`)
 *   - `fhevm.isMock` to detect local vs Sepolia
 *   - `fhevm.createEncryptedInput(addr, userAddr).add64(val).encrypt()` — fluent chain
 *   - `fhevm.userDecryptEuint(FhevmType.euint64, handle, contractAddr, signer)`
 *
 * Requirements:
 *   - @fhevm/hardhat-plugin MUST be first import in hardhat.config.ts
 *   - @fhevm/mock-utils must be installed (peer dep of hardhat-plugin)
 *   - chai@^4 (not v5 — breaking changes)
 *   - evmVersion: "cancun" in hardhat.config.ts
 *
 * Run locally: npx hardhat test
 * Run on Sepolia: npx hardhat test --network sepolia
 */

import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm } from "hardhat";  // ← named import — NOT `import hre from "hardhat"`
import { FhevmType } from "@fhevm/hardhat-plugin";
import { expect } from "chai";
import type { ConfidentialToken } from "../types"; // TypeChain generated

// ─────────────────────────────────────────────────────────────────────────────
// Local mock tests — ConfidentialToken
// ─────────────────────────────────────────────────────────────────────────────

describe("ConfidentialToken (local mock)", function () {
  let signers: {
    deployer: HardhatEthersSigner;
    alice: HardhatEthersSigner;
    bob: HardhatEthersSigner;
  };
  let token: ConfidentialToken;
  let tokenAddr: string;

  // ── Setup ────────────────────────────────────────────────────────────────

  before(async function () {
    const ethSigners = await ethers.getSigners();
    signers = {
      deployer: ethSigners[0],
      alice: ethSigners[1],
      bob: ethSigners[2],
    };
  });

  beforeEach(async function () {
    // Skip this suite when running against Sepolia — it relies on instant mock FHE
    if (!fhevm.isMock) {
      console.warn("ConfidentialToken local suite skipped on non-mock network");
      this.skip();
    }

    const factory = await ethers.getContractFactory("ConfidentialToken");
    token = (await factory.deploy("PrivateToken", "PTK")) as ConfidentialToken;
    await token.waitForDeployment();
    tokenAddr = await token.getAddress();
  });

  // ── Helpers ──────────────────────────────────────────────────────────────

  /**
   * Encrypt a uint64 value for a given signer and return handles + inputProof.
   * Uses the fluent chain: createEncryptedInput(...).add64(val).encrypt()
   */
  async function encryptUint64(signer: HardhatEthersSigner, value: bigint) {
    return fhevm
      .createEncryptedInput(tokenAddr, signer.address)
      .add64(value)
      .encrypt();
    // Returns: { handles: Uint8Array[], inputProof: Uint8Array }
  }

  /**
   * Decrypt the encrypted balance for `account`.
   * The signer MUST match the account whose balance we're reading
   * (they must have received FHE.allow(balanceHandle, account.address)).
   */
  async function readBalance(account: HardhatEthersSigner): Promise<bigint> {
    const handle = await token.balanceOf(account.address);
    return fhevm.userDecryptEuint(
      FhevmType.euint64,
      handle,
      tokenAddr,
      account, // MUST be the account that has FHE.allow — never another signer
    );
  }

  // ── Tests ────────────────────────────────────────────────────────────────

  it("should have correct metadata", async function () {
    expect(await token.name()).to.equal("PrivateToken");
    expect(await token.symbol()).to.equal("PTK");
  });

  it("should mint tokens to deployer", async function () {
    await (await token.connect(signers.deployer).mint(signers.deployer.address, 10_000n)).wait();
    const balance = await readBalance(signers.deployer);
    expect(balance).to.equal(10_000n);
  });

  it("should mint tokens to alice", async function () {
    await (await token.connect(signers.deployer).mint(signers.alice.address, 5_000n)).wait();
    const balance = await readBalance(signers.alice);
    expect(balance).to.equal(5_000n);
  });

  it("should reject mint from non-owner", async function () {
    await expect(
      token.connect(signers.alice).mint(signers.alice.address, 100n),
    ).to.be.reverted;
  });

  it("should transfer encrypted amount from deployer to bob", async function () {
    await (await token.connect(signers.deployer).mint(signers.deployer.address, 10_000n)).wait();

    // Encrypt 1000 as a euint64 for the deployer
    const encrypted = await encryptUint64(signers.deployer, 1_000n);
    await (
      await token
        .connect(signers.deployer)
        .transfer(signers.bob.address, encrypted.handles[0], encrypted.inputProof)
    ).wait();

    const deployerBal = await readBalance(signers.deployer);
    expect(deployerBal).to.equal(9_000n);

    const bobBal = await readBalance(signers.bob);
    expect(bobBal).to.equal(1_000n);
  });

  it("should silently clamp transfer when balance is insufficient (FHE.select behavior)", async function () {
    await (await token.connect(signers.deployer).mint(signers.alice.address, 500n)).wait();

    // Alice tries to send 9_999 — more than she has
    const encrypted = await encryptUint64(signers.alice, 9_999n);
    await (
      await token
        .connect(signers.alice)
        .transfer(signers.bob.address, encrypted.handles[0], encrypted.inputProof)
    ).wait();

    // FHE.select(canTransfer, amount, 0) — transfer is a no-op, balances unchanged
    const aliceBal = await readBalance(signers.alice);
    expect(aliceBal).to.equal(500n); // unchanged

    const bobBal = await readBalance(signers.bob);
    expect(bobBal).to.equal(0n); // nothing received
  });

  it("should encrypt multiple values in one input batch", async function () {
    // Two values in one encrypted batch — handles[0] and handles[1]
    const batch = await fhevm
      .createEncryptedInput(tokenAddr, signers.deployer.address)
      .add64(1_000n) // handles[0]
      .add64(2_000n) // handles[1]
      .encrypt();

    expect(batch.handles).to.have.lengthOf(2);
    // Use batch.handles[0] and batch.handles[1] in separate contract calls
    // The same inputProof covers both
  });

  it("should allow approved spender to transferFrom", async function () {
    await (await token.connect(signers.deployer).mint(signers.deployer.address, 10_000n)).wait();

    // Deployer approves alice to spend 2_000
    const approveEnc = await encryptUint64(signers.deployer, 2_000n);
    await (
      await token
        .connect(signers.deployer)
        .approve(signers.alice.address, approveEnc.handles[0], approveEnc.inputProof)
    ).wait();

    // Alice transfers 1_000 from deployer to bob using allowance
    const transferEnc = await encryptUint64(signers.alice, 1_000n);
    await (
      await token
        .connect(signers.alice)
        .transferFrom(
          signers.deployer.address,
          signers.bob.address,
          transferEnc.handles[0],
          transferEnc.inputProof,
        )
    ).wait();

    const deployerBal = await readBalance(signers.deployer);
    expect(deployerBal).to.equal(9_000n);

    const bobBal = await readBalance(signers.bob);
    expect(bobBal).to.equal(1_000n);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Sepolia tests — runs only on real network
// ─────────────────────────────────────────────────────────────────────────────

describe("ConfidentialToken (Sepolia)", function () {
  let signers: { alice: HardhatEthersSigner };
  let token: ConfidentialToken;
  let tokenAddr: string;
  let step = 0;
  const steps = 6;
  const log = (msg: string) => console.log(`${++step}/${steps} ${msg}`);

  before(async function () {
    if (fhevm.isMock) {
      console.warn("ConfidentialToken Sepolia suite skipped — not on testnet");
      this.skip();
    }

    // Requires: npx hardhat deploy --network sepolia
    const { deployments } = await import("hardhat");
    const deployment = await deployments.get("ConfidentialToken").catch(() => {
      throw new Error("Deploy first: npx hardhat deploy --network sepolia");
    });
    tokenAddr = deployment.address;
    token = await ethers.getContractAt("ConfidentialToken", tokenAddr);
    const ethSigners = await ethers.getSigners();
    signers = { alice: ethSigners[0] };
  });

  it("should increment and decrypt on Sepolia", async function () {
    this.timeout(4 * 40_000); // 160s — KMS decryption can take 30-60s

    log("Encrypting value...");
    const encrypted = await fhevm
      .createEncryptedInput(tokenAddr, signers.alice.address)
      .add64(0n)
      .encrypt();

    log("Sending mint tx...");
    const tx = await token.connect(signers.alice).mint(signers.alice.address, 100n);
    await tx.wait();
    log(`Tx confirmed: ${tx.hash}`);

    log("Reading handle...");
    const handle = await token.balanceOf(signers.alice.address);
    expect(handle).to.not.equal(ethers.ZeroHash);

    log("Decrypting via KMS...");
    const balance = await fhevm.userDecryptEuint(
      FhevmType.euint64,
      handle,
      tokenAddr,
      signers.alice,
    );
    log(`Decrypted balance: ${balance}`);

    expect(balance).to.be.gte(100n);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Voting contract tests
// ─────────────────────────────────────────────────────────────────────────────

describe("ConfidentialVoting", function () {
  let voting: any;
  let votingAddr: string;
  let signers: {
    owner: HardhatEthersSigner;
    voter1: HardhatEthersSigner;
    voter2: HardhatEthersSigner;
    voter3: HardhatEthersSigner;
  };

  before(async function () {
    const ethSigners = await ethers.getSigners();
    signers = {
      owner: ethSigners[0],
      voter1: ethSigners[1],
      voter2: ethSigners[2],
      voter3: ethSigners[3],
    };
  });

  beforeEach(async function () {
    if (!fhevm.isMock) { this.skip(); }

    const factory = await ethers.getContractFactory("ConfidentialVoting");
    voting = await factory.deploy("Upgrade proposal", 3600 /* 1 hour */);
    await voting.waitForDeployment();
    votingAddr = await voting.getAddress();
  });

  it("should accept encrypted votes from multiple voters", async function () {
    // Vote for Option A (0) and Option B (1)
    for (const [voter, choice] of [
      [signers.voter1, 0],
      [signers.voter2, 1],
      [signers.voter3, 1],
    ] as const) {
      const enc = await fhevm
        .createEncryptedInput(votingAddr, voter.address)
        .add32(choice)
        .encrypt();
      await (await voting.connect(voter).castVote(enc.handles[0], enc.inputProof)).wait();
    }

    expect(await voting.hasVoted(signers.voter1.address)).to.be.true;
    expect(await voting.hasVoted(signers.voter2.address)).to.be.true;
    expect(await voting.hasVoted(signers.voter3.address)).to.be.true;
  });

  it("should prevent double voting", async function () {
    const enc = await fhevm
      .createEncryptedInput(votingAddr, signers.voter1.address)
      .add32(0)
      .encrypt();
    await (await voting.connect(signers.voter1).castVote(enc.handles[0], enc.inputProof)).wait();

    const enc2 = await fhevm
      .createEncryptedInput(votingAddr, signers.voter1.address)
      .add32(1)
      .encrypt();
    await expect(
      voting.connect(signers.voter1).castVote(enc2.handles[0], enc2.inputProof),
    ).to.be.revertedWith("Already voted");
  });

  it("should reveal correct results via public decryption", async function () {
    // Cast votes: voter1 → A, voter2 → B, voter3 → B
    for (const [voter, choice] of [
      [signers.voter1, 0],
      [signers.voter2, 1],
      [signers.voter3, 1],
    ] as const) {
      const enc = await fhevm
        .createEncryptedInput(votingAddr, voter.address)
        .add32(choice)
        .encrypt();
      await (await voting.connect(voter).castVote(enc.handles[0], enc.inputProof)).wait();
    }

    // Advance past end time
    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    // Request public decryption
    await (await voting.requestResults()).wait();

    // In mock mode: Gateway callback is synchronous (fires in same block or immediately after)
    await new Promise(r => setTimeout(r, 200));

    expect(await voting.revealedVotesA()).to.equal(1n);
    expect(await voting.revealedVotesB()).to.equal(2n);
    expect(await voting.getWinner()).to.equal(1); // B wins
  });
});
