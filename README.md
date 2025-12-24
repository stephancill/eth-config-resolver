# ENS Config Resolver

A set of ENS contracts that enable users to claim address-based subnames under your ENS name, with optional L1 → L2 CCIP-Read resolution.

## Overview

This project provides three main contracts:

| Contract                    | Description                                                                           |
| --------------------------- | ------------------------------------------------------------------------------------- |
| **ConfigResolver**          | A general-purpose ENS resolver for setting records (text, address, contenthash, etc.) |
| **AddressSubnameRegistrar** | Enables users to claim `0x<address>.yourname.eth` subnames                            |
| **L1ConfigResolver**        | Reads L2 ConfigResolver records from L1 via CCIP-Read (Unruggable Gateways)           |

## Deployments

### Testnets

| Contract         | Network      | Address                                                                                                                         |
| ---------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| ConfigResolver   | Base Sepolia | [`0xA66c55a6b76967477af18A03F2f12d52251Dc2C0`](https://sepolia.basescan.org/address/0xA66c55a6b76967477af18A03F2f12d52251Dc2C0) |
| L1ConfigResolver | Sepolia      | [`0x380e926f5D78F21b80a6EfeF2B3CEf9CcC89356B`](https://sepolia.etherscan.io/address/0x380e926f5D78F21b80a6EfeF2B3CEf9CcC89356B) |

### Mainnet

| Contract         | Network  | Address |
| ---------------- | -------- | ------- |
| ConfigResolver   | Base     | TBD     |
| L1ConfigResolver | Ethereum | TBD     |

### Example

If you own `ethconfig.eth`, users can claim subnames like:

```
0x8d25687829d6b85d9e0020b8c89e3ca24de20a89.ethconfig.eth
```

The address is normalized to lowercase hex with the `0x` prefix (42 characters total).

## Quick Start

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

Deploy ConfigResolver + AddressSubnameRegistrar:

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

Deploy ConfigResolver only:

```bash
forge script script/Deploy.s.sol --sig "deployConfigResolver()" \
  --rpc-url $RPC_URL \
  --account deployer \
  --broadcast \
  --verify
```

Deploy L1ConfigResolver (for reading L2 records from L1):

```bash
L2_CONFIG_RESOLVER=0x... \
  forge script script/Deploy.s.sol --sig "deployL1Resolver()" \
  --rpc-url $RPC_URL \
  --account deployer \
  --broadcast \
  --verify
```

Deploy L1 AddressSubnameRegistrar (for L1 claiming with L2 storage):

```bash
PARENT_NODE=$(cast namehash "yourname.eth") \
L1_CONFIG_RESOLVER=0x... \
  forge script script/Deploy.s.sol --sig "deployL1Registrar()" \
  --rpc-url $RPC_URL \
  --account deployer \
  --broadcast \
  --verify
```

See [DEPLOYMENT.md](./DEPLOYMENT.md) for the full deployment and setup guide.

## Contracts

### ConfigResolver

A resolver contract that supports all standard ENS record types:

- **Address records** (`addr`)
- **Text records** (`text`)
- **Content hash** (`contenthash`)
- **ABI** (`ABI`)
- **Public key** (`pubkey`)
- **DNS records** (`DNS`)
- **Interface** (`interfaceImplementer`)
- **Name** (`name`)

Authorization is based on:

1. Owning the ENS node
2. Being an approved operator (`setApprovalForAll`)
3. Being an approved delegate (`approve`)
4. Owning the reverse node (for your own address)

### AddressSubnameRegistrar

Allows users to claim subnames based on their Ethereum address:

```solidity
// User claims their subname
registrar.claim();

// Or claim for another address (if approved)
registrar.claimForAddr(addr, owner);

// Check availability
registrar.available(addr);

// Get the label for an address
registrar.getLabel(addr); // "0x8d25687829d6b85d9e0020b8c89e3ca24de20a89"

// Get the node hash
registrar.node(addr);
```

### L1ConfigResolver

An L1 resolver that reads ENS records from a ConfigResolver deployed on L2 (Base) using CCIP-Read. Implements the `IL1ConfigResolver` interface.

```solidity
// Supports standard ENS resolution methods
resolver.addr(node);           // Get ETH address
resolver.text(node, "url");    // Get text record
resolver.contenthash(node);    // Get contenthash

// Also supports ENSIP-10 extended resolution
resolver.resolve(name, data);

// IL1ConfigResolver interface
resolver.l2ChainId();          // Get the L2 chain ID
resolver.l2ConfigResolver();   // Get the L2 ConfigResolver address
```

**Default Verifiers (Base):**
| Network | Verifier | L2 Chain ID |
|---------|----------|-------------|
| Sepolia | `0x7F68510F0fD952184ec0b976De429a29A2Ec0FE3` | 84532 (Base Sepolia) |
| Mainnet | `0x0bC6c539e5fc1fb92F31dE34426f433557A9A5A2` | 8453 (Base) |

Custom verifiers and L2 chain IDs can be specified via environment variables during deployment.

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (for dependencies)

### Install Dependencies

```bash
npm install
```

### Run Tests

```bash
forge test -vv
```

### Format Code

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

## Architecture

### L1 Claiming with L2 Storage (Recommended)

Users claim subnames on L1 (Ethereum) and can change their resolver. Records are stored on L2 (Base) for lower gas costs.

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
│   │                             │     │  • Reads via CCIP-Read        │ │
│   └─────────────────────────────┘     └───────────────┬───────────────┘ │
│                                                       │                  │
│   User owns ENS node → can change resolver if desired │                  │
└───────────────────────────────────────────────────────┼──────────────────┘
                                                        │ CCIP-Read
                                                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                             L2 (Base)                                    │
├─────────────────────────────────────────────────────────────────────────┤
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  ConfigResolver - stores records (text, address, contenthash)   │   │
│   └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

**User Flow:**

1. Claim subname on L1 → `registrar.claim()`
2. Set records on L2 → `resolver.setText(node, "url", "https://...")`
3. L1 resolution reads from L2 via CCIP-Read
4. Optionally change resolver on L1 (user owns the ENS node)

### CCIP-Read Flow

```
┌──────────────────┐     1. Call       ┌─────────────────────┐
│   Your dApp      │ ───────────────►  │  L1ConfigResolver   │
│   (Frontend)     │                   │  (Ethereum L1)      │
└──────────────────┘                   └────────┬────────────┘
        ▲                                       │
        │                              2. Reverts with
        │                                 OffchainLookup
        │                                       │
        │  5. Return                            ▼
        │     verified      ┌─────────────────────────────┐
        │     data          │  Gateway (off-chain)        │
        │                   └─────────────┬───────────────┘
        │                                 │
        │                        3. Fetch proofs from L2
        │                                 │
        │                                 ▼
        │                   ┌─────────────────────────────┐
        │                   │  ConfigResolver (Base L2)   │
        │                   └─────────────────────────────┘
        │                                 │
        │                        4. Return proofs
        └─────────────────────────────────┘
```

## License

MIT
