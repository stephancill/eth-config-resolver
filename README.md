# ENS Config Resolver

A set of ENS contracts that enable users to claim address-based subnames under your ENS name.

## Overview

This project provides two main contracts:

| Contract                    | Description                                                                           |
| --------------------------- | ------------------------------------------------------------------------------------- |
| **ConfigResolver**          | A general-purpose ENS resolver for setting records (text, address, contenthash, etc.) |
| **AddressSubnameRegistrar** | Enables users to claim `<their-address>.yourname.eth` subnames                        |

### Example

If you own `ethconfig.eth`, users can claim subnames like:

```
0x8d25687829d6b85d9e0020b8c89e3ca24de20a89.ethconfig.eth
```

The address is normalized to lowercase hex (42 characters, with `0x` prefix).

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

```bash
# Deploy to Sepolia
./script/deploy.sh

# Deploy to Mainnet
./script/deploy.sh mainnet
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

```
┌─────────────────────────────────────────────────────────────┐
│                      User's Wallet                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              AddressSubnameRegistrar                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ claim() → creates <address>.parent.eth              │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────────┐
│      ENS Registry       │     │      ConfigResolver         │
│  (stores ownership)     │     │  (stores records)           │
└─────────────────────────┘     └─────────────────────────────┘
```

## License

MIT
