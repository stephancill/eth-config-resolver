// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title IL1ConfigResolver
/// @notice Interface for L1 resolvers that read ENS records from an L2 ConfigResolver
interface IL1ConfigResolver {
    /// @notice Returns the chain ID of the L2 where the ConfigResolver is deployed
    /// @return The L2 chain ID
    function l2ChainId() external view returns (uint256);

    /// @notice Returns the address of the ConfigResolver on L2
    /// @return The L2 ConfigResolver address
    function l2ConfigResolver() external view returns (address);
}
