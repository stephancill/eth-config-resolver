// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {L1ConfigResolver} from "../src/L1ConfigResolver.sol";
import {IL1ConfigResolver} from "../src/IL1ConfigResolver.sol";
import {ConfigResolver} from "../src/ConfigResolver.sol";
import {ENS} from "@ensdomains/ens-contracts/registry/ENS.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";
import {IGatewayVerifier} from "@unruggable/contracts/IGatewayVerifier.sol";
import {
    GatewayRequest,
    GatewayOP
} from "@unruggable/contracts/GatewayRequest.sol";
import {GatewayFetcher} from "@unruggable/contracts/GatewayFetcher.sol";
import {
    GatewayFetchTarget,
    OffchainLookup
} from "@unruggable/contracts/GatewayFetchTarget.sol";

/// @title MockGatewayVerifier
/// @notice A mock verifier that returns pre-computed values for testing
contract MockGatewayVerifier is IGatewayVerifier {
    function getLatestContext() external view returns (bytes memory) {
        return abi.encode(block.number);
    }

    function gatewayURLs() external pure returns (string[] memory urls) {
        urls = new string[](1);
        urls[0] = "https://mock.gateway/";
    }

    /// @notice Returns values from the proof (which contains pre-computed values in tests)
    function getStorageValues(
        bytes memory,
        GatewayRequest memory,
        bytes memory proof
    ) external pure returns (bytes[] memory values, uint8 exitCode) {
        (values, exitCode) = abi.decode(proof, (bytes[], uint8));
    }
}

/// @title L1ConfigResolverTest
/// @notice End-to-end tests for L1ConfigResolver reading from ConfigResolver
contract L1ConfigResolverTest is Test {
    using GatewayFetcher for GatewayRequest;

    // Contracts
    ConfigResolver public configResolver;
    L1ConfigResolver public l1Resolver;
    MockGatewayVerifier public mockVerifier;

    // Test data
    address public user = address(0x1234567890123456789012345678901234567890);
    bytes32 public testNode;
    string public constant TEST_TEXT_KEY = "url";
    string public constant TEST_TEXT_VALUE = "https://example.com";
    uint256 public constant COIN_TYPE_ETH = 60;

    // Storage slot constants (must match L1ConfigResolver)
    uint256 constant SLOT_RECORD_VERSIONS = 0;
    uint256 constant SLOT_VERSIONABLE_ADDRESSES = 2;
    uint256 constant SLOT_VERSIONABLE_HASHES = 3;
    uint256 constant SLOT_VERSIONABLE_TEXTS = 10;

    function setUp() public {
        // Use mainnet addresses for ENS (they're the same on all networks)
        address ensRegistry = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
        address nameWrapper = 0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401;

        // Deploy ConfigResolver (L2) with mocked ENS
        configResolver = new ConfigResolver(
            ENS(ensRegistry),
            INameWrapper(nameWrapper)
        );

        // Deploy mock verifier
        mockVerifier = new MockGatewayVerifier();

        // Deploy L1ConfigResolver (using Base chain ID 8453 for testing)
        l1Resolver = new L1ConfigResolver(
            IGatewayVerifier(address(mockVerifier)),
            8453,
            address(configResolver)
        );

        // Set up test node (user's reverse node)
        testNode = configResolver.reverseNode(user);

        // Mock ENS to allow user to set records on their reverse node
        vm.mockCall(
            ensRegistry,
            abi.encodeWithSelector(ENS.owner.selector, testNode),
            abi.encode(user)
        );

        // Set up test data on ConfigResolver as user
        vm.startPrank(user);
        configResolver.setText(testNode, TEST_TEXT_KEY, TEST_TEXT_VALUE);
        configResolver.setAddr(testNode, user);
        configResolver.setContenthash(
            testNode,
            hex"e3010170122029f2d17be6139079dc48696d1f582a8530eb9805b561eda517e22a892c7e3f1f"
        );
        vm.stopPrank();
    }

    // ============ Helper to call fetchCallback and get result ============

    function _callFetchCallback(
        bytes memory proof,
        bytes memory carry
    ) internal view returns (bytes memory) {
        (bool success, bytes memory result) = address(l1Resolver).staticcall(
            abi.encodeWithSelector(
                l1Resolver.fetchCallback.selector,
                proof,
                carry
            )
        );
        require(success, "fetchCallback failed");
        return result;
    }

    // ============ Storage Slot Verification Tests ============

    /// @notice Verify that SLOT_RECORD_VERSIONS is correct (slot 0)
    function test_StorageSlot_RecordVersions() public view {
        bytes32 slot = keccak256(abi.encode(testNode, uint256(0)));
        uint256 version = uint256(vm.load(address(configResolver), slot));

        // After setting records, version should still be 0 (only incremented by clearRecords)
        assertEq(version, 0, "recordVersions should be at slot 0");
    }

    /// @notice Verify that SLOT_VERSIONABLE_ADDRESSES is correct (slot 2)
    function test_StorageSlot_VersionableAddresses() public view {
        // Storage layout: versionable_addresses[version][node][coinType]
        // Slot calculation: keccak256(coinType, keccak256(node, keccak256(version, baseSlot)))
        uint64 version = 0;
        uint256 baseSlot = 2;

        bytes32 slot1 = keccak256(abi.encode(version, baseSlot));
        bytes32 slot2 = keccak256(abi.encode(testNode, slot1));
        bytes32 slot3 = keccak256(abi.encode(COIN_TYPE_ETH, slot2));

        // Read the stored value - for short bytes (<32), Solidity stores data|length in same slot
        bytes32 storedValue = vm.load(address(configResolver), slot3);

        // For 20-byte address, Solidity stores: [20 bytes of data][11 zero bytes][1 byte = 2*20 = 40]
        // Extract the length from the lowest byte
        uint8 encodedLength = uint8(uint256(storedValue) & 0xff);
        // For short bytes, length is stored as 2*len, so actual length = encodedLength/2
        assertEq(
            encodedLength,
            40,
            "Address bytes length encoding should be 2*20=40"
        );

        // Extract the address from high bytes
        address storedAddr = address(uint160(uint256(storedValue) >> 96));
        assertEq(storedAddr, user, "Stored address should match user");
    }

    /// @notice Verify that SLOT_VERSIONABLE_TEXTS is correct (slot 10)
    function test_StorageSlot_VersionableTexts() public view {
        // Storage layout: versionable_texts[version][node][key]
        // For string keys in mappings, Solidity uses: keccak256(abi.encodePacked(key, slot))
        uint64 version = 0;
        uint256 baseSlot = 10;

        bytes32 slot1 = keccak256(abi.encode(version, baseSlot));
        bytes32 slot2 = keccak256(abi.encode(testNode, slot1));
        // For string keys, use encodePacked(key, slot)
        bytes32 slot3 = keccak256(abi.encodePacked(TEST_TEXT_KEY, slot2));

        // Read the stored value
        bytes32 storedValue = vm.load(address(configResolver), slot3);

        // For short strings (<32 bytes), Solidity stores: [string data][padding][2*length]
        // "https://example.com" is 19 bytes, so encoding = 2*19 = 38
        uint8 encodedLength = uint8(uint256(storedValue) & 0xff);
        assertEq(
            encodedLength,
            38,
            "Text record length encoding should be 2*19=38"
        );
    }

    /// @notice Verify that SLOT_VERSIONABLE_HASHES is correct (slot 3)
    function test_StorageSlot_VersionableHashes() public view {
        // Storage layout: versionable_hashes[version][node]
        uint64 version = 0;
        uint256 baseSlot = 3;

        bytes32 slot1 = keccak256(abi.encode(version, baseSlot));
        bytes32 slot2 = keccak256(abi.encode(testNode, slot1));

        // Read the stored contenthash length
        uint256 storedLength = uint256(vm.load(address(configResolver), slot2));
        // Our test contenthash is 38 bytes, stored as 2*38+1 = 77
        assertEq(
            storedLength,
            77,
            "Contenthash length encoding should be correct"
        );
    }

    // ============ Direct Read Tests (verify ConfigResolver data is set correctly) ============

    function test_ConfigResolver_DirectRead_Text() public view {
        string memory value = configResolver.text(testNode, TEST_TEXT_KEY);
        assertEq(value, TEST_TEXT_VALUE, "Text record should be set correctly");
    }

    function test_ConfigResolver_DirectRead_Addr() public view {
        address addr = configResolver.addr(testNode);
        assertEq(addr, user, "Address record should be set correctly");
    }

    function test_ConfigResolver_DirectRead_Contenthash() public view {
        bytes memory hash = configResolver.contenthash(testNode);
        assertEq(
            hash,
            hex"e3010170122029f2d17be6139079dc48696d1f582a8530eb9805b561eda517e22a892c7e3f1f",
            "Contenthash should be set correctly"
        );
    }

    // ============ CCIP-Read Flow Tests ============

    /// @notice Test the full CCIP-Read flow for text() resolution
    function test_CCIPRead_Text() public view {
        // Simulate gateway response by reading directly from ConfigResolver
        string memory expectedValue = configResolver.text(
            testNode,
            TEST_TEXT_KEY
        );

        // Prepare mock response
        bytes[] memory values = new bytes[](1);
        values[0] = bytes(expectedValue);
        bytes memory proof = abi.encode(values, uint8(0));

        // Build the carry data (Session struct)
        GatewayRequest memory req = _buildTextRequest(testNode, TEST_TEXT_KEY);
        bytes memory carry = abi.encode(
            GatewayFetchTarget.Session({
                verifier: IGatewayVerifier(address(mockVerifier)),
                context: mockVerifier.getLatestContext(),
                req: req,
                callback: L1ConfigResolver.textCallback.selector,
                carry: ""
            })
        );

        // Call fetchCallback
        bytes memory resultBytes = _callFetchCallback(proof, carry);
        string memory result = abi.decode(resultBytes, (string));

        assertEq(
            result,
            TEST_TEXT_VALUE,
            "CCIP-Read text() should return correct value"
        );
    }

    /// @notice Test the full CCIP-Read flow for addr() resolution
    function test_CCIPRead_Addr() public view {
        // Simulate gateway response
        bytes memory expectedValue = abi.encodePacked(user);

        bytes[] memory values = new bytes[](1);
        values[0] = expectedValue;
        bytes memory proof = abi.encode(values, uint8(0));

        // Build carry data
        GatewayRequest memory req = _buildAddrRequest(testNode, COIN_TYPE_ETH);
        bytes memory carry = abi.encode(
            GatewayFetchTarget.Session({
                verifier: IGatewayVerifier(address(mockVerifier)),
                context: mockVerifier.getLatestContext(),
                req: req,
                callback: L1ConfigResolver.addrCallback.selector,
                carry: abi.encode(testNode)
            })
        );

        // Call fetchCallback
        bytes memory resultBytes = _callFetchCallback(proof, carry);
        address result = abi.decode(resultBytes, (address));

        assertEq(
            result,
            user,
            "CCIP-Read addr() should return correct address"
        );
    }

    /// @notice Test the full CCIP-Read flow for contenthash() resolution
    function test_CCIPRead_Contenthash() public view {
        // Simulate gateway response
        bytes
            memory expectedValue = hex"e3010170122029f2d17be6139079dc48696d1f582a8530eb9805b561eda517e22a892c7e3f1f";

        bytes[] memory values = new bytes[](1);
        values[0] = expectedValue;
        bytes memory proof = abi.encode(values, uint8(0));

        // Build carry data
        GatewayRequest memory req = _buildContenthashRequest(testNode);
        bytes memory carry = abi.encode(
            GatewayFetchTarget.Session({
                verifier: IGatewayVerifier(address(mockVerifier)),
                context: mockVerifier.getLatestContext(),
                req: req,
                callback: L1ConfigResolver.contenthashCallback.selector,
                carry: ""
            })
        );

        // Call fetchCallback
        bytes memory resultBytes = _callFetchCallback(proof, carry);
        bytes memory result = abi.decode(resultBytes, (bytes));

        assertEq(
            result,
            expectedValue,
            "CCIP-Read contenthash() should return correct value"
        );
    }

    /// @notice Test resolve() with text selector
    function test_CCIPRead_Resolve_Text() public view {
        // Build the resolve calldata
        bytes memory innerCalldata = abi.encodeWithSelector(
            bytes4(0x59d1d43c),
            testNode,
            TEST_TEXT_KEY
        );

        // Simulate gateway response
        string memory expectedValue = configResolver.text(
            testNode,
            TEST_TEXT_KEY
        );
        bytes[] memory values = new bytes[](1);
        values[0] = bytes(expectedValue);
        bytes memory proof = abi.encode(values, uint8(0));

        // Build carry data
        GatewayRequest memory req = _buildTextRequest(testNode, TEST_TEXT_KEY);
        bytes memory carry = abi.encode(
            GatewayFetchTarget.Session({
                verifier: IGatewayVerifier(address(mockVerifier)),
                context: mockVerifier.getLatestContext(),
                req: req,
                callback: L1ConfigResolver.resolveCallback.selector,
                carry: innerCalldata
            })
        );

        // Call fetchCallback
        bytes memory resultBytes = _callFetchCallback(proof, carry);
        string memory decodedResult = abi.decode(
            abi.decode(resultBytes, (bytes)),
            (string)
        );

        assertEq(
            decodedResult,
            TEST_TEXT_VALUE,
            "resolve() with text selector should return correct value"
        );
    }

    /// @notice Test resolve() with addr selector
    function test_CCIPRead_Resolve_Addr() public view {
        // Build the resolve calldata for addr(bytes32)
        bytes memory innerCalldata = abi.encodeWithSelector(
            bytes4(0x3b3b57de),
            testNode
        );

        // Simulate gateway response
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encodePacked(user);
        bytes memory proof = abi.encode(values, uint8(0));

        // Build carry data
        GatewayRequest memory req = _buildAddrRequest(testNode, COIN_TYPE_ETH);
        bytes memory carry = abi.encode(
            GatewayFetchTarget.Session({
                verifier: IGatewayVerifier(address(mockVerifier)),
                context: mockVerifier.getLatestContext(),
                req: req,
                callback: L1ConfigResolver.resolveCallback.selector,
                carry: innerCalldata
            })
        );

        // Call fetchCallback
        bytes memory resultBytes = _callFetchCallback(proof, carry);
        address decodedResult = abi.decode(
            abi.decode(resultBytes, (bytes)),
            (address)
        );

        assertEq(
            decodedResult,
            user,
            "resolve() with addr selector should return correct address"
        );
    }

    // ============ Empty/Missing Record Tests ============

    function test_CCIPRead_EmptyText() public view {
        bytes32 emptyNode = keccak256("nonexistent");

        bytes[] memory values = new bytes[](1);
        values[0] = "";
        bytes memory proof = abi.encode(values, uint8(0));

        GatewayRequest memory req = _buildTextRequest(emptyNode, "nonexistent");
        bytes memory carry = abi.encode(
            GatewayFetchTarget.Session({
                verifier: IGatewayVerifier(address(mockVerifier)),
                context: mockVerifier.getLatestContext(),
                req: req,
                callback: L1ConfigResolver.textCallback.selector,
                carry: ""
            })
        );

        bytes memory resultBytes = _callFetchCallback(proof, carry);
        string memory result = abi.decode(resultBytes, (string));
        assertEq(result, "", "Empty text record should return empty string");
    }

    function test_CCIPRead_EmptyAddr() public view {
        bytes[] memory values = new bytes[](1);
        values[0] = "";
        bytes memory proof = abi.encode(values, uint8(0));

        GatewayRequest memory req = _buildAddrRequest(testNode, COIN_TYPE_ETH);
        bytes memory carry = abi.encode(
            GatewayFetchTarget.Session({
                verifier: IGatewayVerifier(address(mockVerifier)),
                context: mockVerifier.getLatestContext(),
                req: req,
                callback: L1ConfigResolver.addrCallback.selector,
                carry: ""
            })
        );

        bytes memory resultBytes = _callFetchCallback(proof, carry);
        address result = abi.decode(resultBytes, (address));
        assertEq(
            result,
            address(0),
            "Empty address record should return zero address"
        );
    }

    /// @notice Test exit code handling
    function test_CCIPRead_ExitCode_NonZero() public view {
        bytes[] memory values = new bytes[](1);
        values[0] = "";
        // Non-zero exit code indicates error/not found
        bytes memory proof = abi.encode(values, uint8(1));

        GatewayRequest memory req = _buildTextRequest(testNode, TEST_TEXT_KEY);
        bytes memory carry = abi.encode(
            GatewayFetchTarget.Session({
                verifier: IGatewayVerifier(address(mockVerifier)),
                context: mockVerifier.getLatestContext(),
                req: req,
                callback: L1ConfigResolver.textCallback.selector,
                carry: ""
            })
        );

        bytes memory resultBytes = _callFetchCallback(proof, carry);
        string memory result = abi.decode(resultBytes, (string));
        assertEq(
            result,
            "",
            "Non-zero exit code should return empty string for text"
        );
    }

    // ============ Interface Support Tests ============

    function test_SupportsInterface_ERC165() public view {
        assertTrue(
            l1Resolver.supportsInterface(0x01ffc9a7),
            "Should support ERC-165"
        );
    }

    function test_SupportsInterface_ExtendedResolver() public view {
        assertTrue(
            l1Resolver.supportsInterface(0x9061b923),
            "Should support IExtendedResolver"
        );
    }

    function test_SupportsInterface_Addr() public view {
        assertTrue(
            l1Resolver.supportsInterface(0x3b3b57de),
            "Should support addr(bytes32)"
        );
    }

    function test_SupportsInterface_AddrMulti() public view {
        assertTrue(
            l1Resolver.supportsInterface(0xf1cb7e06),
            "Should support addr(bytes32,uint256)"
        );
    }

    function test_SupportsInterface_Text() public view {
        assertTrue(
            l1Resolver.supportsInterface(0x59d1d43c),
            "Should support text(bytes32,string)"
        );
    }

    function test_SupportsInterface_Contenthash() public view {
        assertTrue(
            l1Resolver.supportsInterface(0xbc1c58d1),
            "Should support contenthash(bytes32)"
        );
    }

    // ============ Immutable Getters Tests ============

    function test_Verifier() public view {
        assertEq(
            address(l1Resolver.verifier()),
            address(mockVerifier),
            "Verifier should be set correctly"
        );
    }

    function test_L2ConfigResolver() public view {
        assertEq(
            l1Resolver.l2ConfigResolver(),
            address(configResolver),
            "L2 ConfigResolver should be set correctly"
        );
    }

    function test_L2ChainId() public view {
        assertEq(
            l1Resolver.l2ChainId(),
            8453,
            "L2 Chain ID should be set correctly"
        );
    }

    function test_SupportsInterface_IL1ConfigResolver() public view {
        // IL1ConfigResolver interface ID
        bytes4 interfaceId = type(IL1ConfigResolver).interfaceId;
        assertTrue(
            l1Resolver.supportsInterface(interfaceId),
            "Should support IL1ConfigResolver"
        );
    }

    // ============ Helper Functions ============

    function _buildTextRequest(
        bytes32 node,
        string memory key
    ) internal view returns (GatewayRequest memory req) {
        req = GatewayFetcher.newRequest(1).setTarget(address(configResolver));
        req = req.setSlot(SLOT_RECORD_VERSIONS).push(node).follow().read();
        req = req.setSlot(SLOT_VERSIONABLE_TEXTS);
        req = req.follow();
        req = req.push(node).follow();
        req = req.push(key).follow();
        req = req.readBytes().setOutput(0);
    }

    function _buildAddrRequest(
        bytes32 node,
        uint256 coinType
    ) internal view returns (GatewayRequest memory req) {
        req = GatewayFetcher.newRequest(1).setTarget(address(configResolver));
        req = req.setSlot(SLOT_RECORD_VERSIONS).push(node).follow().read();
        req = req.setSlot(SLOT_VERSIONABLE_ADDRESSES);
        req = req.follow();
        req = req.push(node).follow();
        req = req.push(coinType).follow();
        req = req.readBytes().setOutput(0);
    }

    function _buildContenthashRequest(
        bytes32 node
    ) internal view returns (GatewayRequest memory req) {
        req = GatewayFetcher.newRequest(1).setTarget(address(configResolver));
        req = req.setSlot(SLOT_RECORD_VERSIONS).push(node).follow().read();
        req = req.setSlot(SLOT_VERSIONABLE_HASHES);
        req = req.follow();
        req = req.push(node).follow();
        req = req.readBytes().setOutput(0);
    }
}
