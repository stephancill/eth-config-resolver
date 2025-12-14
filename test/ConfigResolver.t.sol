// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ConfigResolver} from "../src/ConfigResolver.sol";
import {ENSRegistry} from "@ensdomains/ens-contracts/registry/ENSRegistry.sol";
import {ENS} from "@ensdomains/ens-contracts/registry/ENS.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";
import {ReverseRegistrar} from "@ensdomains/ens-contracts/reverseRegistrar/ReverseRegistrar.sol";

contract ConfigResolverTest is Test {
    ENSRegistry public ens;
    ReverseRegistrar public reverseRegistrar;
    ConfigResolver public resolver;
    INameWrapper public nameWrapper;

    address public alice = address(0x1);
    address public bob = address(0x2);

    bytes32 constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

    function setUp() public {
        // Deploy ENS registry
        ens = new ENSRegistry();

        // Set up the reverse registrar structure:
        // 1. Create "reverse" subdomain under root
        bytes32 zeroHash = bytes32(0);
        bytes32 reverseLabelHash = keccak256(bytes("reverse"));
        ens.setSubnodeOwner(zeroHash, reverseLabelHash, address(this));

        // 2. Deploy ReverseRegistrar
        reverseRegistrar = new ReverseRegistrar(ens);

        // 3. Create "addr" subdomain under "reverse" (this creates ADDR_REVERSE_NODE)
        //    and set ReverseRegistrar as the owner
        bytes32 reverseNode = keccak256(abi.encodePacked(zeroHash, reverseLabelHash));
        bytes32 addrLabelHash = keccak256(bytes("addr"));
        ens.setSubnodeOwner(reverseNode, addrLabelHash, address(reverseRegistrar));

        // 4. Deploy ConfigResolver with address(0) for nameWrapper (not needed for basic tests)
        //    The ReverseClaimer in ConfigResolver will try to claim the reverse node,
        //    but since we're the deployer, it should work
        resolver = new ConfigResolver(ens, INameWrapper(address(0)));

        // 5. Set up alice's reverse node using ReverseRegistrar
        //    We need to use the ReverseRegistrar to claim it since it owns ADDR_REVERSE_NODE
        vm.prank(alice);
        reverseRegistrar.claimForAddr(alice, alice, address(resolver));
    }

    function test_AccountCanSetTextRecordForOwnReverseNode() public {
        bytes32 reverseNode = resolver.reverseNode(alice);

        // Switch to alice's context
        vm.prank(alice);

        // Set a text record
        string memory key = "url";
        string memory value = "https://example.com";
        resolver.setText(reverseNode, key, value);

        // Verify the text record was set
        string memory retrievedValue = resolver.text(reverseNode, key);
        assertEq(retrievedValue, value);
    }

    function test_AccountCannotSetTextRecordForOtherReverseNode() public {
        bytes32 aliceReverseNode = resolver.reverseNode(alice);

        // Switch to bob's context
        vm.prank(bob);

        // Try to set a text record for alice's reverse node - should fail
        string memory key = "url";
        string memory value = "https://malicious.com";
        vm.expectRevert();
        resolver.setText(aliceReverseNode, key, value);
    }

    function test_MultipleAccountsCanSetTextRecordsForTheirOwnReverseNodes() public {
        // Set up bob's reverse node using ReverseRegistrar
        vm.prank(bob);
        bytes32 bobReverseNode = reverseRegistrar.claimForAddr(bob, bob, address(resolver));

        // Alice sets her text record
        bytes32 aliceReverseNode = resolver.reverseNode(alice);
        vm.prank(alice);
        resolver.setText(aliceReverseNode, "url", "https://alice.com");

        // Bob sets his text record
        vm.prank(bob);
        resolver.setText(bobReverseNode, "url", "https://bob.com");

        // Verify both records are set correctly
        assertEq(resolver.text(aliceReverseNode, "url"), "https://alice.com");
        assertEq(resolver.text(bobReverseNode, "url"), "https://bob.com");
    }

    function test_AccountCanSetMultipleTextRecords() public {
        bytes32 reverseNode = resolver.reverseNode(alice);

        vm.prank(alice);
        resolver.setText(reverseNode, "url", "https://example.com");

        vm.prank(alice);
        resolver.setText(reverseNode, "email", "alice@example.com");

        vm.prank(alice);
        resolver.setText(reverseNode, "description", "Alice's profile");

        // Verify all records
        assertEq(resolver.text(reverseNode, "url"), "https://example.com");
        assertEq(resolver.text(reverseNode, "email"), "alice@example.com");
        assertEq(resolver.text(reverseNode, "description"), "Alice's profile");
    }

    // Helper function to compute sha3 of hex address (same as in ReverseRegistrar)
    function sha3HexAddress(address addr) private pure returns (bytes32 ret) {
        bytes32 lookup = 0x3031323334353637383961626364656600000000000000000000000000000000;
        assembly {
            for {
                let i := 40
            } gt(i, 0) {} {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
            }

            ret := keccak256(0, 40)
        }
    }
}
