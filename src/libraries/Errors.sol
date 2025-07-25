// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

/// @title  Errors
/// @author 0xIntuition
/// @notice Library containing all custom errors detailing cases where the Intuition Protocol may revert.
library Errors {
    ///////// TRUST ERRORS //////////////////////////////////////////////////////////////////

    error Trust_AnnualMintingLimitExceeded();
    error Trust_EpochMintingLimitExceeded();
    error Trust_InvalidAnnualReductionBasisPoints();
    error Trust_InvalidMaxAnnualEmission();
    error Trust_InvalidMaxEmissionPerEpochBasisPoints();
    error Trust_OverridenInitializer();
    error Trust_ZeroAddress();
    error Trust_ZeroAmount();
}
