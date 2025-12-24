// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {AddressSubnameRegistrar} from "../src/AddressSubnameRegistrar.sol";
import {ConfigResolver} from "../src/ConfigResolver.sol";
import {ENSRegistry} from "@ensdomains/ens-contracts/registry/ENSRegistry.sol";
import {ENS} from "@ensdomains/ens-contracts/registry/ENS.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";

contract AddressSubnameRegistrarTest is Test {
    ENSRegistry public ens;
    ConfigResolver public resolver;
    AddressSubnameRegistrar public registrar;

    address public alice = address(0x8d25687829D6b85d9e0020B8c89e3Ca24dE20a89);
    address public bob = address(0x2);
    address public deployer = address(this);

    // namehash("eth")
    bytes32 constant ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;
    // namehash("ethconfig.eth") - you'd compute this properly
    bytes32 public ethconfigNode;

    function setUp() public {
        // Deploy ENS registry
        ens = new ENSRegistry();

        // Deploy ConfigResolver (will be used as default resolver)
        resolver = new ConfigResolver(ens, INameWrapper(address(0)));

        // Set up "eth" TLD owned by deployer
        bytes32 ethLabelHash = keccak256(bytes("eth"));
        ens.setSubnodeOwner(bytes32(0), ethLabelHash, deployer);

        // Set up "ethconfig.eth" owned by deployer
        bytes32 ethconfigLabelHash = keccak256(bytes("ethconfig"));
        ens.setSubnodeOwner(ETH_NODE, ethconfigLabelHash, deployer);
        ethconfigNode = keccak256(abi.encodePacked(ETH_NODE, ethconfigLabelHash));

        // Deploy the AddressSubnameRegistrar
        registrar = new AddressSubnameRegistrar(
            ens,
            INameWrapper(address(0)), // No wrapper for this test
            ethconfigNode,
            address(resolver)
        );

        // Transfer ownership of ethconfig.eth to the registrar
        // So it can create subnames
        ens.setOwner(ethconfigNode, address(registrar));
    }

    function test_UserCanClaimTheirAddressSubname() public {
        // Alice claims her subname
        vm.prank(alice);
        bytes32 node = registrar.claim();

        // Verify the subname was created
        assertEq(ens.owner(node), alice);
        assertEq(ens.resolver(node), address(resolver));

        // Log the label for verification
        string memory label = registrar.getLabel(alice);
        console.log("Alice's subname label:", label);
        // Should be: 8d25687829d6b85d9e0020b8c89e3ca24de20a89
    }

    function test_LabelIsNormalizedLowercase() public {
        // The address 0x8d25687829D6b85d9e0020B8c89e3Ca24dE20a89
        // should produce label: 8d25687829d6b85d9e0020b8c89e3ca24de20a89
        string memory label = registrar.getLabel(alice);
        assertEq(label, "8d25687829d6b85d9e0020b8c89e3ca24de20a89");
    }

    function test_CannotClaimSameSubnameTwice() public {
        // Alice claims her subname
        vm.prank(alice);
        registrar.claim();

        // Alice tries to claim again - should fail
        vm.prank(alice);
        vm.expectRevert(AddressSubnameRegistrar.AlreadyClaimed.selector);
        registrar.claim();
    }

    function test_CannotClaimForSomeoneElse() public {
        // Bob tries to claim Alice's subname
        vm.prank(bob);
        vm.expectRevert(AddressSubnameRegistrar.Unauthorized.selector);
        registrar.claimForAddr(alice, bob);
    }

    function test_CanClaimForApprovedAddress() public {
        // Alice approves Bob
        vm.prank(alice);
        ens.setApprovalForAll(bob, true);

        // Bob claims for Alice
        vm.prank(bob);
        bytes32 node = registrar.claimForAddr(alice, alice);

        // Verify Alice owns it
        assertEq(ens.owner(node), alice);
    }

    function test_CheckAvailability() public {
        // Should be available
        assertTrue(registrar.available(alice));

        // Alice claims
        vm.prank(alice);
        registrar.claim();

        // Should no longer be available
        assertFalse(registrar.available(alice));
    }

    function test_UserCanSetRecordsAfterClaiming() public {
        // Alice claims her subname
        vm.prank(alice);
        bytes32 node = registrar.claim();

        // Alice sets a text record on her subname
        vm.prank(alice);
        resolver.setText(node, "url", "https://alice.com");

        // Verify
        assertEq(resolver.text(node, "url"), "https://alice.com");
    }

    function test_MultipleUsersClaim() public {
        // Alice claims
        vm.prank(alice);
        bytes32 aliceNode = registrar.claim();

        // Bob claims
        vm.prank(bob);
        bytes32 bobNode = registrar.claim();

        // Both should own their subnames
        assertEq(ens.owner(aliceNode), alice);
        assertEq(ens.owner(bobNode), bob);

        // Nodes should be different
        assertTrue(aliceNode != bobNode);
    }
}

