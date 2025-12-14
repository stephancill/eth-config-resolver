//SPDX-License-Identifier: MIT
pragma solidity >=0.8.17 <0.9.0;

import "@ensdomains/ens-contracts/registry/ENS.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/ABIResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/AddrResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/ContentHashResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/DNSResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/InterfaceResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/NameResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/PubkeyResolver.sol";
import "@ensdomains/ens-contracts/resolvers/profiles/TextResolver.sol";
import "@ensdomains/ens-contracts/resolvers/Multicallable.sol";
import {ReverseClaimer} from "@ensdomains/ens-contracts/reverseRegistrar/ReverseClaimer.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";
import {NameCoder} from "@ensdomains/ens-contracts/utils/NameCoder.sol";

bytes32 constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;
bytes32 constant lookup = 0x3031323334353637383961626364656600000000000000000000000000000000;

/// A simple resolver anyone can use; only allows the owner of a node to set its
/// address.
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
    ReverseClaimer
{
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

    constructor(ENS _ens, INameWrapper wrapperAddress) ReverseClaimer(_ens, msg.sender) {
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
        return super.supportsInterface(interfaceID);
    }
}
