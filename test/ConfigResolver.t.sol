// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ConfigResolver} from "../src/ConfigResolver.sol";
import {ENSRegistry} from "@ensdomains/ens-contracts/registry/ENSRegistry.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";
import {ReverseRegistrar} from "@ensdomains/ens-contracts/reverseRegistrar/ReverseRegistrar.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/resolvers/profiles/IAddrResolver.sol";
import {ITextResolver} from "@ensdomains/ens-contracts/resolvers/profiles/ITextResolver.sol";

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

    // ============ Wildcard Resolution Tests (ENSIP-10) ============

    function test_SupportsExtendedResolverInterface() public view {
        // 0x9061b923 is the interface ID for IExtendedResolver
        assertTrue(resolver.supportsInterface(0x9061b923));
    }

    function test_WildcardResolveAddr() public view {
        // Test resolving addr() for an unclaimed subname
        // DNS-encoded name: \x28<40-char-hex>\x06parent\x03eth\x00
        // For simplicity, we'll use alice's address

        // Build DNS-encoded name for alice's address under "test.eth"
        bytes memory dnsName = _buildDnsName(alice, "test", "eth");

        // Build the addr(bytes32) call data
        bytes memory data = abi.encodeWithSelector(IAddrResolver.addr.selector, bytes32(0));

        // Call resolve
        bytes memory result = resolver.resolve(dnsName, data);

        // Decode and verify
        address resolved = abi.decode(result, (address));
        assertEq(resolved, alice);
    }

    function test_WildcardResolveText() public {
        // First, set a text record using alice's reverse node
        // (text records are stored under the reverse node and looked up via wildcard)
        bytes32 aliceReverseNode = resolver.reverseNode(alice);

        // Alice sets the text record (she's authorized via reverseNode check)
        vm.prank(alice);
        resolver.setText(aliceReverseNode, "url", "https://alice.example.com");

        // Now resolve via wildcard - should find the same record
        bytes memory dnsName = _buildDnsName(alice, "test", "eth");
        bytes memory data = abi.encodeWithSelector(
            ITextResolver.text.selector,
            bytes32(0), // node (ignored, computed from name)
            "url"
        );

        bytes memory result = resolver.resolve(dnsName, data);
        string memory value = abi.decode(result, (string));
        assertEq(value, "https://alice.example.com");
    }

    function test_WildcardResolveEmptyText() public view {
        // Test resolving text for a key that hasn't been set
        // (bob hasn't set any records)
        bytes memory dnsName = _buildDnsName(bob, "test", "eth");

        bytes memory data = abi.encodeWithSelector(ITextResolver.text.selector, bytes32(0), "nonexistent");

        bytes memory result = resolver.resolve(dnsName, data);
        string memory value = abi.decode(result, (string));
        assertEq(value, "");
    }

    function test_WildcardTextSharedAcrossParents() public {
        // Verify that text records are shared across different parent names
        bytes32 aliceReverseNode = resolver.reverseNode(alice);

        // Alice sets the text record once
        vm.prank(alice);
        resolver.setText(aliceReverseNode, "url", "https://alice.example.com");

        // Should resolve under different parents
        bytes memory dnsName1 = _buildDnsName(alice, "parent1", "eth");
        bytes memory dnsName2 = _buildDnsName(alice, "parent2", "eth");

        bytes memory data = abi.encodeWithSelector(ITextResolver.text.selector, bytes32(0), "url");

        bytes memory result1 = resolver.resolve(dnsName1, data);
        bytes memory result2 = resolver.resolve(dnsName2, data);

        assertEq(abi.decode(result1, (string)), "https://alice.example.com");
        assertEq(abi.decode(result2, (string)), "https://alice.example.com");
    }

    function test_StandardResolutionForNonWildcardNames() public {
        // Test that non-40-char labels fall back to standard resolution
        // This is the key fix: resolving names like "ethconfig.eth" should work

        // ENS namehash is computed as: keccak256(namehash(parent) + keccak256(label))
        // For "test.eth": first compute "eth" node, then "test.eth" node
        bytes32 ethNode = keccak256(abi.encodePacked(bytes32(0), keccak256("eth")));
        bytes32 testNode = keccak256(abi.encodePacked(ethNode, keccak256("test")));

        // Set the owner of the nodes so we can set records
        ens.setSubnodeOwner(bytes32(0), keccak256("eth"), address(this));
        ens.setSubnodeOwner(ethNode, keccak256("test"), address(this));

        // Set a text record directly using the standard resolver function
        resolver.setText(testNode, "url", "https://test.example.com");

        // Now resolve via the resolve() function (simulating ENSIP-10 query)
        // DNS-encoded name: \x04test\x03eth\x00
        bytes memory dnsName = hex"0474657374036574680000";
        bytes memory data = abi.encodeWithSelector(ITextResolver.text.selector, testNode, "url");

        bytes memory result = resolver.resolve(dnsName, data);
        string memory value = abi.decode(result, (string));
        assertEq(value, "https://test.example.com");
    }

    function test_StandardResolutionForContentHash() public {
        // Test that contenthash resolution works for parent domains

        // Create a test node
        bytes32 ethNode = keccak256(abi.encodePacked(bytes32(0), keccak256("eth")));
        ens.setSubnodeOwner(bytes32(0), keccak256("eth"), address(this));
        bytes32 testNode = keccak256(abi.encodePacked(ethNode, keccak256("myname")));
        ens.setSubnodeOwner(ethNode, keccak256("myname"), address(this));

        // Set a content hash
        bytes memory contentHash = hex"e301017012208086c3967b9eaa618bb2877c4ebe1e67c8305d0d2b4dc8698cebc9a2f565a933";
        resolver.setContenthash(testNode, contentHash);

        // Resolve via the resolve() function
        // DNS-encoded name: \x06myname\x03eth\x00
        bytes memory dnsName = hex"066d796e616d65036574680000";
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("contenthash(bytes32)")), testNode);

        bytes memory result = resolver.resolve(dnsName, data);
        bytes memory decoded = abi.decode(result, (bytes));
        assertEq(decoded, contentHash);
    }

    function test_NonWildcardNameWithNoDataReturnsEmpty() public view {
        // Test with a non-40-char label that has no data set
        // Should not revert, should return empty/zero data
        bytes memory dnsName = hex"0a6162636465666768696a03657468"; // 10-char label "abcdefghij"
        bytes32 someNode = bytes32(0);
        bytes memory data = abi.encodeWithSelector(IAddrResolver.addr.selector, someNode);

        // Should not revert - falls back to standard resolution
        bytes memory result = resolver.resolve(dnsName, data);
        address resolved = abi.decode(result, (address));
        assertEq(resolved, address(0)); // No address set, returns zero
    }

    function test_WildcardResolveInvalidHex() public {
        // Test with invalid hex characters (42 chars with 0x prefix but invalid hex after)
        // "0xzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz" - 0x + 40 z's
        bytes memory invalidName =
            hex"2a30787a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a04746573740365746800";
        bytes memory data = abi.encodeWithSelector(IAddrResolver.addr.selector, bytes32(0));

        vm.expectRevert("Invalid hex address");
        resolver.resolve(invalidName, data);
    }

    function test_WildcardResolveChecksummedAddress() public {
        // Test that checksummed (mixed case) addresses resolve correctly
        // Using a well-known checksummed address format
        address testAddr = 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B;

        // Build DNS name with checksummed address (mixed case)
        bytes memory checksummedName = _buildDnsNameWithChecksummedAddress(testAddr, "test", "eth");

        // Build the addr(bytes32) call data
        bytes memory data = abi.encodeWithSelector(IAddrResolver.addr.selector, bytes32(0));

        // Call resolve - should work with checksummed address
        bytes memory result = resolver.resolve(checksummedName, data);

        // Decode and verify
        address resolved = abi.decode(result, (address));
        assertEq(resolved, testAddr);
    }

    function test_WildcardResolveChecksummedAndLowercaseReturnSameResult() public {
        // Verify that both checksummed and lowercase addresses resolve to the same result
        address testAddr = 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B;

        // Set up a text record for this address
        bytes32 addrReverseNode = resolver.reverseNode(testAddr);

        // We need to give testAddr ownership of their reverse node
        vm.prank(testAddr);
        reverseRegistrar.claimForAddr(testAddr, testAddr, address(resolver));

        vm.prank(testAddr);
        resolver.setText(addrReverseNode, "url", "https://vitalik.example.com");

        // Build DNS names with both formats
        bytes memory lowercaseName = _buildDnsName(testAddr, "test", "eth");
        bytes memory checksummedName = _buildDnsNameWithChecksummedAddress(testAddr, "test", "eth");

        bytes memory textData = abi.encodeWithSelector(ITextResolver.text.selector, bytes32(0), "url");

        // Both should return the same text record
        bytes memory result1 = resolver.resolve(lowercaseName, textData);
        bytes memory result2 = resolver.resolve(checksummedName, textData);

        assertEq(abi.decode(result1, (string)), "https://vitalik.example.com");
        assertEq(abi.decode(result2, (string)), "https://vitalik.example.com");

        // Both should also return the same address
        bytes memory addrData = abi.encodeWithSelector(IAddrResolver.addr.selector, bytes32(0));

        bytes memory addrResult1 = resolver.resolve(lowercaseName, addrData);
        bytes memory addrResult2 = resolver.resolve(checksummedName, addrData);

        assertEq(abi.decode(addrResult1, (address)), testAddr);
        assertEq(abi.decode(addrResult2, (address)), testAddr);
    }

    function test_WildcardResolveUppercaseAddress() public view {
        // Test with fully uppercase address (another edge case)
        address testAddr = 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B;

        // Build DNS name with uppercase address
        bytes memory uppercaseName = _buildDnsNameWithUppercaseAddress(testAddr, "test", "eth");

        // Build the addr(bytes32) call data
        bytes memory data = abi.encodeWithSelector(IAddrResolver.addr.selector, bytes32(0));

        // Call resolve - should work with uppercase address
        bytes memory result = resolver.resolve(uppercaseName, data);

        // Decode and verify
        address resolved = abi.decode(result, (address));
        assertEq(resolved, testAddr);
    }

    // Helper to build DNS-encoded name for 0xaddress.parent.tld
    function _buildDnsName(address addr, string memory parent, string memory tld) private pure returns (bytes memory) {
        bytes memory hexAddr = _addressToHexBytes(addr);
        bytes memory parentBytes = bytes(parent);
        bytes memory tldBytes = bytes(tld);

        // Format: \x2a<42-char-hex-with-0x>\x<parent-len><parent>\x<tld-len><tld>\x00
        return abi.encodePacked(
            uint8(42), hexAddr, uint8(parentBytes.length), parentBytes, uint8(tldBytes.length), tldBytes, uint8(0)
        );
    }

    // Helper to convert address to lowercase hex bytes (42 chars, with 0x prefix)
    function _addressToHexBytes(address addr) private pure returns (bytes memory) {
        bytes memory result = new bytes(42);
        bytes memory hexChars = "0123456789abcdef";

        result[0] = "0";
        result[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(uint160(addr) >> (8 * (19 - i)));
            result[2 + i * 2] = hexChars[b >> 4];
            result[2 + i * 2 + 1] = hexChars[b & 0x0f];
        }

        return result;
    }

    // Helper to build DNS-encoded name with checksummed address
    function _buildDnsNameWithChecksummedAddress(address addr, string memory parent, string memory tld)
        private
        pure
        returns (bytes memory)
    {
        bytes memory hexAddr = _addressToChecksummedHexBytes(addr);
        bytes memory parentBytes = bytes(parent);
        bytes memory tldBytes = bytes(tld);

        return abi.encodePacked(
            uint8(42), hexAddr, uint8(parentBytes.length), parentBytes, uint8(tldBytes.length), tldBytes, uint8(0)
        );
    }

    // Helper to build DNS-encoded name with uppercase address
    function _buildDnsNameWithUppercaseAddress(address addr, string memory parent, string memory tld)
        private
        pure
        returns (bytes memory)
    {
        bytes memory hexAddr = _addressToUppercaseHexBytes(addr);
        bytes memory parentBytes = bytes(parent);
        bytes memory tldBytes = bytes(tld);

        return abi.encodePacked(
            uint8(42), hexAddr, uint8(parentBytes.length), parentBytes, uint8(tldBytes.length), tldBytes, uint8(0)
        );
    }

    // Helper to convert address to checksummed hex bytes (EIP-55) with 0x prefix
    function _addressToChecksummedHexBytes(address addr) private pure returns (bytes memory) {
        bytes memory result = new bytes(42);
        bytes memory hexCharsLower = "0123456789abcdef";

        result[0] = "0";
        result[1] = "x";

        // First, create lowercase hex string (without 0x for hashing)
        bytes memory lowercase = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(uint160(addr) >> (8 * (19 - i)));
            lowercase[i * 2] = hexCharsLower[b >> 4];
            lowercase[i * 2 + 1] = hexCharsLower[b & 0x0f];
        }

        // Hash the lowercase address for checksum
        bytes32 hash = keccak256(lowercase);

        // Apply checksum (EIP-55)
        for (uint256 i = 0; i < 40; i++) {
            uint8 hashNibble = uint8(hash[i / 2]);
            if (i % 2 == 0) {
                hashNibble = hashNibble >> 4;
            } else {
                hashNibble = hashNibble & 0x0f;
            }

            uint8 charCode = uint8(lowercase[i]);
            // If it's a letter (a-f) and hash nibble >= 8, uppercase it
            if (charCode >= 97 && charCode <= 102 && hashNibble >= 8) {
                result[2 + i] = bytes1(charCode - 32); // Convert to uppercase
            } else {
                result[2 + i] = lowercase[i];
            }
        }

        return result;
    }

    // Helper to convert address to uppercase hex bytes (42 chars, with 0x prefix)
    function _addressToUppercaseHexBytes(address addr) private pure returns (bytes memory) {
        bytes memory result = new bytes(42);
        bytes memory hexChars = "0123456789ABCDEF";

        result[0] = "0";
        result[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(uint160(addr) >> (8 * (19 - i)));
            result[2 + i * 2] = hexChars[b >> 4];
            result[2 + i * 2 + 1] = hexChars[b & 0x0f];
        }

        return result;
    }
}
