/**
 * FHEVM Frontend Integration Example
 * Using fhevmjs with React + ethers.js
 *
 * Works with both:
 * - fhevmjs (Hardhat template)
 * - @zama-fhe/sdk + @zama-fhe/react-sdk (React template)
 *
 * Install: npm install fhevmjs ethers
 */

import React, { useState, useEffect, createContext, useContext } from "react";
import { BrowserProvider, Contract, JsonRpcSigner } from "ethers";
import { createInstance, type FhevmInstance } from "fhevmjs/web";

// ── Sepolia network contract addresses ──────────────────────────────────────
const SEPOLIA_CONFIG = {
  networkUrl: "https://eth-sepolia.public.blastapi.io",
  gatewayUrl: "https://gateway.sepolia.zama.ai",
  kmsContractAddress: "0x9D6891A6240D6130c54ae243d8005063D05fE14b",
  aclContractAddress: "0xFee8407e2f5e3Ee68ad77cAE98c434e637f516e5",
};

// ── FHEVM Instance (singleton) ───────────────────────────────────────────────

let _instance: FhevmInstance | null = null;

export async function getFhevmInstance(): Promise<FhevmInstance> {
  if (_instance) return _instance;
  _instance = await createInstance(SEPOLIA_CONFIG);
  return _instance;
}

// ── React Context for FHEVM ──────────────────────────────────────────────────

interface FhevmContextValue {
  instance: FhevmInstance | null;
  isReady: boolean;
}

const FhevmContext = createContext<FhevmContextValue>({
  instance: null,
  isReady: false,
});

export function FhevmProvider({ children }: { children: React.ReactNode }) {
  const [instance, setInstance] = useState<FhevmInstance | null>(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    getFhevmInstance()
      .then((inst) => {
        setInstance(inst);
        setIsReady(true);
      })
      .catch(console.error);
  }, []);

  return (
    <FhevmContext.Provider value={{ instance, isReady }}>
      {children}
    </FhevmContext.Provider>
  );
}

export function useFhevm() {
  return useContext(FhevmContext);
}

// ── Core FHEVM Operations ────────────────────────────────────────────────────

/**
 * Encrypt a value and generate a ZK proof for a specific contract + sender.
 *
 * @param contractAddress - The contract that will receive the encrypted value (live address!)
 * @param userAddress     - The sender's address
 * @param value           - The plaintext value to encrypt
 * @param type            - The target Solidity type (determines which addXX to call)
 *
 * Returns { handle, inputProof } ready to pass to the contract.
 */
export async function encryptValue(
  contractAddress: string,
  userAddress: string,
  value: bigint,
  type: "uint8" | "uint16" | "uint32" | "uint64" | "uint128" | "uint256" | "bool" | "address"
): Promise<{ handle: bigint; inputProof: Uint8Array }> {
  const instance = await getFhevmInstance();

  // ALWAYS use the live address — never hardcode
  const input = instance.createEncryptedInput(contractAddress, userAddress);

  switch (type) {
    case "uint8":   input.add8(Number(value)); break;
    case "uint16":  input.add16(Number(value)); break;
    case "uint32":  input.add32(Number(value)); break;
    case "uint64":  input.add64(value); break;
    case "uint128": input.add128(value); break;
    case "uint256": input.add256(value); break;
    case "bool":    input.addBool(value !== 0n); break;
    case "address": throw new Error("Use encryptAddress() for addresses");
  }

  const { handles, inputProof } = await input.encrypt();
  return { handle: handles[0], inputProof };
}

/**
 * Re-encrypt a ciphertext handle to read the plaintext value.
 * This triggers an EIP-712 signature request in the user's wallet.
 *
 * @param handle          - The euintXX handle from the contract (bytes32 as bigint)
 * @param contractAddress - The contract that holds the ciphertext
 * @param signer          - The user's ethers signer
 *
 * Returns the plaintext value as BigInt.
 * The user must have FHE.allow(handle, userAddress) in the contract.
 */
export async function reencryptValue(
  handle: bigint,
  contractAddress: string,
  signer: JsonRpcSigner
): Promise<bigint> {
  const instance = await getFhevmInstance();
  const userAddress = await signer.getAddress();

  // Generate a fresh ephemeral keypair — NEVER reuse across sessions
  const { publicKey, privateKey } = instance.generateKeypair();

  // Create EIP-712 payload bound to THIS specific contract
  const eip712 = instance.createEIP712(publicKey, contractAddress);

  // User signs — wallet popup appears
  const signature = await signer.signTypedData(
    eip712.domain,
    { Reencrypt: eip712.types.Reencrypt },
    eip712.message
  );

  // Re-encrypt: KMS decrypts handle, re-encrypts under user's publicKey
  // Only the holder of privateKey can read the result
  const plaintext = await instance.reencrypt(
    handle,
    privateKey,
    publicKey,
    signature,
    contractAddress, // must match EIP-712 domain
    userAddress      // must match signer
  );

  return plaintext;
}

// ── ConfidentialToken Component ──────────────────────────────────────────────

const VAULT_ABI = [
  "function deposit(uint256 encAmount, bytes calldata proof) external",
  "function transfer(address to, uint256 encAmount, bytes calldata proof) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
  "function name() external view returns (string)",
  "function symbol() external view returns (string)",
];

interface TokenUIProps {
  contractAddress: string;
}

export function ConfidentialTokenUI({ contractAddress }: TokenUIProps) {
  const { instance, isReady } = useFhevm();
  const [signer, setSigner] = useState<JsonRpcSigner | null>(null);
  const [userAddress, setUserAddress] = useState<string>("");
  const [balance, setBalance] = useState<bigint | null>(null);
  const [depositAmount, setDepositAmount] = useState("");
  const [transferTo, setTransferTo] = useState("");
  const [transferAmount, setTransferAmount] = useState("");
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState("");

  // Connect wallet
  async function connectWallet() {
    const provider = new BrowserProvider((window as any).ethereum);
    await provider.send("eth_requestAccounts", []);
    const s = await provider.getSigner();
    setSigner(s);
    setUserAddress(await s.getAddress());
    setStatus("Wallet connected");
  }

  // Deposit encrypted amount
  async function deposit() {
    if (!signer || !isReady || !depositAmount) return;
    setLoading(true);
    setStatus("Encrypting deposit...");
    try {
      const amount = BigInt(depositAmount);
      const { handle, inputProof } = await encryptValue(
        contractAddress,
        userAddress,
        amount,
        "uint64"
      );

      const contract = new Contract(contractAddress, VAULT_ABI, signer);
      setStatus("Sending transaction...");
      const tx = await contract.deposit(handle, inputProof);
      setStatus("Waiting for confirmation...");
      await tx.wait();
      setStatus(`Deposited ${depositAmount} tokens successfully`);
      setDepositAmount("");
    } catch (e: any) {
      setStatus(`Error: ${e.message}`);
    } finally {
      setLoading(false);
    }
  }

  // Transfer encrypted amount
  async function transfer() {
    if (!signer || !isReady || !transferTo || !transferAmount) return;
    setLoading(true);
    setStatus("Encrypting transfer...");
    try {
      const amount = BigInt(transferAmount);
      const { handle, inputProof } = await encryptValue(
        contractAddress,
        userAddress,
        amount,
        "uint64"
      );

      const contract = new Contract(contractAddress, VAULT_ABI, signer);
      setStatus("Sending transfer...");
      const tx = await contract.transfer(transferTo, handle, inputProof);
      await tx.wait();
      setStatus("Transfer complete");
      setTransferAmount("");
    } catch (e: any) {
      setStatus(`Error: ${e.message}`);
    } finally {
      setLoading(false);
    }
  }

  // Read balance via re-encryption (requires wallet signature)
  async function readBalance() {
    if (!signer || !isReady) return;
    setLoading(true);
    setStatus("Reading balance (requires wallet signature)...");
    try {
      const provider = new BrowserProvider((window as any).ethereum);
      const contract = new Contract(contractAddress, VAULT_ABI, provider);

      // Fetch the encrypted handle from contract
      const handle: bigint = await contract.balanceOf(userAddress);

      // Re-encrypt to get plaintext (EIP-712 signature popup)
      const plaintext = await reencryptValue(handle, contractAddress, signer);
      setBalance(plaintext);
      setStatus("Balance loaded");
    } catch (e: any) {
      setStatus(`Error: ${e.message}`);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div style={{ maxWidth: 500, margin: "0 auto", padding: 24, fontFamily: "sans-serif" }}>
      <h2>Confidential Token</h2>
      <p style={{ fontSize: 12, color: "#666" }}>Contract: {contractAddress}</p>

      {!signer ? (
        <button onClick={connectWallet}>Connect Wallet</button>
      ) : (
        <>
          <p>Connected: {userAddress.slice(0, 6)}...{userAddress.slice(-4)}</p>

          {/* Balance */}
          <section style={{ marginBottom: 24 }}>
            <h3>Your Balance</h3>
            <button onClick={readBalance} disabled={loading}>
              Read Balance (requires signature)
            </button>
            {balance !== null && (
              <p>Balance: <strong>{balance.toString()}</strong> tokens</p>
            )}
          </section>

          {/* Deposit */}
          <section style={{ marginBottom: 24 }}>
            <h3>Deposit</h3>
            <input
              value={depositAmount}
              onChange={(e) => setDepositAmount(e.target.value)}
              placeholder="Amount (integer)"
              type="number"
              min="0"
            />
            <button onClick={deposit} disabled={loading || !depositAmount}>
              Deposit (Encrypted)
            </button>
          </section>

          {/* Transfer */}
          <section style={{ marginBottom: 24 }}>
            <h3>Transfer</h3>
            <input
              value={transferTo}
              onChange={(e) => setTransferTo(e.target.value)}
              placeholder="Recipient address (0x...)"
            />
            <input
              value={transferAmount}
              onChange={(e) => setTransferAmount(e.target.value)}
              placeholder="Amount (integer)"
              type="number"
              min="0"
            />
            <button onClick={transfer} disabled={loading || !transferTo || !transferAmount}>
              Transfer (Encrypted)
            </button>
          </section>
        </>
      )}

      {status && (
        <div style={{
          padding: 12,
          background: status.startsWith("Error") ? "#fee" : "#efe",
          borderRadius: 4,
          marginTop: 16
        }}>
          {status}
        </div>
      )}
    </div>
  );
}

// ── App Entry Point ──────────────────────────────────────────────────────────

export default function App() {
  return (
    <FhevmProvider>
      <ConfidentialTokenUI contractAddress="0xYOUR_DEPLOYED_CONTRACT_ADDRESS" />
    </FhevmProvider>
  );
}
