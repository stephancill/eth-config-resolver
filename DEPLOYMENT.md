# Deployment & Setup Guide

This guide walks you through deploying and configuring the `ConfigResolver`, `AddressSubnameRegistrar`, and `L1ConfigResolver` contracts.

## Overview

| Contract                  | Purpose                                                               |
| ------------------------- | --------------------------------------------------------------------- |
| `ConfigResolver`          | A general-purpose ENS resolver that allows name owners to set records |
| `AddressSubnameRegistrar` | Allows users to claim `<address>.yourname.eth` subnames               |
| `L1ConfigResolver`        | Reads L2 ConfigResolver records from L1 via CCIP-Read                 |

## Architecture Options

### Option A: L1 Claiming with L2 Storage (Recommended)

Users claim subnames on L1 (Ethereum), but records are stored on L2 (Base) for lower gas costs. Users can optionally change their resolver.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           L1 (Ethereum)                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─────────────────────────────┐     ┌───────────────────────────────┐ │
│   │  AddressSubnameRegistrar    │     │      L1ConfigResolver         │ │
│   │  ─────────────────────────  │     │  ───────────────────────────  │ │
│   │  • Users call claim()       │────▶│  • Default resolver for       │ │
│   │  • Creates ENS node on L1   │     │    claimed subnames           │ │
│   │  • Sets resolver to         │     │  • Reads records via          │ │
│   │    L1ConfigResolver         │     │    CCIP-Read from L2          │ │
│   └─────────────────────────────┘     └───────────────┬───────────────┘ │
│                                                       │                  │
│   User owns ENS node → can change resolver if desired │                  │
│                                                       │                  │
└───────────────────────────────────────────────────────┼──────────────────┘
                                                        │ CCIP-Read
                                                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                             L2 (Base)                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                       ConfigResolver                             │   │
│   │  ─────────────────────────────────────────────────────────────  │   │
│   │  • Stores text, address, contenthash records                    │   │
│   │  • Users set records here (low gas)                             │   │
│   │  • Authorizes via reverse node (user's address)                 │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**User Flow:**

1. User calls `claim()` on L1 `AddressSubnameRegistrar` → creates `<address>.parent.eth` in ENS
2. Subname is created with `L1ConfigResolver` as the resolver
3. User sets records on L2 `ConfigResolver` (low gas)
4. L1 resolution reads from L2 via CCIP-Read
5. User can change their L1 resolver anytime (they own the ENS node)

### Option B: L2-Only with Wildcard Resolution

Simpler setup where everything lives on L2, and L1 uses wildcard resolution. Users cannot change their resolver.

```
L1: Parent name resolver = L1ConfigResolver (wildcard ENSIP-10)
L2: ConfigResolver + AddressSubnameRegistrar
```

**Limitation:** Subnames don't exist in L1 ENS registry, so users cannot change their resolver.

## Prerequisites

1. **Foundry installed** - [Install Foundry](https://book.getfoundry.sh/getting-started/installation)
2. **Deployer account** - A funded wallet in Foundry's keystore
3. **ENS name ownership** - You must own the parent name (e.g., `ethconfig.eth`)

### Setting up your deployer account

```bash
# Import an existing private key
cast wallet import deployer --interactive

# Or create a new account
cast wallet new deployer

# Verify it exists
cast wallet list
```

## Contract Addresses

### ENS Addresses (same on all networks)

| Contract     | Address                                      |
| ------------ | -------------------------------------------- |
| ENS Registry | `0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e` |

### Mainnet

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| NameWrapper      | `0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401` |
| Gateway Verifier | `0x0bC6c539e5fc1fb92F31dE34426f433557A9A5A2` |

### Sepolia

| Contract         | Address                                      |
| ---------------- | -------------------------------------------- |
| NameWrapper      | `0x0635513f179D50A207757E05759CbD106d7dFcE8` |
| Gateway Verifier | `0x7F68510F0fD952184ec0b976De429a29A2Ec0FE3` |

---

## Step 1: Deploy Contracts

### Deploy ConfigResolver + AddressSubnameRegistrar

```bash
# Sepolia
PARENT_NODE=$(cast namehash "yourname.eth") \
  forge script script/Deploy.s.sol \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify

# Mainnet
PARENT_NODE=$(cast namehash "yourname.eth") \
  forge script script/Deploy.s.sol \
  --rpc-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify
```

### Deploy ConfigResolver Only

```bash
forge script script/Deploy.s.sol --sig "deployConfigResolver()" \
  --rpc-url $RPC_URL \
  --account deployer \
  --broadcast \
  --verify
```

### Deploy L1ConfigResolver (CCIP-Read)

For reading L2 records from L1:

```bash
L2_CONFIG_RESOLVER=0x... \
  forge script script/Deploy.s.sol --sig "deployL1Resolver()" \
  --rpc-url $RPC_URL \
  --account deployer \
  --broadcast \
  --verify
```

### Deploy L1 AddressSubnameRegistrar (Option A)

For L1 claiming with L2 storage - deploy after L1ConfigResolver:

```bash
# Sepolia
PARENT_NODE=$(cast namehash "yourname.eth") \
L1_CONFIG_RESOLVER=0x... \
  forge script script/Deploy.s.sol --sig "deployL1Registrar()" \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify

# Mainnet
PARENT_NODE=$(cast namehash "yourname.eth") \
L1_CONFIG_RESOLVER=0x... \
  forge script script/Deploy.s.sol --sig "deployL1Registrar()" \
  --rpc-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify
```

Save the deployed addresses for the next steps.

---

## Step 2: Authorize the Registrar

The registrar needs permission to create subnames under your wrapped name.

> ⚠️ **Important**: The approval must come from the **actual owner** of the wrapped name, not the deployer (unless they're the same).

### Find the wrapped name owner

```bash
export PARENT_NODE=$(cast namehash "yourname.eth")

# Check who owns the wrapped name
cast call $NAME_WRAPPER "ownerOf(uint256)(address)" $PARENT_NODE --rpc-url $RPC_URL
```

### Approve the registrar

```bash
# Approve registrar to manage your wrapped names
# Run this from the OWNER's account, not the deployer!
cast send $NAME_WRAPPER "setApprovalForAll(address,bool)" \
  $REGISTRAR \
  true \
  --rpc-url $RPC_URL \
  --account <owner-account>  # Must be the wrapped name owner
```

---

## Step 3: Enable Wildcard Resolution (ENSIP-10)

The ConfigResolver supports wildcard resolution, allowing `<address>.yourname.eth` to resolve without users needing to claim the subname first.

### Set ConfigResolver as the parent name's resolver

```bash
# Set ConfigResolver as the resolver for your parent name
# Run this from the wrapped name OWNER's account
cast send $NAME_WRAPPER "setResolver(bytes32,address)" \
  $PARENT_NODE \
  $CONFIG_RESOLVER \
  --rpc-url $RPC_URL \
  --account <owner-account>
```

### Verify wildcard support

```bash
# Check that ConfigResolver supports IExtendedResolver (0x9061b923)
cast call $CONFIG_RESOLVER "supportsInterface(bytes4)" "0x9061b923" --rpc-url $RPC_URL
# Should return: true (0x01)

# Check that the parent name uses ConfigResolver
cast call $ENS_REGISTRY "resolver(bytes32)(address)" $PARENT_NODE --rpc-url $RPC_URL
# Should return: your CONFIG_RESOLVER address
```

---

## Step 4: Verify Deployment

### Check ConfigResolver

```bash
# Verify it supports the resolver interface (ERC-165)
cast call $CONFIG_RESOLVER "supportsInterface(bytes4)" "0x01ffc9a7" --rpc-url $RPC_URL
# Should return: true (0x01)

# Verify it supports wildcard resolution (ENSIP-10)
cast call $CONFIG_RESOLVER "supportsInterface(bytes4)" "0x9061b923" --rpc-url $RPC_URL
# Should return: true (0x01)
```

### Check AddressSubnameRegistrar

```bash
# Check parent node
cast call $REGISTRAR "parentNode()" --rpc-url $RPC_URL

# Check default resolver
cast call $REGISTRAR "defaultResolver()" --rpc-url $RPC_URL

# Check if an address's subname is available
cast call $REGISTRAR "available(address)" "0x8d25687829D6b85d9e0020B8c89e3Ca24dE20a89" --rpc-url $RPC_URL
```

### Check L1ConfigResolver

```bash
# Verify it supports IExtendedResolver
cast call $L1_RESOLVER "supportsInterface(bytes4)" "0x9061b923" --rpc-url $RPC_URL
# Should return: true (0x01)

# Check the L2 target
cast call $L1_RESOLVER "l2ConfigResolver()" --rpc-url $RPC_URL

# Check the verifier
cast call $L1_RESOLVER "verifier()" --rpc-url $RPC_URL
```

---

## Usage

### Users Claiming Subnames

Users can claim their address-based subname by calling `claim()`:

```bash
# User claims their subname
cast send $REGISTRAR "claim()" \
  --rpc-url $RPC_URL \
  --account user-wallet
```

This creates `<address>.yourname.eth` for the caller.

### Setting Records on Claimed Subnames

After claiming, users can set records on their subname:

```bash
# Get the user's node
USER_NODE=$(cast call $REGISTRAR "node(address)" $USER_ADDRESS --rpc-url $RPC_URL)

# Set a text record
cast send $CONFIG_RESOLVER "setText(bytes32,string,string)" \
  $USER_NODE \
  "url" \
  "https://example.com" \
  --rpc-url $RPC_URL \
  --account user-wallet

# Set an address record
cast send $CONFIG_RESOLVER "setAddr(bytes32,address)" \
  $USER_NODE \
  $USER_ADDRESS \
  --rpc-url $RPC_URL \
  --account user-wallet
```

### Querying Records

```bash
# Get text record
cast call $CONFIG_RESOLVER "text(bytes32,string)" $USER_NODE "url" --rpc-url $RPC_URL

# Get address
cast call $CONFIG_RESOLVER "addr(bytes32)" $USER_NODE --rpc-url $RPC_URL
```

---

## Frontend Integration

### ethers.js v6 Example

```javascript
import { ethers } from "ethers";

const registrar = new ethers.Contract(
  REGISTRAR_ADDRESS,
  [
    "function claim() returns (bytes32)",
    "function available(address) view returns (bool)",
    "function getLabel(address) view returns (string)",
    "function node(address) view returns (bytes32)",
  ],
  signer
);

const resolver = new ethers.Contract(
  RESOLVER_ADDRESS,
  [
    "function setText(bytes32,string,string)",
    "function text(bytes32,string) view returns (string)",
    "function setAddr(bytes32,address)",
    "function addr(bytes32) view returns (address)",
  ],
  signer
);

// Check availability
const isAvailable = await registrar.available(userAddress);

// Claim subname
if (isAvailable) {
  const tx = await registrar.claim();
  await tx.wait();
}

// Get the node for the user
const node = await registrar.node(userAddress);

// Set records
await resolver.setText(node, "url", "https://example.com");
await resolver.setAddr(node, userAddress);
```

### viem Example

```typescript
import { createPublicClient, createWalletClient, http } from "viem";
import { mainnet } from "viem/chains";

const publicClient = createPublicClient({
  chain: mainnet,
  transport: http(),
});

// Check availability
const isAvailable = await publicClient.readContract({
  address: REGISTRAR_ADDRESS,
  abi: registrarAbi,
  functionName: "available",
  args: [userAddress],
});

// Claim
const hash = await walletClient.writeContract({
  address: REGISTRAR_ADDRESS,
  abi: registrarAbi,
  functionName: "claim",
});
```

---

## Deployed Contracts

### Testnets

| Network      | Contract         | Address                                                                                                                         |
| ------------ | ---------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Base Sepolia | ConfigResolver   | [`0xA66c55a6b76967477af18A03F2f12d52251Dc2C0`](https://sepolia.basescan.org/address/0xA66c55a6b76967477af18A03F2f12d52251Dc2C0) |
| Sepolia      | L1ConfigResolver | [`0x380e926f5D78F21b80a6EfeF2B3CEf9CcC89356B`](https://sepolia.etherscan.io/address/0x380e926f5D78F21b80a6EfeF2B3CEf9CcC89356B) |

### Mainnet

| Network  | Contract         | Address |
| -------- | ---------------- | ------- |
| Base     | ConfigResolver   | TBD     |
| Ethereum | L1ConfigResolver | TBD     |

---

## Troubleshooting

### "Unauthorised" error when claiming

This is the most common issue. It means the registrar is not approved to create subnames.

**Diagnosis:**

```bash
# 1. Find the wrapped name owner
cast call $NAME_WRAPPER "ownerOf(uint256)(address)" $PARENT_NODE --rpc-url $RPC_URL

# 2. Check if the registrar is approved by that owner
cast call $NAME_WRAPPER "isApprovedForAll(address,address)(bool)" \
  <owner-address> \
  $REGISTRAR \
  --rpc-url $RPC_URL
```

**Solution:** Run the approval from the **wrapped name owner's** account (not the deployer):

```bash
cast send $NAME_WRAPPER "setApprovalForAll(address,bool)" \
  $REGISTRAR \
  true \
  --rpc-url $RPC_URL \
  --account <owner-account>
```

### "Unauthorized" error when claiming (user not authorized)

- Ensure the caller is the address they're trying to claim for
- Or ensure they have ENS approval (`isApprovedForAll`)

### "AlreadyClaimed" error

- The subname has already been claimed by someone
- Check with `available(address)`

### Registrar can't create subnames

- Ensure the registrar is approved via NameWrapper **by the wrapped name owner**

### Records not being set

- Ensure the caller owns the subname (check `ens.owner(node)`)
- Ensure the resolver is set correctly (check `ens.resolver(node)`)

---

## Full Deployment Workflow (Option A)

This is the complete workflow for deploying the L1 claiming with L2 storage architecture.

### Step 1: Deploy ConfigResolver on L2 (Base)

```bash
# Base Sepolia
forge script script/Deploy.s.sol --sig "deployConfigResolver()" \
  --rpc-url https://base-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify

# Base Mainnet
forge script script/Deploy.s.sol --sig "deployConfigResolver()" \
  --rpc-url https://base-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify
```

Save the L2 ConfigResolver address as `L2_CONFIG_RESOLVER`.

### Step 2: Deploy L1ConfigResolver on L1

```bash
# Sepolia
L2_CONFIG_RESOLVER=0x... \
  forge script script/Deploy.s.sol --sig "deployL1Resolver()" \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify

# Mainnet
L2_CONFIG_RESOLVER=0x... \
  forge script script/Deploy.s.sol --sig "deployL1Resolver()" \
  --rpc-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify
```

Save the L1ConfigResolver address as `L1_CONFIG_RESOLVER`.

### Step 3: Deploy L1 AddressSubnameRegistrar

```bash
# Sepolia
PARENT_NODE=$(cast namehash "yourname.eth") \
L1_CONFIG_RESOLVER=0x... \
  forge script script/Deploy.s.sol --sig "deployL1Registrar()" \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify

# Mainnet
PARENT_NODE=$(cast namehash "yourname.eth") \
L1_CONFIG_RESOLVER=0x... \
  forge script script/Deploy.s.sol --sig "deployL1Registrar()" \
  --rpc-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account deployer \
  --broadcast \
  --verify
```

Save the L1 AddressSubnameRegistrar address as `L1_REGISTRAR`.

### Step 4: Authorize L1 Registrar

The L1 registrar needs permission to create subnames under your wrapped parent name.

```bash
# From the wrapped name owner's account
cast send $NAME_WRAPPER "setApprovalForAll(address,bool)" \
  $L1_REGISTRAR \
  true \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account <owner-account>
```

### Step 5: User Claims on L1

Users can now claim their subname on L1:

```bash
cast send $L1_REGISTRAR "claim()" \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account user-wallet
```

### Step 6: User Sets Records on L2

Users set their records on the L2 ConfigResolver:

```bash
# Get the user's node hash
USER_NODE=$(cast call $L1_REGISTRAR "node(address)(bytes32)" $USER_ADDRESS \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY)

# Set a text record on L2
cast send $L2_CONFIG_RESOLVER "setText(bytes32,string,string)" \
  $USER_NODE \
  "url" \
  "https://example.com" \
  --rpc-url https://base-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account user-wallet
```

### Step 7: (Optional) User Changes Resolver

Users who want a different resolver can change it on L1 (they own the wrapped subname):

```bash
# User changes their resolver via NameWrapper
cast send $NAME_WRAPPER "setResolver(bytes32,address)" \
  $USER_NODE \
  $NEW_RESOLVER \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_API_KEY \
  --account user-wallet
```

---

## Security Considerations

1. **Subname ownership**: Users fully own their claimed subnames and can set any records.

2. **No fees**: This implementation doesn't charge fees. Add payment logic if needed.

3. **No expiry**: Subnames don't expire unless the parent expires. Consider adding reclaim logic.

4. **Wrapped subnames**: Since the parent is wrapped, subnames will be wrapped too with inherited fuses.
