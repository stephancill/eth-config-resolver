//SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@ensdomains/ens-contracts/registry/ENS.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";

bytes32 constant lookup = 0x3031323334353637383961626364656600000000000000000000000000000000;

/// @title AddressSubnameRegistrar
/// @notice Allows users to claim <their-address>.<parent>.eth subnames
/// @dev Works with both wrapped and unwrapped parent names
contract AddressSubnameRegistrar {
    ENS public immutable ens;
    INameWrapper public immutable nameWrapper;
    bytes32 public immutable parentNode;
    address public immutable defaultResolver;

    event SubnameClaimed(address indexed addr, bytes32 indexed node, address owner);

    error Unauthorized();
    error AlreadyClaimed();

    /// @param _ens The ENS registry address
    /// @param _nameWrapper The NameWrapper address
    /// @param _parentNode The namehash of the parent name (e.g., namehash("ethconfig.eth"))
    /// @param _defaultResolver The default resolver to set for claimed subnames
    constructor(ENS _ens, INameWrapper _nameWrapper, bytes32 _parentNode, address _defaultResolver) {
        ens = _ens;
        nameWrapper = _nameWrapper;
        parentNode = _parentNode;
        defaultResolver = _defaultResolver;
    }

    /// @notice Claim a subname for the caller's address
    /// @return node The ENS node hash of the claimed subname
    function claim() external returns (bytes32) {
        return claimForAddr(msg.sender, msg.sender);
    }

    /// @notice Claim a subname for a specific address
    /// @param addr The address to create the subname for
    /// @param owner The owner of the new subname
    /// @return node The ENS node hash of the claimed subname
    function claimForAddr(address addr, address owner) public returns (bytes32) {
        // Only the address owner can claim their subname
        if (addr != msg.sender && !ens.isApprovedForAll(addr, msg.sender)) {
            revert Unauthorized();
        }

        bytes32 labelHash = sha3HexAddress(addr);
        bytes32 node = keccak256(abi.encodePacked(parentNode, labelHash));

        // Check if already claimed
        address currentOwner = ens.owner(node);
        if (currentOwner != address(0)) {
            // If owned by NameWrapper, check if it's actually wrapped
            if (address(nameWrapper) != address(0) && currentOwner == address(nameWrapper)) {
                if (nameWrapper.ownerOf(uint256(node)) != address(0)) {
                    revert AlreadyClaimed();
                }
            } else {
                // Owned by someone else
                revert AlreadyClaimed();
            }
        }

        // Check if the parent is wrapped (owned by NameWrapper in registry)
        address parentOwner = ens.owner(parentNode);
        if (address(nameWrapper) != address(0) && parentOwner == address(nameWrapper)) {
            // Parent is wrapped - use NameWrapper to create wrapped subname
            _claimWrapped(addr, owner);
        } else {
            // Parent is unwrapped - use ENS registry directly
            _claimUnwrapped(labelHash, owner);
        }

        emit SubnameClaimed(addr, node, owner);
        return node;
    }

    /// @notice Get the node hash for a given address's subname
    /// @param addr The address
    /// @return The ENS node hash
    function node(address addr) public view returns (bytes32) {
        return keccak256(abi.encodePacked(parentNode, sha3HexAddress(addr)));
    }

    /// @notice Get the label (hex address) for a given address
    /// @param addr The address
    /// @return The lowercase hex string (42 characters, with 0x prefix)
    function getLabel(address addr) public pure returns (string memory) {
        bytes memory ret = new bytes(42);
        ret[0] = "0";
        ret[1] = "x";
        uint160 addrVal = uint160(addr);
        for (uint256 i = 42; i > 2;) {
            unchecked {
                i--;
                ret[i] = bytes1(uint8(lookup[addrVal & 0xf]));
                addrVal = addrVal >> 4;
                i--;
                ret[i] = bytes1(uint8(lookup[addrVal & 0xf]));
                addrVal = addrVal >> 4;
            }
        }
        return string(ret);
    }

    /// @notice Check if a subname for an address is available
    /// @param addr The address to check
    /// @return True if the subname is available
    function available(address addr) public view returns (bool) {
        bytes32 node_ = node(addr);
        address currentOwner = ens.owner(node_);

        if (currentOwner == address(0)) {
            return true;
        }

        if (address(nameWrapper) != address(0) && currentOwner == address(nameWrapper)) {
            return nameWrapper.ownerOf(uint256(node_)) == address(0);
        }

        return false;
    }

    function _claimWrapped(address addr, address owner) internal {
        // Get parent expiry to set subname expiry
        (,, uint64 parentExpiry) = nameWrapper.getData(uint256(parentNode));

        // Create wrapped subname
        // The label needs to be the actual string, not the hash
        string memory labelStr = getLabel(addr);

        nameWrapper.setSubnodeRecord(
            parentNode,
            labelStr,
            owner,
            defaultResolver,
            0, // TTL
            0, // No fuses burned - owner has full control
            parentExpiry
        );
    }

    function _claimUnwrapped(bytes32 labelHash, address owner) internal {
        ens.setSubnodeRecord(parentNode, labelHash, owner, defaultResolver, 0);
    }

    /// @dev Compute the keccak256 hash of the lowercase hex representation of an address with 0x prefix
    function sha3HexAddress(address addr) internal pure returns (bytes32 ret) {
        assembly {
            // Store "0x" prefix at positions 0-1
            mstore8(0, 0x30) // '0' = 0x30
            mstore8(1, 0x78) // 'x' = 0x78
            // Store hex address starting at position 2
            for { let i := 42 } gt(i, 2) {} {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
            }
            ret := keccak256(0, 42)
        }
    }
}

