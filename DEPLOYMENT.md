# Deployment & Setup Guide

This guide walks you through deploying and configuring the `ConfigResolver` and `AddressSubnameRegistrar` contracts.

## Overview

| Contract                  | Purpose                                                               |
| ------------------------- | --------------------------------------------------------------------- |
| `ConfigResolver`          | A general-purpose ENS resolver that allows name owners to set records |
| `AddressSubnameRegistrar` | Allows users to claim `<address>.yourname.eth` subnames               |

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

### Mainnet

| Contract     | Address                                      |
| ------------ | -------------------------------------------- |
| ENS Registry | `0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e` |
| NameWrapper  | `0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401` |

### Sepolia

| Contract     | Address                                      |
| ------------ | -------------------------------------------- |
| ENS Registry | `0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e` |
| NameWrapper  | `0x0635513f179D50A207757E05759CbD106d7dFcE8` |

---

## Step 1: Deploy ConfigResolver

### Using the deploy script

```bash
# Deploy to Sepolia (default)
./script/deploy.sh

# Deploy to Mainnet
./script/deploy.sh mainnet
```

### Manual deployment

```bash
# Set variables
export RPC_URL="https://sepolia.gateway.tenderly.co"
export ENS_REGISTRY="0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
export NAME_WRAPPER="0x0635513f179D50A207757E05759CbD106d7dFcE8"

# Deploy
forge create src/ConfigResolver.sol:ConfigResolver \
  --rpc-url $RPC_URL \
  --account deployer \
  --constructor-args $ENS_REGISTRY $NAME_WRAPPER \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Save the deployed address as `CONFIG_RESOLVER`.

---

## Step 2: Deploy AddressSubnameRegistrar

First, compute the namehash of your parent name:

```bash
# Compute namehash for "ethconfig.eth"
cast namehash "ethconfig.eth"
# Returns: 0x... (your parent node)
```

Then deploy:

```bash
export PARENT_NODE=$(cast namehash "ethconfig.eth")
export CONFIG_RESOLVER="0x..."  # From step 1

forge create src/AddressSubnameRegistrar.sol:AddressSubnameRegistrar \
  --rpc-url $RPC_URL \
  --account deployer \
  --constructor-args $ENS_REGISTRY $NAME_WRAPPER $PARENT_NODE $CONFIG_RESOLVER \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Save the deployed address as `REGISTRAR`.

---

## Step 3: Authorize the Registrar

The registrar needs permission to create subnames. First, check if your name is wrapped.

### Check if your name is wrapped

```bash
# Check who owns the node in ENS Registry
cast call $ENS_REGISTRY "owner(bytes32)(address)" $PARENT_NODE --rpc-url $RPC_URL
```

- If the result is the **NameWrapper address** → your name is **wrapped** (Option B)
- If the result is **your address** → your name is **unwrapped** (Option A)

### Option A: Unwrapped Name

Transfer ownership of the parent name to the registrar:

```bash
# Transfer ownership to the registrar
cast send $ENS_REGISTRY "setOwner(bytes32,address)" \
  $PARENT_NODE \
  $REGISTRAR \
  --rpc-url $RPC_URL \
  --account deployer
```

> ⚠️ **Warning**: This transfers full control. Consider using a wrapper or approval instead.

### Option B: Wrapped Name (Recommended)

If your name is wrapped in NameWrapper, you need to approve the registrar as an operator.

> ⚠️ **Important**: The approval must come from the **actual owner** of the wrapped name, not the deployer (unless they're the same).

**Step 1: Find the wrapped name owner**

```bash
# Check who owns the wrapped name
cast call $NAME_WRAPPER "ownerOf(uint256)(address)" $PARENT_NODE --rpc-url $RPC_URL
```

**Step 2: Approve the registrar (from the owner's account)**

```bash
# Approve registrar to manage your wrapped names
# Run this from the OWNER's account, not the deployer!
cast send $NAME_WRAPPER "setApprovalForAll(address,bool)" \
  $REGISTRAR \
  true \
  --rpc-url $RPC_URL \
  --account <owner-account>  # Must be the wrapped name owner
```

For example, if the owner is in a keystore called `user`:

```bash
cast send $NAME_WRAPPER "setApprovalForAll(address,bool)" \
  $REGISTRAR \
  true \
  --rpc-url $RPC_URL \
  --account user
```

---

## Step 4: Enable Wildcard Resolution (ENSIP-10)

The ConfigResolver supports wildcard resolution, allowing `<address>.yourname.eth` to resolve without users needing to claim the subname first. This enables:

- **Address resolution**: `<address>.yourname.eth` automatically resolves to that address
- **Text records**: Users can set records that resolve via any parent name

### Set ConfigResolver as the parent name's resolver

For wildcard resolution to work, your parent name must use the ConfigResolver as its resolver.

**For wrapped names (NameWrapper):**

```bash
# Set ConfigResolver as the resolver for your parent name
# Run this from the wrapped name OWNER's account
cast send $NAME_WRAPPER "setResolver(bytes32,address)" \
  $PARENT_NODE \
  $CONFIG_RESOLVER \
  --rpc-url $RPC_URL \
  --account <owner-account>
```

**For unwrapped names (ENS Registry):**

```bash
cast send $ENS_REGISTRY "setResolver(bytes32,address)" \
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

### How it works

Once enabled, any lookup for `<address>.yourname.eth` will:

1. ENS checks if the subname exists → it doesn't (not claimed)
2. ENS falls back to the parent's resolver (ConfigResolver)
3. ConfigResolver's `resolve()` function handles the request:
   - For `addr()`: Returns the address from the subdomain label
   - For `text()`: Looks up records stored under the user's reverse node

This means users can set records once (via their reverse node) and have them resolve under any parent name that uses ConfigResolver.

---

## Step 5: Verify Deployment

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

This creates `<address>.ethconfig.eth` for the caller.

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

After deployment, update this section with your addresses:

| Network | Contract                | Address |
| ------- | ----------------------- | ------- |
| Sepolia | ConfigResolver          | `0x...` |
| Sepolia | AddressSubnameRegistrar | `0x...` |
| Mainnet | ConfigResolver          | `0x...` |
| Mainnet | AddressSubnameRegistrar | `0x...` |

---

## Troubleshooting

### "Unauthorised" error when claiming (wrapped names)

This is the most common issue. It means the registrar is not approved to create subnames.

**Diagnosis:**

```bash
# 1. Check if the name is wrapped (owned by NameWrapper in registry)
cast call $ENS_REGISTRY "owner(bytes32)(address)" $PARENT_NODE --rpc-url $RPC_URL

# 2. If wrapped, find the actual owner
cast call $NAME_WRAPPER "ownerOf(uint256)(address)" $PARENT_NODE --rpc-url $RPC_URL

# 3. Check if the registrar is approved by that owner
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

- Ensure the registrar is the owner of the parent node, OR
- Ensure the registrar is approved via NameWrapper **by the wrapped name owner**

### Records not being set

- Ensure the caller owns the subname (check `ens.owner(node)`)
- Ensure the resolver is set correctly (check `ens.resolver(node)`)

---

## Security Considerations

1. **Parent name ownership**: Once you transfer the parent name to the registrar, you lose direct control. Consider using NameWrapper approvals instead.

2. **Subname ownership**: Users fully own their claimed subnames and can set any records.

3. **No fees**: This implementation doesn't charge fees. Add payment logic if needed.

4. **No expiry**: Subnames don't expire unless the parent expires. Consider adding reclaim logic.

5. **Wrapped names**: If the parent is wrapped, subnames will be wrapped too with inherited fuses.
