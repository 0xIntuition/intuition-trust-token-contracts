// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

/**
 * @title ITrustBonding
 * @author 0xIntuition
 * @notice The minimal interface for the TrustBonding contract
 */
interface ITrustBonding {
    /**
     * @notice Returns the length of an epoch in seconds (2 weeks by default)
     * @return The length of an epoch in seconds
     */
    function epochLength() external view returns (uint256);

    /**
     * @notice Starting timestamp of the bonding contract's first epoch (epoch 0)
     * @return The start timestamp of the bonding contract
     */
    function startTimestamp() external view returns (uint256);
}
