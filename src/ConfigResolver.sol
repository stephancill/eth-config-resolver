//SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@ensdomains/ens-contracts/registry/ENS.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/ABIResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/AddrResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/ContentHashResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/DNSResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/InterfaceResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/NameResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/PubkeyResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/TextResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/IExtendedResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/IAddrResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/ITextResolver.sol";
import "@ensdomains/ens-contracts/resolvers/Multicallable.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";
import {HexUtils} from "@ensdomains/ens-contracts/utils/HexUtils.sol";

bytes32 constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;
bytes32 constant lookup = 0x3031323334353637383961626364656600000000000000000000000000000000;

/// A simple resolver anyone can use; only allows the owner of a node to set its
/// address. Supports ENSIP-10 wildcard resolution for address-based subnames.
contract ConfigResolver is
    Multicallable,
    ABIResolver,
    AddrResolver,
    ContentHashResolver,
    DNSResolver,
    InterfaceResolver,
    NameResolver,
    PubkeyResolver,
    TextResolver,
    IExtendedResolver
{
    using HexUtils for bytes;
    ENS immutable ens;
    INameWrapper immutable nameWrapper;

    /// A mapping of operators. An address that is authorised for an address
    /// may make any changes to the name that the owner could, but may not update
    /// the set of authorisations.
    /// (owner, operator) => approved
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /// A mapping of delegates. A delegate that is authorised by an owner
    /// for a name may make changes to the name's resolver, but may not update
    /// the set of token approvals.
    /// (owner, name, delegate) => approved
    mapping(address => mapping(bytes32 => mapping(address => bool))) private _tokenApprovals;

    // Logged when an operator is added or removed.
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // Logged when a delegate is approved or  an approval is revoked.
    event Approved(address owner, bytes32 indexed node, address indexed delegate, bool indexed approved);

    constructor(ENS _ens, INameWrapper wrapperAddress) {
        ens = _ens;
        nameWrapper = wrapperAddress;
    }

    /// @dev Returns the node hash for a given account's reverse records.
    /// @param addr The address to hash
    /// @return The ENS node hash.
    function reverseNode(address addr) public pure returns (bytes32) {
        bytes32 sha3HexAddress;

        // An optimised function to compute the sha3 of the lower-case
        // hexadecimal representation of an Ethereum address.
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

            sha3HexAddress := keccak256(0, 40)
        }

        return keccak256(abi.encodePacked(ADDR_REVERSE_NODE, sha3HexAddress));
    }

    /// @dev See {IERC1155-setApprovalForAll}.
    function setApprovalForAll(address operator, bool approved) external {
        require(msg.sender != operator, "ERC1155: setting approval status for self");

        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @dev See {IERC1155-isApprovedForAll}.
    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    /// @dev Approve a delegate to be able to updated records on a node.
    function approve(bytes32 node, address delegate, bool approved) external {
        require(msg.sender != delegate, "Setting delegate status for self");

        _tokenApprovals[msg.sender][node][delegate] = approved;
        emit Approved(msg.sender, node, delegate, approved);
    }

    /// @dev Check to see if the delegate has been approved by the owner for the node.
    function isApprovedFor(address owner, bytes32 node, address delegate) public view returns (bool) {
        return _tokenApprovals[owner][node][delegate];
    }

    function isAuthorised(bytes32 node) internal view override returns (bool) {
        if (reverseNode(msg.sender) == node) {
            return true;
        }

        address owner = ens.owner(node);
        if (owner == address(nameWrapper)) {
            owner = nameWrapper.ownerOf(uint256(node));
        }
        return owner == msg.sender || isApprovedForAll(owner, msg.sender) || isApprovedFor(owner, node, msg.sender);
    }

    /// @dev ENSIP-10 wildcard resolution. Resolves subnames like <address>.parent.eth
    /// without requiring them to be claimed in ENS, and also supports standard resolution
    /// for manually created names.
    /// @param name The DNS-encoded name to resolve
    /// @param data The ABI-encoded call data (selector + args)
    /// @return The ABI-encoded result of the resolution
    function resolve(bytes calldata name, bytes calldata data) external view override returns (bytes memory) {
        // Extract the first label length
        uint256 labelLen = uint8(name[0]);

        // If this is a 40-char hex address label, handle wildcard resolution
        if (labelLen == 40) {
            // Parse the hex address from the label
            bytes memory label = name[1:41];
            (address resolvedAddr, bool valid) = label.hexToAddress(0, 40);
            if (!valid) {
                revert("Invalid hex address");
            }

            // For text records and other data, we use the address's reverse node
            // This allows users to set records once and have them resolve under any parent
            bytes32 addrReverseNode = reverseNode(resolvedAddr);

            // Check which function is being called
            bytes4 selector = bytes4(data[:4]);

            if (selector == IAddrResolver.addr.selector) {
                // Return the address encoded in the label
                return abi.encode(resolvedAddr);
            }

            if (selector == ITextResolver.text.selector) {
                // Decode the key from the call data
                (, string memory key) = abi.decode(data[4:], (bytes32, string));
                // Look up the stored text record under the address's reverse node
                string memory value = this.text(addrReverseNode, key);
                return abi.encode(value);
            }

            // For other calls, try to forward to the appropriate function
            // by making a static call to ourselves with the address's reverse node
            bytes memory newData = abi.encodePacked(selector, addrReverseNode, data[36:]);
            (bool success, bytes memory result) = address(this).staticcall(newData);
            if (success) {
                return result;
            }

            revert("Unsupported function");
        }

        // For non-wildcard queries (e.g., the parent domain itself or any manually created name),
        // forward the call directly to the inherited resolver functions using the original calldata
        (bool success, bytes memory result) = address(this).staticcall(data);
        if (success) {
            return result;
        }
        revert("Resolution failed");
    }

    function supportsInterface(bytes4 interfaceID)
        public
        view
        override(
            Multicallable,
            ABIResolver,
            AddrResolver,
            ContentHashResolver,
            DNSResolver,
            InterfaceResolver,
            NameResolver,
            PubkeyResolver,
            TextResolver
        )
        returns (bool)
    {
        // 0x9061b923 is the interface ID for IExtendedResolver (ENSIP-10)
        return interfaceID == 0x9061b923 || super.supportsInterface(interfaceID);
    }
}
