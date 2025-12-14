// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17 <0.9.0;

import {Script, console} from "forge-std/Script.sol";
import {AddressSubnameRegistrar} from "../src/AddressSubnameRegistrar.sol";
import {ENS} from "@ensdomains/ens-contracts/registry/ENS.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";

contract DeployAddressSubnameRegistrar is Script {
    // ENS Registry is the same on all networks
    address constant ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

    // Sepolia testnet addresses
    address constant SEPOLIA_NAME_WRAPPER = 0x0635513f179D50A207757E05759CbD106d7dFcE8;

    // Mainnet addresses
    address constant MAINNET_NAME_WRAPPER = 0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401;

    function run() external {
        // Load configuration from environment
        bytes32 parentNode = vm.envBytes32("PARENT_NODE");
        address defaultResolver = vm.envAddress("DEFAULT_RESOLVER");

        // Get chain ID to determine which network we're on
        uint256 chainId = block.chainid;
        address nameWrapper;

        if (chainId == 11155111) {
            // Sepolia
            nameWrapper = SEPOLIA_NAME_WRAPPER;
            console.log("Deploying to Sepolia testnet");
        } else if (chainId == 1) {
            // Mainnet
            nameWrapper = MAINNET_NAME_WRAPPER;
            console.log("Deploying to Ethereum mainnet");
        } else {
            revert("Unsupported chain. Use Sepolia (11155111) or Mainnet (1)");
        }

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy AddressSubnameRegistrar
        AddressSubnameRegistrar registrar =
            new AddressSubnameRegistrar(ENS(ENS_REGISTRY), INameWrapper(nameWrapper), parentNode, defaultResolver);

        vm.stopBroadcast();

        // Log deployment information
        console.log("AddressSubnameRegistrar deployed at:", address(registrar));
        console.log("ENS Registry:", ENS_REGISTRY);
        console.log("NameWrapper:", nameWrapper);
        console.log("Parent Node:", vm.toString(parentNode));
        console.log("Default Resolver:", defaultResolver);
        console.log("Chain ID:", chainId);
    }
}
