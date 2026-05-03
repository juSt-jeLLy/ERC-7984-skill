# Deploying FHEVM Contracts

## Pre-Deployment Checklist

Before deploying, verify:

```
□ Contract inherits correct network config (SepoliaFHEVMConfig or ZamaEthereumConfig)
□ All encrypted assignments have FHE.allowThis() afterward
□ All user-readable values have FHE.allow(handle, userAddress)
□ All encrypted mappings are initialized before first use
□ FHE.fromExternal() used for all externalEuintXX parameters
□ evmVersion: "cancun" in hardhat.config.ts
□ Solidity version 0.8.24 or higher
□ Wallet funded with enough ETH for deployment gas
```

## Hardhat Deployment

### Using `hardhat-deploy`

```typescript
// deploy/01_deploy_vault.ts
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployVault: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployer } = await hre.getNamedAccounts();
    const { deploy } = hre.deployments;

    const result = await deploy("Vault", {
        from: deployer,
        args: [],  // constructor arguments
        log: true,
        waitConfirmations: hre.network.name === "sepolia" ? 5 : 1,
    });

    console.log("Vault deployed to:", result.address);

    // Verify on Etherscan (Sepolia only)
    if (hre.network.name === "sepolia" && process.env.ETHERSCAN_API_KEY) {
        await hre.run("verify:verify", {
            address: result.address,
            constructorArguments: [],
        });
    }
};

deployVault.tags = ["Vault"];
export default deployVault;
```

```bash
# Deploy to Sepolia
npx hardhat deploy --network sepolia

# Deploy to local Hardhat
npx hardhat deploy --network localhost
```

### Using Hardhat Ignition (Modern)

```typescript
// ignition/modules/Vault.ts
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("VaultModule", (m) => {
    const vault = m.contract("Vault", []);
    return { vault };
});
```

```bash
npx hardhat ignition deploy ignition/modules/Vault.ts --network sepolia
```

### Direct Deploy Script

```typescript
// scripts/deploy.ts
import { ethers } from "hardhat";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying from:", deployer.address);
    console.log("Balance:", (await deployer.provider.getBalance(deployer.address)).toString());

    const Vault = await ethers.getContractFactory("Vault");
    const vault = await Vault.deploy();
    await vault.waitForDeployment();

    const address = await vault.getAddress();
    console.log("Vault deployed to:", address);

    // Save address for frontend
    const fs = require("fs");
    fs.writeFileSync("./deployment.json", JSON.stringify({ vault: address }, null, 2));
}

main().catch(console.error);
```

```bash
npx hardhat run scripts/deploy.ts --network sepolia
```

## Environment Setup for Sepolia

```bash
# Option 1: hardhat vars (recommended)
npx hardhat vars set MNEMONIC
npx hardhat vars set INFURA_API_KEY
npx hardhat vars set ETHERSCAN_API_KEY  # optional

# Option 2: .env file
MNEMONIC="your twelve word mnemonic phrase here..."
INFURA_API_KEY=your_infura_key
ETHERSCAN_API_KEY=your_etherscan_key
```

## Network Configuration

```typescript
// hardhat.config.ts — network section
networks: {
    hardhat: {
        chainId: 31337,
        accounts: { mnemonic: MNEMONIC },
    },
    sepolia: {
        url: `https://sepolia.infura.io/v3/${INFURA_API_KEY}`,
        // or: url: "https://eth-sepolia.public.blastapi.io",
        chainId: 11155111,
        accounts: { mnemonic: MNEMONIC },
    },
    // Ethereum mainnet
    mainnet: {
        url: `https://mainnet.infura.io/v3/${INFURA_API_KEY}`,
        chainId: 1,
        accounts: { mnemonic: MNEMONIC },
    },
},
```

## Contract Verification

```bash
# Verify on Etherscan after deployment
npx hardhat verify --network sepolia 0xYOUR_CONTRACT_ADDRESS

# With constructor arguments
npx hardhat verify --network sepolia 0xYOUR_CONTRACT_ADDRESS "MyToken" "MTK"
```

## Foundry Deployment (React Template)

```bash
# Deploy to Sepolia using Foundry
forge script script/DeployVault.s.sol:DeployVault \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --broadcast \
    --verify \
    -vvvv
```

```solidity
// script/DeployVault.s.sol
pragma solidity ^0.8.24;
import { Script } from "forge-std/Script.sol";
import { Vault } from "../src/Vault.sol";

contract DeployVault is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        
        Vault vault = new Vault();
        console.log("Vault:", address(vault));
        
        vm.stopBroadcast();
    }
}
```

## Post-Deployment Steps

1. **Save the deployed address** — update your frontend config
2. **Verify on Etherscan** — confirms source code matches bytecode
3. **Fund the contract** if it needs ETH for operations
4. **Initialize state** if constructor doesn't do it (e.g., mint initial supply)
5. **Test on Sepolia** — run integration tests against the live deployment

## Gas Considerations

FHE operations use more gas than standard EVM operations. For Sepolia deployment:

- Use a funded Sepolia wallet (minimum 0.1 ETH recommended)
- Set `gasLimit` if estimation fails: `await contract.deposit({ gasLimit: 500_000 })`
- Monitor gas with `REPORT_GAS=true npx hardhat test`

## Common Deployment Errors

| Error | Fix |
|---|---|
| `insufficient funds` | Fund wallet from Sepolia faucets |
| `Nonce too high` | Wait for pending txs or run `npx hardhat clean` |
| `Cannot estimate gas` | Check for revert reason with `staticCall` |
| `Contract source code already verified` | Already verified — no action needed |
| Network not responding | Switch RPC URL; use public Sepolia endpoint |

See [`addresses.md`](addresses.md) for Sepolia RPC endpoints and contract addresses.
