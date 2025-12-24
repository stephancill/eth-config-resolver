// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ConfigResolver} from "../src/ConfigResolver.sol";
import {AddressSubnameRegistrar} from "../src/AddressSubnameRegistrar.sol";
import {L1ConfigResolver} from "../src/L1ConfigResolver.sol";
import {ENS} from "@ensdomains/ens-contracts/registry/ENS.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";
import {IGatewayVerifier} from "@unruggable/contracts/IGatewayVerifier.sol";

/// @title Deploy
/// @notice Unified deployment script for ENS Config Resolver contracts
/// @dev Supports deploying ConfigResolver, AddressSubnameRegistrar, and L1ConfigResolver
///
/// Usage:
///   # Deploy ConfigResolver only
///   forge script script/Deploy.s.sol --sig "deployConfigResolver()" --rpc-url $RPC_URL --account deployer --broadcast --verify
///
///   # Deploy ConfigResolver + AddressSubnameRegistrar
///   PARENT_NODE=$(cast namehash yourname.eth) forge script script/Deploy.s.sol --sig "deployAll()" --rpc-url $RPC_URL --account deployer --broadcast --verify
///
///   # Deploy L1ConfigResolver (for reading L2 records from L1)
///   L2_CONFIG_RESOLVER=0x... forge script script/Deploy.s.sol --sig "deployL1Resolver()" --rpc-url $RPC_URL --account deployer --broadcast --verify
///
///   # Deploy L1ConfigResolver with custom verifier/chain (e.g., for non-Base L2s)
///   VERIFIER=0x... L2_CHAIN_ID=42161 L2_CONFIG_RESOLVER=0x... forge script script/Deploy.s.sol --sig "deployL1Resolver()" --rpc-url $RPC_URL --account deployer --broadcast --verify
contract Deploy is Script {
    // ============ Chain IDs ============
    uint256 constant MAINNET = 1;
    uint256 constant SEPOLIA = 11155111;
    uint256 constant BASE_MAINNET = 8453;
    uint256 constant BASE_SEPOLIA = 84532;

    // ============ ENS Addresses ============
    // ENS Registry is the same on Mainnet and Sepolia
    address constant ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    // On L2s without ENS, we use a dummy address (users can only use reverse nodes)
    address constant DUMMY_ENS = address(0);

    // ============ NameWrapper Addresses ============
    address constant MAINNET_NAME_WRAPPER =
        0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401;
    address constant SEPOLIA_NAME_WRAPPER =
        0x0635513f179D50A207757E05759CbD106d7dFcE8;
    address constant DUMMY_NAME_WRAPPER = address(0);

    // ============ Gateway Verifier Addresses ============
    // Sepolia verifier for Base Sepolia
    IGatewayVerifier constant SEPOLIA_VERIFIER =
        IGatewayVerifier(0x7F68510F0fD952184ec0b976De429a29A2Ec0FE3);
    // Mainnet verifier for Base
    IGatewayVerifier constant MAINNET_VERIFIER =
        IGatewayVerifier(0x0bC6c539e5fc1fb92F31dE34426f433557A9A5A2);

    // ============ Network Detection ============

    function _getENSRegistry() internal view returns (address) {
        if (block.chainid == MAINNET || block.chainid == SEPOLIA) {
            return ENS_REGISTRY;
        } else if (
            block.chainid == BASE_MAINNET || block.chainid == BASE_SEPOLIA
        ) {
            // L2s don't have ENS - use dummy (only reverse node auth works)
            return DUMMY_ENS;
        } else {
            revert("Unsupported chain");
        }
    }

    function _getNameWrapper() internal view returns (address) {
        if (block.chainid == MAINNET) {
            return MAINNET_NAME_WRAPPER;
        } else if (block.chainid == SEPOLIA) {
            return SEPOLIA_NAME_WRAPPER;
        } else if (
            block.chainid == BASE_MAINNET || block.chainid == BASE_SEPOLIA
        ) {
            // L2s don't have NameWrapper
            return DUMMY_NAME_WRAPPER;
        } else {
            revert("Unsupported chain");
        }
    }

    function _getDefaultVerifier() internal view returns (address) {
        if (block.chainid == MAINNET) {
            return address(MAINNET_VERIFIER);
        } else if (block.chainid == SEPOLIA) {
            return address(SEPOLIA_VERIFIER);
        } else {
            return address(0);
        }
    }

    function _getDefaultL2ChainId() internal view returns (uint256) {
        if (block.chainid == MAINNET) {
            return BASE_MAINNET;
        } else if (block.chainid == SEPOLIA) {
            return BASE_SEPOLIA;
        } else {
            return 0;
        }
    }

    function _getNetworkName() internal view returns (string memory) {
        if (block.chainid == MAINNET) {
            return "Ethereum Mainnet";
        } else if (block.chainid == SEPOLIA) {
            return "Sepolia";
        } else if (block.chainid == BASE_MAINNET) {
            return "Base Mainnet";
        } else if (block.chainid == BASE_SEPOLIA) {
            return "Base Sepolia";
        } else {
            return "Unknown";
        }
    }

    function _isL2() internal view returns (bool) {
        return block.chainid == BASE_MAINNET || block.chainid == BASE_SEPOLIA;
    }

    // ============ Deploy ConfigResolver Only ============

    /// @notice Deploy ConfigResolver contract
    /// @return resolver The deployed ConfigResolver address
    function deployConfigResolver() public returns (ConfigResolver resolver) {
        address ensRegistry = _getENSRegistry();
        address nameWrapper = _getNameWrapper();

        console.log("");
        console.log("==========================================");
        console.log("Deploying ConfigResolver");
        console.log("==========================================");
        console.log("Network:", _getNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("ENS Registry:", ensRegistry);
        console.log("NameWrapper:", nameWrapper);
        if (_isL2()) {
            console.log("");
            console.log("NOTE: On L2, only reverse node authorization works.");
            console.log(
                "      Users can set records for their own address only."
            );
        }
        console.log("");

        vm.startBroadcast();
        resolver = new ConfigResolver(
            ENS(ensRegistry),
            INameWrapper(nameWrapper)
        );
        vm.stopBroadcast();

        console.log("ConfigResolver deployed at:", address(resolver));
        console.log("");
    }

    // ============ Deploy ConfigResolver + AddressSubnameRegistrar ============

    /// @notice Deploy ConfigResolver and AddressSubnameRegistrar
    /// @dev Requires PARENT_NODE environment variable (use `cast namehash yourname.eth`)
    ///      Note: AddressSubnameRegistrar requires ENS, so only works on L1
    /// @return resolver The deployed ConfigResolver address
    /// @return registrar The deployed AddressSubnameRegistrar address
    function deployAll()
        public
        returns (ConfigResolver resolver, AddressSubnameRegistrar registrar)
    {
        if (_isL2()) {
            revert(
                "AddressSubnameRegistrar requires ENS. Use deployConfigResolver() on L2."
            );
        }

        bytes32 parentNode = vm.envBytes32("PARENT_NODE");
        address ensRegistry = _getENSRegistry();
        address nameWrapper = _getNameWrapper();

        console.log("");
        console.log("==========================================");
        console.log("Deploying ConfigResolver + AddressSubnameRegistrar");
        console.log("==========================================");
        console.log("Network:", _getNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("ENS Registry:", ensRegistry);
        console.log("NameWrapper:", nameWrapper);
        console.log("Parent Node:", vm.toString(parentNode));
        console.log("");

        vm.startBroadcast();

        // Deploy ConfigResolver first
        resolver = new ConfigResolver(
            ENS(ensRegistry),
            INameWrapper(nameWrapper)
        );
        console.log("ConfigResolver deployed at:", address(resolver));

        // Deploy AddressSubnameRegistrar with ConfigResolver as default resolver
        registrar = new AddressSubnameRegistrar(
            ENS(ensRegistry),
            INameWrapper(nameWrapper),
            parentNode,
            address(resolver)
        );
        console.log("AddressSubnameRegistrar deployed at:", address(registrar));

        vm.stopBroadcast();

        _printNextSteps(
            parentNode,
            address(resolver),
            address(registrar),
            nameWrapper
        );
    }

    // ============ Deploy L1ConfigResolver (for CCIP-Read) ============

    /// @notice Deploy L1ConfigResolver for reading L2 records from L1
    /// @dev Requires L2_CONFIG_RESOLVER environment variable
    ///      Optional overrides: VERIFIER, L2_CHAIN_ID
    /// @return resolver The deployed L1ConfigResolver address
    function deployL1Resolver() public returns (L1ConfigResolver resolver) {
        address l2ConfigResolver = vm.envAddress("L2_CONFIG_RESOLVER");

        // Get verifier (env override or default for chain)
        address defaultVerifier = _getDefaultVerifier();
        address verifierAddr = vm.envOr("VERIFIER", defaultVerifier);
        require(
            verifierAddr != address(0),
            "VERIFIER required: no default for this chain"
        );
        IGatewayVerifier verifier = IGatewayVerifier(verifierAddr);

        // Get L2 chain ID (env override or default for chain)
        uint256 defaultL2ChainId = _getDefaultL2ChainId();
        uint256 l2ChainId = vm.envOr("L2_CHAIN_ID", defaultL2ChainId);
        require(
            l2ChainId != 0,
            "L2_CHAIN_ID required: no default for this chain"
        );

        console.log("");
        console.log("==========================================");
        console.log("Deploying L1ConfigResolver");
        console.log("==========================================");
        console.log("Network:", _getNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("Gateway Verifier:", verifierAddr);
        if (verifierAddr != defaultVerifier) {
            console.log("  (overridden via VERIFIER env var)");
        }
        console.log("L2 Chain ID:", l2ChainId);
        if (l2ChainId != defaultL2ChainId) {
            console.log("  (overridden via L2_CHAIN_ID env var)");
        }
        console.log("L2 ConfigResolver:", l2ConfigResolver);
        console.log("");

        vm.startBroadcast();
        resolver = new L1ConfigResolver(verifier, l2ChainId, l2ConfigResolver);
        vm.stopBroadcast();

        console.log("L1ConfigResolver deployed at:", address(resolver));
        console.log("");
    }

    // ============ Deploy L1 AddressSubnameRegistrar (for L1 claiming) ============

    /// @notice Deploy AddressSubnameRegistrar on L1 with L1ConfigResolver as default resolver
    /// @dev This allows users to claim subnames on L1 that resolve via CCIP-Read to L2 records
    ///      Requires PARENT_NODE and L1_CONFIG_RESOLVER environment variables
    /// @return registrar The deployed AddressSubnameRegistrar address
    function deployL1Registrar()
        public
        returns (AddressSubnameRegistrar registrar)
    {
        if (_isL2()) {
            revert(
                "AddressSubnameRegistrar for L1 claiming must be deployed on L1"
            );
        }

        bytes32 parentNode = vm.envBytes32("PARENT_NODE");
        address l1ConfigResolver = vm.envAddress("L1_CONFIG_RESOLVER");
        address ensRegistry = _getENSRegistry();
        address nameWrapper = _getNameWrapper();

        console.log("");
        console.log("==========================================");
        console.log("Deploying L1 AddressSubnameRegistrar");
        console.log("==========================================");
        console.log("Network:", _getNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("ENS Registry:", ensRegistry);
        console.log("NameWrapper:", nameWrapper);
        console.log("Parent Node:", vm.toString(parentNode));
        console.log("Default Resolver (L1ConfigResolver):", l1ConfigResolver);
        console.log("");

        vm.startBroadcast();
        registrar = new AddressSubnameRegistrar(
            ENS(ensRegistry),
            INameWrapper(nameWrapper),
            parentNode,
            l1ConfigResolver
        );
        vm.stopBroadcast();

        console.log("AddressSubnameRegistrar deployed at:", address(registrar));
        console.log("");

        _printL1RegistrarNextSteps(
            parentNode,
            l1ConfigResolver,
            address(registrar),
            nameWrapper
        );
    }

    // ============ Deploy Everything (L2 + L1) ============

    /// @notice Deploy all contracts: ConfigResolver, AddressSubnameRegistrar, and L1ConfigResolver
    /// @dev Requires PARENT_NODE and L2_CONFIG_RESOLVER environment variables
    ///      Note: L1ConfigResolver should typically be deployed on a different chain than ConfigResolver
    function deployEverything()
        public
        returns (
            ConfigResolver configResolver,
            AddressSubnameRegistrar registrar,
            L1ConfigResolver l1Resolver
        )
    {
        (configResolver, registrar) = deployAll();
        l1Resolver = deployL1Resolver();
    }

    // ============ Helper Functions ============

    function _printNextSteps(
        bytes32 parentNode,
        address resolver,
        address registrar,
        address nameWrapper
    ) internal pure {
        string memory rpcPlaceholder = "$RPC_URL";

        console.log("");
        console.log("==========================================");
        console.log("Next Steps");
        console.log("==========================================");
        console.log("");
        console.log("1. Set ConfigResolver as the resolver for your ENS name:");
        console.log("");
        console.log("   # If your name is WRAPPED:");
        console.log("   cast send", vm.toString(nameWrapper), "\\");
        console.log('     "setResolver(bytes32,address)" \\');
        console.log("    ", vm.toString(parentNode), "\\");
        console.log("    ", vm.toString(resolver), "\\");
        console.log("     --rpc-url", rpcPlaceholder, "--account <owner>");
        console.log("");
        console.log("   # If your name is UNWRAPPED:");
        console.log("   cast send", vm.toString(ENS_REGISTRY), "\\");
        console.log('     "setResolver(bytes32,address)" \\');
        console.log("    ", vm.toString(parentNode), "\\");
        console.log("    ", vm.toString(resolver), "\\");
        console.log("     --rpc-url", rpcPlaceholder, "--account <owner>");
        console.log("");
        console.log("2. Authorize the registrar to create subnames:");
        console.log("");
        console.log("   # If your name is WRAPPED:");
        console.log("   cast send", vm.toString(nameWrapper), "\\");
        console.log('     "setApprovalForAll(address,bool)" \\');
        console.log("    ", vm.toString(registrar), "true \\");
        console.log("     --rpc-url", rpcPlaceholder, "--account <owner>");
        console.log("");
        console.log("3. Users can now:");
        console.log("   - Set records via their reverse node");
        console.log("   - Claim their address subname via registrar.claim()");
        console.log("");
    }

    function _printL1RegistrarNextSteps(
        bytes32 parentNode,
        address l1ConfigResolver,
        address registrar,
        address nameWrapper
    ) internal pure {
        string memory rpcPlaceholder = "$RPC_URL";

        console.log("");
        console.log("==========================================");
        console.log("Next Steps (L1 Registrar with CCIP-Read)");
        console.log("==========================================");
        console.log("");
        console.log("1. Authorize the registrar to create subnames on L1:");
        console.log("");
        console.log("   # If your name is WRAPPED:");
        console.log("   cast send", vm.toString(nameWrapper), "\\");
        console.log('     "setApprovalForAll(address,bool)" \\');
        console.log("    ", vm.toString(registrar), "true \\");
        console.log("     --rpc-url", rpcPlaceholder, "--account <owner>");
        console.log("");
        console.log("2. Users can now:");
        console.log("   - Claim subnames on L1 via registrar.claim()");
        console.log("   - Subnames resolve via CCIP-Read to L2 records");
        console.log(
            "   - Users can change their resolver if desired (they own the ENS node)"
        );
        console.log("");
        console.log(
            "3. To set records, users interact with the L2 ConfigResolver"
        );
        console.log(
            "   - Records are stored on L2, read via CCIP-Read from L1"
        );
        console.log("");
        console.log("Default Resolver:", l1ConfigResolver);
        console.log("Registrar:", registrar);
        console.log("Parent Node:", vm.toString(parentNode));
        console.log("");
    }

    // ============ Default Entry Point ============

    /// @notice Default run function
    /// @dev On L2: deploys ConfigResolver only
    ///      On L1: deploys ConfigResolver + AddressSubnameRegistrar (requires PARENT_NODE)
    function run() external {
        // On L2, just deploy ConfigResolver
        if (_isL2()) {
            deployConfigResolver();
            return;
        }

        // On L1, check if PARENT_NODE is set
        try vm.envBytes32("PARENT_NODE") {
            deployAll();
        } catch {
            console.log("");
            console.log("ERROR: PARENT_NODE environment variable not set");
            console.log("");
            console.log("Usage:");
            console.log(
                '  PARENT_NODE=$(cast namehash "yourname.eth") forge script script/Deploy.s.sol \\'
            );
            console.log(
                "    --rpc-url $RPC_URL --account deployer --broadcast --verify"
            );
            console.log("");
            console.log("Or deploy ConfigResolver only:");
            console.log(
                '  forge script script/Deploy.s.sol --sig "deployConfigResolver()" \\'
            );
            console.log(
                "    --rpc-url $RPC_URL --account deployer --broadcast --verify"
            );
            console.log("");
            revert("PARENT_NODE not set");
        }
    }
}
