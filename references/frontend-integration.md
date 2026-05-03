# Frontend Integration with FHEVM

## SDK Options

### Option A: `@zama-fhe/sdk` + `@zama-fhe/react-sdk` (React Template)

The React template uses Foundry + Next.js with `@zama-fhe/sdk` v3. This is the recommended setup for new dApps.

### Option B: `fhevmjs` (older Hardhat template)

The Hardhat template uses `fhevmjs`. Both are supported; this guide covers both.

---

## Setup: `@zama-fhe/react-sdk` (Recommended)

### Install

```bash
npm install @zama-fhe/sdk @zama-fhe/react-sdk
```

### Vite Config (Required)

```typescript
// vite.config.ts — CORS headers required for WASM SharedArrayBuffer
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",     // COOP
      "Cross-Origin-Embedder-Policy": "require-corp",  // COEP
    },
  },
  optimizeDeps: {
    exclude: ["@zama-fhe/relayer-sdk"],  // do not pre-bundle WASM
  },
});
```

### Provider Setup

```typescript
// app/layout.tsx (Next.js) or App.tsx (Vite)
import { ZamaProvider } from "@zama-fhe/react-sdk";
import { RelayerWeb } from "@zama-fhe/relayer-sdk";

// For Sepolia testnet
const relayer = new RelayerWeb({
  relayerUrl: "https://relayer.testnet.zama.ai",
});

// For local development
// import { RelayerCleartext } from "@zama-fhe/relayer-sdk";
// const relayer = new RelayerCleartext({ rpcUrl: "http://localhost:8545" });

export default function App() {
  return (
    <ZamaProvider relayer={relayer}>
      {/* your app */}
    </ZamaProvider>
  );
}
```

### Hook: `useZama`

```typescript
import { useZama } from "@zama-fhe/react-sdk";

function BalanceDisplay({ contractAddress }: { contractAddress: string }) {
  const { instance, isReady } = useZama();

  const readBalance = async (userAddress: string, handle: bigint) => {
    if (!instance || !isReady) return;

    // Generate fresh keypair
    const { publicKey, privateKey } = instance.generateKeypair();

    // Create EIP-712 for this contract
    const eip712 = instance.createEIP712(publicKey, contractAddress);

    // Sign (user approval popup)
    const provider = new BrowserProvider(window.ethereum);
    const signer = await provider.getSigner();
    const signature = await signer.signTypedData(
      eip712.domain,
      { Reencrypt: eip712.types.Reencrypt },
      eip712.message
    );

    // Re-encrypt to get plaintext
    const balance = await instance.reencrypt(
      handle,
      privateKey,
      publicKey,
      signature,
      contractAddress,
      userAddress
    );

    return balance; // BigInt
  };

  return <div>...</div>;
}
```

---

## Setup: `fhevmjs` (Hardhat Template)

### Install

```bash
npm install fhevmjs
```

### Initialize Instance

```typescript
// lib/fhevm.ts
import { createInstance, FhevmInstance } from "fhevmjs/web";

let instance: FhevmInstance | null = null;

export async function getInstance(): Promise<FhevmInstance> {
  if (instance) return instance;

  // For Sepolia testnet:
  instance = await createInstance({
    kmsContractAddress: "0x9D6891A6240D6130c54ae243d8005063D05fE14b", // Sepolia KMS
    aclContractAddress: "0xFee8407e2f5e3Ee68ad77cAE98c434e637f516e5", // Sepolia ACL
    networkUrl: "https://eth-sepolia.public.blastapi.io",
    gatewayUrl: "https://gateway.sepolia.zama.ai",
  });

  return instance;
}
```

See [`addresses.md`](addresses.md) for all network contract addresses.

### Encrypting and Sending

```typescript
import { getInstance } from "./lib/fhevm";
import { BrowserProvider, Contract } from "ethers";

async function encryptedDeposit(
  contractAddress: string,
  abi: any[],
  amount: bigint
) {
  const instance = await getInstance();
  const provider = new BrowserProvider(window.ethereum);
  const signer = await provider.getSigner();

  const contractAddr = await new Contract(contractAddress, abi, provider).getAddress();
  const userAddr = await signer.getAddress();

  // Create encrypted input
  const input = instance.createEncryptedInput(contractAddr, userAddr);
  input.add64(amount);  // must match Solidity: externalEuint64
  const { handles, inputProof } = await input.encrypt();

  // Send transaction
  const contract = new Contract(contractAddress, abi, signer);
  const tx = await contract.deposit(handles[0], inputProof);
  await tx.wait();
}
```

### Re-encryption (User Decrypt)

```typescript
async function readBalance(contractAddress: string, abi: any[]): Promise<bigint> {
  const instance = await getInstance();
  const provider = new BrowserProvider(window.ethereum);
  const signer = await provider.getSigner();
  const userAddress = await signer.getAddress();

  // Always generate fresh keypair per session
  const { publicKey, privateKey } = instance.generateKeypair();

  // EIP-712 payload for this contract
  const eip712 = instance.createEIP712(publicKey, contractAddress);

  // User signs
  const signature = await signer.signTypedData(
    eip712.domain,
    { Reencrypt: eip712.types.Reencrypt },
    eip712.message
  );

  // Fetch handle from contract
  const contract = new Contract(contractAddress, abi, provider);
  const handle = await contract.balanceOf(userAddress);

  // Re-encrypt
  return await instance.reencrypt(
    handle,
    privateKey,
    publicKey,
    signature,
    contractAddress,
    userAddress
  );
}
```

---

## React Component Example

```tsx
import React, { useState } from "react";
import { BrowserProvider } from "ethers";
import { getInstance } from "./lib/fhevm";
import VAULT_ABI from "./abi/Vault.json";

const CONTRACT_ADDRESS = "0x..."; // your deployed contract

export function VaultUI() {
  const [balance, setBalance] = useState<bigint | null>(null);
  const [amount, setAmount] = useState("");
  const [loading, setLoading] = useState(false);

  async function deposit() {
    setLoading(true);
    try {
      const instance = await getInstance();
      const provider = new BrowserProvider(window.ethereum);
      const signer = await provider.getSigner();

      const input = instance.createEncryptedInput(
        CONTRACT_ADDRESS,
        await signer.getAddress()
      );
      input.add64(BigInt(amount));
      const { handles, inputProof } = await input.encrypt();

      const { Contract } = await import("ethers");
      const contract = new Contract(CONTRACT_ADDRESS, VAULT_ABI, signer);
      const tx = await contract.deposit(handles[0], inputProof);
      await tx.wait();
      alert("Deposited!");
    } finally {
      setLoading(false);
    }
  }

  async function readBalance() {
    setLoading(true);
    try {
      const instance = await getInstance();
      const provider = new BrowserProvider(window.ethereum);
      const signer = await provider.getSigner();
      const userAddress = await signer.getAddress();

      const { publicKey, privateKey } = instance.generateKeypair();
      const eip712 = instance.createEIP712(publicKey, CONTRACT_ADDRESS);
      const signature = await signer.signTypedData(
        eip712.domain,
        { Reencrypt: eip712.types.Reencrypt },
        eip712.message
      );

      const { Contract } = await import("ethers");
      const contract = new Contract(CONTRACT_ADDRESS, VAULT_ABI, provider);
      const handle = await contract.balanceOf(userAddress);

      const bal = await instance.reencrypt(
        handle, privateKey, publicKey, signature,
        CONTRACT_ADDRESS, userAddress
      );
      setBalance(bal);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div>
      <h1>Confidential Vault</h1>
      <input
        value={amount}
        onChange={e => setAmount(e.target.value)}
        placeholder="Amount to deposit"
        type="number"
      />
      <button onClick={deposit} disabled={loading}>Deposit</button>
      <button onClick={readBalance} disabled={loading}>Read Balance</button>
      {balance !== null && <p>Your balance: {balance.toString()}</p>}
    </div>
  );
}
```

---

## wagmi Integration (React Template)

The React template uses wagmi + RainbowKit. See `hooks/fhecounter-example/useFHECounterWagmi.tsx` in the template for a complete wagmi hook example.

```typescript
import { useWriteContract, useReadContract } from "wagmi";

// Reading handle (public — returns bytes32)
const { data: handle } = useReadContract({
  address: CONTRACT_ADDRESS,
  abi: VAULT_ABI,
  functionName: "balanceOf",
  args: [userAddress],
});
// Re-encryption happens separately via fhevm instance
```

---

## Common Frontend Errors

| Error | Fix |
|---|---|
| `SharedArrayBuffer is not defined` | Add CORS headers to Vite/Next config (COOP + COEP) |
| `instance.reencrypt returns 0` | `FHE.allow(handle, userAddress)` not called in contract |
| `Proof verification failed` | Used hardcoded address; use `contract.getAddress()` |
| `Invalid signature` | Reused keypair; generate fresh `generateKeypair()` per session |
| `WASM init failed` | Exclude `@zama-fhe/relayer-sdk` from Vite `optimizeDeps` |

See [`error-reference.md`](error-reference.md) for full error details.
