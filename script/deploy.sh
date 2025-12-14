#!/bin/bash

# Set required environment variables
export ETHERSCAN_API_KEY="253URMD24CWBW4CNU19BC1T8YMY145DJ9S"

# Network configuration - default to Sepolia
NETWORK=${1:-sepolia}

if [ "$NETWORK" == "sepolia" ]; then
    RPC_URL="https://sepolia.gateway.tenderly.co"
    CHAIN_ID=11155111
    ENS_REGISTRY="0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
    NAME_WRAPPER="0x0635513f179D50A207757E05759CbD106d7dFcE8"
    EXPLORER_URL="https://sepolia.etherscan.io"
    NETWORK_NAME="Sepolia"
elif [ "$NETWORK" == "mainnet" ]; then
    RPC_URL="https://eth.llamarpc.com"
    CHAIN_ID=1
    ENS_REGISTRY="0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
    NAME_WRAPPER="0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401"
    EXPLORER_URL="https://etherscan.io"
    NETWORK_NAME="Ethereum Mainnet"
else
    echo "Error: Unsupported network. Use 'sepolia' or 'mainnet'"
    exit 1
fi

# Check if deployer account exists
if [ ! -f ~/.foundry/keystores/deployer ]; then
    echo "Error: Foundry account 'deployer' not found."
    echo "Keystore file should be at: ~/.foundry/keystores/deployer"
    exit 1
fi

echo "=========================================="
echo "Deploying ConfigResolver to $NETWORK_NAME"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo "Chain ID: $CHAIN_ID"
echo "ENS Registry: $ENS_REGISTRY"
echo "NameWrapper: $NAME_WRAPPER"
echo "Deployer account: deployer (keystore)"
echo ""

# Deploy the contract
echo "Deploying contract..."
DEPLOY_OUTPUT=$(forge script script/DeployConfigResolver.s.sol:DeployConfigResolver \
    --rpc-url $RPC_URL \
    --account deployer \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv 2>&1)

# Extract the deployed contract address from the output
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -o 'ConfigResolver deployed at: 0x[a-fA-F0-9]\{40\}' | sed 's/ConfigResolver deployed at: //' || \
                   echo "$DEPLOY_OUTPUT" | grep -o 'Deployed to: 0x[a-fA-F0-9]\{40\}' | sed 's/Deployed to: //' || \
                   echo "$DEPLOY_OUTPUT" | grep -A 5 "ConfigResolver" | grep -o '0x[a-fA-F0-9]\{40\}' | head -1)

if [ -z "$CONTRACT_ADDRESS" ]; then
    # Try to get it from broadcast logs
    LATEST_BROADCAST=$(find broadcast/DeployConfigResolver.s.sol -type d -name "$CHAIN_ID" 2>/dev/null | sort -r | head -1)
    if [ -n "$LATEST_BROADCAST" ]; then
        LATEST_RUN=$(find "$LATEST_BROADCAST" -name "run-latest.json" 2>/dev/null)
        if [ -n "$LATEST_RUN" ]; then
            CONTRACT_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "ConfigResolver") | .contractAddress' "$LATEST_RUN" 2>/dev/null | head -1)
        fi
    fi
fi

if [ -z "$CONTRACT_ADDRESS" ]; then
    echo "Error: Could not extract contract address from deployment output"
    echo "Deployment output:"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

echo ""
echo "=========================================="
echo "Deployment successful!"
echo "Contract address: $CONTRACT_ADDRESS"
echo "=========================================="
echo ""

# Note: Verification is handled automatically by the --verify flag during deployment
# Both Etherscan and Sourcify will be notified
echo "=========================================="
echo "Verification"
echo "=========================================="
echo "Etherscan verification was attempted during deployment via --verify flag"
echo "Sourcify will automatically pick up the verification from Etherscan"
echo ""
echo "Contract address: $CONTRACT_ADDRESS"
echo "Etherscan: $EXPLORER_URL/address/$CONTRACT_ADDRESS"
echo "Sourcify: https://sourcify.dev/#/lookup/$CONTRACT_ADDRESS"
echo ""

