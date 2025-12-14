#!/bin/bash

# Deploy ConfigResolver and AddressSubnameRegistrar
# Usage: ./script/deploy-all.sh <network> <parent-name>
# Example: ./script/deploy-all.sh sepolia ethconfig.eth

set -e

# Set required environment variables
export ETHERSCAN_API_KEY="253URMD24CWBW4CNU19BC1T8YMY145DJ9S"

# Parse arguments
NETWORK=${1:-sepolia}
PARENT_NAME=${2:-""}

if [ -z "$PARENT_NAME" ]; then
    echo "Usage: ./script/deploy-all.sh <network> <parent-name>"
    echo "Example: ./script/deploy-all.sh sepolia ethconfig.eth"
    exit 1
fi

# Network configuration
if [ "$NETWORK" == "sepolia" ]; then
    RPC_URL="https://sepolia.gateway.tenderly.co"
    CHAIN_ID=11155111
    EXPLORER_URL="https://sepolia.etherscan.io"
    NETWORK_NAME="Sepolia"
elif [ "$NETWORK" == "mainnet" ]; then
    RPC_URL="https://eth.llamarpc.com"
    CHAIN_ID=1
    EXPLORER_URL="https://etherscan.io"
    NETWORK_NAME="Ethereum Mainnet"
else
    echo "Error: Unsupported network. Use 'sepolia' or 'mainnet'"
    exit 1
fi

# Check if deployer account exists
if [ ! -f ~/.foundry/keystores/deployer ]; then
    echo "Error: Foundry account 'deployer' not found."
    echo "Create it with: cast wallet import deployer --interactive"
    exit 1
fi

# Compute parent node
PARENT_NODE=$(cast namehash "$PARENT_NAME")

echo "=========================================="
echo "Deploying to $NETWORK_NAME"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo "Parent Name: $PARENT_NAME"
echo "Parent Node: $PARENT_NODE"
echo ""

# Step 1: Deploy ConfigResolver
echo "Step 1: Deploying ConfigResolver..."
echo "-----------------------------------"

CONFIG_RESOLVER=$(forge script script/DeployConfigResolver.s.sol:DeployConfigResolver \
    --rpc-url $RPC_URL \
    --account deployer \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvv 2>&1 | grep -o 'ConfigResolver deployed at: 0x[a-fA-F0-9]\{40\}' | sed 's/ConfigResolver deployed at: //' | head -1)

if [ -z "$CONFIG_RESOLVER" ]; then
    # Try to get from broadcast logs
    LATEST_RUN=$(find broadcast/DeployConfigResolver.s.sol/$CHAIN_ID -name "run-latest.json" 2>/dev/null | head -1)
    if [ -n "$LATEST_RUN" ]; then
        CONFIG_RESOLVER=$(jq -r '.transactions[] | select(.contractName == "ConfigResolver") | .contractAddress' "$LATEST_RUN" 2>/dev/null | head -1)
    fi
fi

if [ -z "$CONFIG_RESOLVER" ]; then
    echo "Error: Failed to deploy ConfigResolver"
    exit 1
fi

echo "ConfigResolver deployed at: $CONFIG_RESOLVER"
echo ""

# Step 2: Deploy AddressSubnameRegistrar
echo "Step 2: Deploying AddressSubnameRegistrar..."
echo "---------------------------------------------"

export PARENT_NODE
export DEFAULT_RESOLVER=$CONFIG_RESOLVER

REGISTRAR=$(forge script script/DeployAddressSubnameRegistrar.s.sol:DeployAddressSubnameRegistrar \
    --rpc-url $RPC_URL \
    --account deployer \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvv 2>&1 | grep -o 'AddressSubnameRegistrar deployed at: 0x[a-fA-F0-9]\{40\}' | sed 's/AddressSubnameRegistrar deployed at: //' | head -1)

if [ -z "$REGISTRAR" ]; then
    # Try to get from broadcast logs
    LATEST_RUN=$(find broadcast/DeployAddressSubnameRegistrar.s.sol/$CHAIN_ID -name "run-latest.json" 2>/dev/null | head -1)
    if [ -n "$LATEST_RUN" ]; then
        REGISTRAR=$(jq -r '.transactions[] | select(.contractName == "AddressSubnameRegistrar") | .contractAddress' "$LATEST_RUN" 2>/dev/null | head -1)
    fi
fi

if [ -z "$REGISTRAR" ]; then
    echo "Error: Failed to deploy AddressSubnameRegistrar"
    exit 1
fi

echo "AddressSubnameRegistrar deployed at: $REGISTRAR"
echo ""

# Summary
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Network: $NETWORK_NAME"
echo "Parent Name: $PARENT_NAME"
echo "Parent Node: $PARENT_NODE"
echo ""
echo "Contracts:"
echo "  ConfigResolver:            $CONFIG_RESOLVER"
echo "  AddressSubnameRegistrar:   $REGISTRAR"
echo ""
echo "Etherscan:"
echo "  ConfigResolver:            $EXPLORER_URL/address/$CONFIG_RESOLVER"
echo "  AddressSubnameRegistrar:   $EXPLORER_URL/address/$REGISTRAR"
echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Authorize the registrar to create subnames:"
echo ""
echo "   # If your name is UNWRAPPED:"
echo "   cast send 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e \\"
echo "     \"setOwner(bytes32,address)\" \\"
echo "     $PARENT_NODE \\"
echo "     $REGISTRAR \\"
echo "     --rpc-url $RPC_URL \\"
echo "     --account deployer"
echo ""
echo "   # If your name is WRAPPED (recommended):"
echo "   # Approve the registrar on NameWrapper"
echo ""
echo "2. Users can now claim subnames:"
echo "   cast send $REGISTRAR \"claim()\" --rpc-url $RPC_URL --account user"
echo ""
