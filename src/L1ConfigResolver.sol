// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    GatewayFetcher,
    GatewayRequest
} from "@unruggable/contracts/GatewayFetcher.sol";
import {GatewayFetchTarget} from "@unruggable/contracts/GatewayFetchTarget.sol";
import {IGatewayVerifier} from "@unruggable/contracts/IGatewayVerifier.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// ENS Resolver Interfaces
import {
    IAddrResolver
} from "@ensdomains/ens-contracts/resolvers/profiles/IAddrResolver.sol";
import {
    IAddressResolver
} from "@ensdomains/ens-contracts/resolvers/profiles/IAddressResolver.sol";
import {
    ITextResolver
} from "@ensdomains/ens-contracts/resolvers/profiles/ITextResolver.sol";
import {
    IContentHashResolver
} from "@ensdomains/ens-contracts/resolvers/profiles/IContentHashResolver.sol";
import {
    IExtendedResolver
} from "@ensdomains/ens-contracts/resolvers/profiles/IExtendedResolver.sol";
import {IL1ConfigResolver} from "./IL1ConfigResolver.sol";

/// @title L1ConfigResolver
/// @notice An L1 resolver that reads ENS records from the ConfigResolver deployed on L2 (Base)
/// @dev Uses CCIP-Read (EIP-3668) via Unruggable Gateways to trustlessly read L2 storage
contract L1ConfigResolver is
    GatewayFetchTarget,
    IERC165,
    IExtendedResolver,
    IL1ConfigResolver
{
    using GatewayFetcher for GatewayRequest;

    // ============ Errors ============
    error UnsupportedSelector(bytes4 selector);

    // ============ Constants ============

    // Storage slot constants for ConfigResolver
    // Verified via `forge inspect ConfigResolver storage`
    uint256 constant SLOT_RECORD_VERSIONS = 0;
    uint256 constant SLOT_VERSIONABLE_ADDRESSES = 2;
    uint256 constant SLOT_VERSIONABLE_HASHES = 3;
    uint256 constant SLOT_VERSIONABLE_TEXTS = 10;

    // Coin type for Ethereum (SLIP-44)
    uint256 constant COIN_TYPE_ETH = 60;

    // ============ Immutables ============
    IGatewayVerifier public immutable verifier;
    uint256 public immutable l2ChainId;
    address public immutable l2ConfigResolver;

    // ============ Constructor ============
    constructor(
        IGatewayVerifier _verifier,
        uint256 _l2ChainId,
        address _l2ConfigResolver
    ) {
        verifier = _verifier;
        l2ChainId = _l2ChainId;
        l2ConfigResolver = _l2ConfigResolver;
    }

    // ============ ERC-165 ============
    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IExtendedResolver).interfaceId ||
            interfaceId == type(IAddrResolver).interfaceId ||
            interfaceId == type(IAddressResolver).interfaceId ||
            interfaceId == type(ITextResolver).interfaceId ||
            interfaceId == type(IContentHashResolver).interfaceId ||
            interfaceId == type(IL1ConfigResolver).interfaceId;
    }

    // ============ ENSIP-10 Extended Resolver ============

    /// @notice Resolves ENS records by reading from the L2 ConfigResolver
    /// @dev The DNS-encoded name parameter is unused for direct resolution
    /// @param data The ABI-encoded function call (selector + args)
    /// @return The ABI-encoded result
    function resolve(
        bytes calldata,
        bytes calldata data
    ) external view override returns (bytes memory) {
        bytes4 selector = bytes4(data);

        // Decode the node from calldata
        bytes32 node;
        if (
            selector == IAddrResolver.addr.selector ||
            selector == IContentHashResolver.contenthash.selector
        ) {
            node = abi.decode(data[4:], (bytes32));
        } else if (selector == IAddressResolver.addr.selector) {
            (node, ) = abi.decode(data[4:], (bytes32, uint256));
        } else if (selector == ITextResolver.text.selector) {
            (node, ) = abi.decode(data[4:], (bytes32, string));
        } else {
            revert UnsupportedSelector(selector);
        }

        // Build the gateway request
        GatewayRequest memory req = _buildRequest(node, data);

        // Execute CCIP-Read fetch
        fetch(
            verifier,
            req,
            this.resolveCallback.selector,
            data,
            new string[](0)
        );
    }

    /// @notice Callback that receives verified L2 data
    /// @param values The array of values read from L2
    /// @param exitCode The exit code (0 = success)
    /// @param data The original calldata passed through
    /// @return The ABI-encoded result
    function resolveCallback(
        bytes[] calldata values,
        uint8 exitCode,
        bytes calldata data
    ) external pure returns (bytes memory) {
        // Exit code != 0 means record not found or error
        if (exitCode != 0) {
            return _emptyResponse(bytes4(data));
        }

        bytes4 selector = bytes4(data);

        if (selector == IAddrResolver.addr.selector) {
            // addr(bytes32) returns address
            bytes memory addrBytes = values[0];
            if (addrBytes.length == 0) {
                return abi.encode(address(0));
            }
            return abi.encode(address(bytes20(addrBytes)));
        } else if (selector == IAddressResolver.addr.selector) {
            // addr(bytes32, uint256) returns bytes
            return abi.encode(values[0]);
        } else if (selector == ITextResolver.text.selector) {
            // text(bytes32, string) returns string
            return abi.encode(string(values[0]));
        } else if (selector == IContentHashResolver.contenthash.selector) {
            // contenthash(bytes32) returns bytes
            return abi.encode(values[0]);
        }

        return new bytes(0);
    }

    // ============ Direct Resolution Methods ============

    /// @notice Get the ETH address for a node
    /// @param node The ENS node hash
    /// @return The ETH address
    function addr(bytes32 node) external view returns (address) {
        GatewayRequest memory req = _buildAddrRequest(node, COIN_TYPE_ETH);
        fetch(
            verifier,
            req,
            this.addrCallback.selector,
            abi.encode(node),
            new string[](0)
        );
    }

    /// @notice Callback for addr()
    function addrCallback(
        bytes[] calldata values,
        uint8 exitCode,
        bytes calldata
    ) external pure returns (address) {
        if (exitCode != 0 || values[0].length == 0) {
            return address(0);
        }
        return address(bytes20(values[0]));
    }

    /// @notice Get a text record for a node
    /// @param node The ENS node hash
    /// @param key The text record key
    /// @return The text record value
    function text(
        bytes32 node,
        string calldata key
    ) external view returns (string memory) {
        GatewayRequest memory req = _buildTextRequest(node, key);
        fetch(verifier, req, this.textCallback.selector, "", new string[](0));
    }

    /// @notice Callback for text()
    function textCallback(
        bytes[] calldata values,
        uint8 exitCode,
        bytes calldata
    ) external pure returns (string memory) {
        if (exitCode != 0 || values[0].length == 0) {
            return "";
        }
        return string(values[0]);
    }

    /// @notice Get the contenthash for a node
    /// @param node The ENS node hash
    /// @return The contenthash bytes
    function contenthash(bytes32 node) external view returns (bytes memory) {
        GatewayRequest memory req = _buildContenthashRequest(node);
        fetch(
            verifier,
            req,
            this.contenthashCallback.selector,
            "",
            new string[](0)
        );
    }

    /// @notice Callback for contenthash()
    function contenthashCallback(
        bytes[] calldata values,
        uint8 exitCode,
        bytes calldata
    ) external pure returns (bytes memory) {
        if (exitCode != 0) {
            return "";
        }
        return values[0];
    }

    // ============ Internal Request Builders ============

    /// @notice Build a gateway request based on the selector
    function _buildRequest(
        bytes32 node,
        bytes calldata data
    ) internal view returns (GatewayRequest memory) {
        bytes4 selector = bytes4(data);

        if (selector == IAddrResolver.addr.selector) {
            return _buildAddrRequest(node, COIN_TYPE_ETH);
        } else if (selector == IAddressResolver.addr.selector) {
            (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
            return _buildAddrRequest(node, coinType);
        } else if (selector == ITextResolver.text.selector) {
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            return _buildTextRequest(node, key);
        } else if (selector == IContentHashResolver.contenthash.selector) {
            return _buildContenthashRequest(node);
        }

        revert UnsupportedSelector(selector);
    }

    /// @notice Build a request to read an address record
    /// @dev Reads versionable_addresses[recordVersions[node]][node][coinType]
    function _buildAddrRequest(
        bytes32 node,
        uint256 coinType
    ) internal view returns (GatewayRequest memory req) {
        req = GatewayFetcher.newRequest(1).setTarget(l2ConfigResolver);

        // Step 1: Read recordVersions[node] and push to stack
        // recordVersions is mapping(bytes32 => uint64) at slot 0
        req = req.setSlot(SLOT_RECORD_VERSIONS).push(node).follow().read();

        // Step 2: Now stack has the version, use it to navigate versionable_addresses
        // versionable_addresses[version][node][coinType]
        req = req.setSlot(SLOT_VERSIONABLE_ADDRESSES);
        // follow() uses top of stack (version) as key
        req = req.follow();
        // Now push node and follow
        req = req.push(node).follow();
        // Now push coinType and follow
        req = req.push(coinType).follow();
        // Read the bytes value (dynamic bytes)
        req = req.readBytes().setOutput(0);
    }

    /// @notice Build a request to read a text record
    /// @dev Reads versionable_texts[recordVersions[node]][node][key]
    function _buildTextRequest(
        bytes32 node,
        string memory key
    ) internal view returns (GatewayRequest memory req) {
        req = GatewayFetcher.newRequest(1).setTarget(l2ConfigResolver);

        // Step 1: Read recordVersions[node] and push to stack
        req = req.setSlot(SLOT_RECORD_VERSIONS).push(node).follow().read();

        // Step 2: Navigate versionable_texts[version][node][key]
        req = req.setSlot(SLOT_VERSIONABLE_TEXTS);
        // follow() uses top of stack (version) as key
        req = req.follow();
        // Push node and follow
        req = req.push(node).follow();
        // Push key (string) and follow
        req = req.push(key).follow();
        // Read the string value (dynamic bytes)
        req = req.readBytes().setOutput(0);
    }

    /// @notice Build a request to read a contenthash
    /// @dev Reads versionable_hashes[recordVersions[node]][node]
    function _buildContenthashRequest(
        bytes32 node
    ) internal view returns (GatewayRequest memory req) {
        req = GatewayFetcher.newRequest(1).setTarget(l2ConfigResolver);

        // Step 1: Read recordVersions[node] and push to stack
        req = req.setSlot(SLOT_RECORD_VERSIONS).push(node).follow().read();

        // Step 2: Navigate versionable_hashes[version][node]
        req = req.setSlot(SLOT_VERSIONABLE_HASHES);
        // follow() uses top of stack (version) as key
        req = req.follow();
        // Push node and follow
        req = req.push(node).follow();
        // Read the bytes value (dynamic bytes)
        req = req.readBytes().setOutput(0);
    }

    /// @notice Return an empty response for the given selector
    function _emptyResponse(
        bytes4 selector
    ) internal pure returns (bytes memory) {
        if (selector == IAddrResolver.addr.selector) {
            return abi.encode(address(0));
        } else if (selector == IAddressResolver.addr.selector) {
            return abi.encode(new bytes(0));
        } else if (selector == ITextResolver.text.selector) {
            return abi.encode("");
        } else if (selector == IContentHashResolver.contenthash.selector) {
            return abi.encode(new bytes(0));
        }
        return new bytes(0);
    }
}
