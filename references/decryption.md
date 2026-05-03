# Decryption in FHEVM

FHEVM supports two decryption patterns:
1. **User Decryption (Re-encryption)** — a specific user reads their own private value off-chain
2. **Public Decryption** — an on-chain callback receives a plaintext via the Gateway (visible to all)

---

## 1. User Decryption (Re-encryption)

The user re-encrypts a ciphertext handle under their own public key using an EIP-712 signature. The KMS decrypts the stored value and re-encrypts it with the user's key — so only the user can read the result.

**Requirements:**
- `FHE.allow(handle, userAddress)` must have been called for that user
- The user must sign an EIP-712 message authorizing the re-encryption

### Frontend Implementation

```typescript
import { BrowserProvider, Contract } from "ethers";
import { getInstance } from "./fhevm"; // your instance setup

async function readMyBalance(contractAddress: string, abi: any[]): Promise<bigint> {
  const instance = await getInstance();
  const provider = new BrowserProvider(window.ethereum);
  const signer = await provider.getSigner();
  const userAddress = await signer.getAddress();

  // Step 1: Generate a fresh ephemeral keypair (NEVER reuse across sessions)
  const { publicKey, privateKey } = instance.generateKeypair();

  // Step 2: Create EIP-712 payload bound to THIS contract
  const eip712 = instance.createEIP712(publicKey, contractAddress);

  // Step 3: User signs the payload
  const signature = await signer.signTypedData(
    eip712.domain,
    { Reencrypt: eip712.types.Reencrypt },
    eip712.message
  );

  // Step 4: Fetch the encrypted handle from the contract
  const contract = new Contract(contractAddress, abi, provider);
  const handle = await contract.balanceOf(userAddress);

  // Step 5: Re-encrypt via KMS — returns plaintext visible only to user
  const balance = await instance.reencrypt(
    handle,
    privateKey,
    publicKey,
    signature,
    contractAddress,  // must match EIP-712 domain
    userAddress       // must match the signer
  );

  return balance; // BigInt
}
```

### Solidity Side Requirements

```solidity
mapping(address => euint64) private _balances;

function balanceOf(address user) external view returns (euint64) {
    return _balances[user];  // returns the handle; user re-encrypts off-chain
}

// After any assignment — BOTH must be called:
function _creditBalance(address user, euint64 amount) internal {
    _balances[user] = FHE.add(_balances[user], amount);
    FHE.allowThis(_balances[user]);    // contract can use it next tx
    FHE.allow(_balances[user], user);  // ← user can re-encrypt it
}
```

### Hardhat Testing: User Decrypt

```typescript
import { ethers, fhevm } from "hardhat";  // named import — NOT `import hre from "hardhat"`
import { FhevmType } from "@fhevm/hardhat-plugin";

const balanceHandle = await contract.balanceOf(owner.address);
const contractAddr = await contract.getAddress();

const balance = await fhevm.userDecryptEuint(
    FhevmType.euint64,   // type of the encrypted value
    balanceHandle,       // the handle from the contract
    contractAddr,        // contract address
    owner                // the signer (must match who was granted FHE.allow)
);

console.log("Balance:", balance); // BigInt
expect(balance).to.equal(1000n);
```

---

## 2. Public Decryption (Gateway Callback)

Public decryption makes a plaintext visible on-chain to everyone. Used for:
- Revealing auction winners
- Publishing vote tallies
- Revealing game results

This is a **two-transaction flow**: one tx marks the handle as publicly decryptable and requests gateway decryption; a second tx (delivered by the Gateway) calls back with the plaintext.

### Current API: `FHE.makePubliclyDecryptable`

**Important**: The current pattern requires calling `FHE.makePubliclyDecryptable(handle)` before requesting decryption. This explicitly authorizes the Gateway to decrypt the handle. Skipping this step causes the gateway to reject the request.

```solidity
import { FHE, euint64, Gateway } from "@fhevm/solidity";
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";

contract ConfidentialAuction is SepoliaFHEVMConfig {
    euint64 private _highestBid;
    uint64  public  revealedWinningBid;
    bool    public  isRevealed;
    uint256 private _pendingRequestId;

    // Step 1: Mark handle as publicly decryptable, then request decryption
    function revealResult() external {
        require(block.timestamp > auctionEndTime, "Auction still running");
        require(!isRevealed, "Already revealed");
        require(_pendingRequestId == 0, "Decryption already requested");

        // REQUIRED: explicitly authorize public decryption of this handle
        FHE.makePubliclyDecryptable(_highestBid);

        uint256[] memory handles = new uint256[](1);
        handles[0] = uint256(euint64.unwrap(_highestBid));

        // Submit decryption request — gateway will call onDecrypt
        _pendingRequestId = Gateway.requestDecryption(
            handles,
            this.onDecrypt.selector,
            0,
            block.timestamp + 100,
            false
        );
    }

    // Step 2: Gateway calls this with the plaintext (separate transaction)
    function onDecrypt(
        uint256 requestId,
        uint64 plaintext,
        bytes[] memory signatures
    ) public returns (bool) {
        require(msg.sender == address(Gateway.gatewayContractAddress()), "Only gateway");
        require(requestId == _pendingRequestId, "Unknown request");

        // Verify KMS signatures — ALWAYS required, never skip
        FHE.checkSignatures(requestId, abi.encode(plaintext), abi.encode(signatures));

        revealedWinningBid = plaintext;
        isRevealed = true;
        _pendingRequestId = 0;

        emit ResultRevealed(plaintext);
        return true;
    }
}
```

### Decoding Multiple Values

```solidity
// Request decryption of 2 handles:
uint256[] memory handles = new uint256[](2);
handles[0] = uint256(euint64.unwrap(_highBid));
handles[1] = uint256(euint64.unwrap(_lowBid));

// Make both publicly decryptable first:
FHE.makePubliclyDecryptable(_highBid);
FHE.makePubliclyDecryptable(_lowBid);

// Callback decodes tuple:
function onDecrypt(uint256 reqId, uint64 highBid, uint64 lowBid, bytes[] memory sigs) public returns (bool) {
    FHE.checkSignatures(reqId, abi.encode(highBid, lowBid), abi.encode(sigs));
    // ... use values
    return true;
}

// For bool:
function onReveal(uint256 reqId, bool result, bytes[] memory sigs) public returns (bool) {
    FHE.checkSignatures(reqId, abi.encode(result), abi.encode(sigs));
    return true;
}
```


### Testing Public Decryption (Hardhat)

In local Hardhat tests, the Gateway callback happens synchronously (no waiting):

```typescript
// Request decryption
const tx = await contract.revealResult();
await tx.wait();

// In hardhat mock mode: callback fires synchronously in next block
// For Sepolia: poll until isRevealed == true (may take 30-60 seconds)

// Check result
const revealed = await contract.revealedWinningBid();
console.log("Winning bid:", revealed);
```

For Sepolia testing, poll for the result:

```typescript
async function waitForDecryption(contract, timeoutMs = 120_000) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const isRevealed = await contract.isRevealed();
        if (isRevealed) return await contract.revealedWinningBid();
        await new Promise(r => setTimeout(r, 5000)); // poll every 5s
    }
    throw new Error("Decryption timed out");
}
```

---

## Preventing Duplicate Decryption Requests

```solidity
mapping(uint256 => bool) private _pendingDecryption;
bool private _decryptionRequested;

function requestReveal() external {
    require(!_decryptionRequested, "Already requested");
    _decryptionRequested = true;

    bytes32[] memory handles = new bytes32[](1);
    handles[0] = euint64.unwrap(_secret);
    uint256 reqId = FHE.requestDecryption(handles, this.onReveal.selector);
    _pendingDecryption[reqId] = true;
}
```

---

## Common Decryption Errors

| Error | Cause | Fix |
|---|---|---|
| `Re-encryption returns 0` | `FHE.allow(handle, user)` not called | Add `FHE.allow` when granting access |
| `Re-encryption signature invalid` | Reused keypair or wrong contract in EIP-712 | Generate fresh keypair; verify contract address |
| `Callback never triggered` | Wrong callback selector or ACL issue | Verify callback signature exactly; ensure `allowThis` |
| `InvalidKMSSignatures` | Tampered callback or network mismatch | Check network; always call `FHE.checkSignatures()` |
| `HandlesAlreadySavedForRequestID` | Duplicate `requestDecryption` call | Use a `_decryptionRequested` guard flag |

See [`error-reference.md`](error-reference.md) for full details.
