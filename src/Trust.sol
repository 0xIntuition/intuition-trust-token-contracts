// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {HypERC20} from "@hyperlane-xyz/token/HypERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {Errors} from "src/libraries/Errors.sol";
import {ITrustBonding} from "src/interfaces/ITrustBonding.sol";

/**
 * @title  Trust
 * @author 0xIntuition
 * @notice Core contract of the Intuition protocol. Trust (TRUST) is the utility token that is used in
 *         the Intuition protocol for bonding in order to generate the inflationary rewards in form of
 *         the additional TRUST tokens, as well as for the DAO governance and staking inside the MultiVault.
 */
contract Trust is Initializable, HypERC20, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Number of seconds in a year
    uint256 public constant ONE_YEAR = 365 days;

    /// @notice Basis points divisor
    uint256 public constant BASIS_POINTS_DIVISOR = 10_000;

    /// @notice Maximum possible annual emission of Trust tokens
    uint256 public constant MAX_POSSIBLE_ANNUAL_EMISSION = 1e8 * 1e18; // 10% of the initial supply on Base

    /// @notice Minter role identifier
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role used for pausing the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks the start of the current annual period
    uint256 public annualPeriodStartTime;

    /// @notice Tracks the amount minted in the current annual period
    uint256 public annualMintedAmount;

    /// @notice Start time of the current epoch
    uint256 public epochStartTime;

    /// @notice Amount minted in the current epoch
    uint256 public epochMintedAmount;

    /// @notice Maximum annual emission of Trust tokens
    uint256 public maxAnnualEmission;

    /// @notice Maximum emission per epoch in basis points of max annual emission
    uint256 public maxEmissionPerEpochBasisPoints;

    /// @notice Reduction percentage per year in basis points of max annual emission
    uint256 public annualReductionBasisPoints;

    /// @notice TrustBonding contract address
    ITrustBonding public trustBonding;

    /// @dev Gap for upgrade safety
    uint256[50] private __gap;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Event emitted when the TrustBonding contract address is set
     * @param newTrustBonding New TrustBonding contract address
     */
    event TrustBondingSet(address indexed newTrustBonding);

    /**
     * @notice Event emitted when the maximum annual emission is changed
     * @param newMaxAnnualEmission New maximum annual emission
     */
    event MaxAnnualEmissionChanged(uint256 indexed newMaxAnnualEmission);

    /**
     * @notice Event emitted when the maximum emission per epoch is changed
     * @param newMaxEmissionPerEpochBasisPoints New maximum emission per epoch in basis points
     */
    event MaxEmissionPerEpochBasisPointsChanged(uint256 indexed newMaxEmissionPerEpochBasisPoints);

    /**
     * @notice Event emitted when the annual reduction basis points is changed
     * @param newAnnualReductionBasisPoints New annual reduction basis points
     */
    event AnnualReductionBasisPointsChanged(uint256 indexed newAnnualReductionBasisPoints);

    /*//////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint8 decimals_, uint256 scale_, address mailbox_) HypERC20(decimals_, scale_, mailbox_) {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                                 INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function initialize(
        uint256, /* _totalSupply */
        string memory, /* _name */
        string memory, /* _symbol */
        address, /* _hook */
        address, /* _interchainSecurityModule */
        address /* _owner */
    ) public override {
        revert Errors.Trust_OverridenInitializer();
    }

    /**
     * @notice Initializes the Trust contract
     * @param _admin Admin address (multisig)
     * @param _trustBonding TrustBonding contract address
     * @param _maxAnnualEmission Maximum annual emission of Trust tokens
     * @param _maxEmissionPerEpochBasisPoints Maximum emission per epoch
     * @param _annualReductionBasisPoints Annual reduction basis points
     */
    function initialize(
        // Trust-specific parameters
        address _trustBonding,
        uint256 _maxAnnualEmission,
        uint256 _maxEmissionPerEpochBasisPoints,
        uint256 _annualReductionBasisPoints,
        // HypERC20 parameters
        uint256 _totalSupply,
        address _hook,
        address _interchainSecurityModule,
        address _admin
    ) external initializer {
        if (_admin == address(0) || _trustBonding == address(0)) {
            revert Errors.Trust_ZeroAddress();
        }

        if (_maxAnnualEmission > MAX_POSSIBLE_ANNUAL_EMISSION) {
            revert Errors.Trust_InvalidMaxAnnualEmission();
        }

        if (_maxEmissionPerEpochBasisPoints > BASIS_POINTS_DIVISOR || _maxEmissionPerEpochBasisPoints == 0) {
            revert Errors.Trust_InvalidMaxEmissionPerEpochBasisPoints();
        }

        if (_annualReductionBasisPoints >= BASIS_POINTS_DIVISOR) {
            revert Errors.Trust_InvalidAnnualReductionBasisPoints();
        }

        // Initialize in correct order (matching HypERC20)
        __ERC20_init("Intuition", "TRUST");
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _admin);

        // Mint initial supply to deployer
        if (_totalSupply > 0) {
            _mint(msg.sender, _totalSupply);
        }

        // Initialize additional upgradeables
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(MINTER_ROLE, _trustBonding);

        // Set the TrustBonding contract address
        trustBonding = ITrustBonding(_trustBonding);

        // Initialize annual minting variables
        annualPeriodStartTime = trustBonding.startTimestamp();
        annualMintedAmount = 0;
        maxAnnualEmission = _maxAnnualEmission;

        // Initialize epoch variables
        epochStartTime = annualPeriodStartTime;
        epochMintedAmount = 0;
        maxEmissionPerEpochBasisPoints = _maxEmissionPerEpochBasisPoints;

        // Initialize emission reduction variables
        annualReductionBasisPoints = _annualReductionBasisPoints;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total mintable amount for the current annual period
     * @return Total mintable amount for the current annual period after subtracting the
     *         amount already minted in the current annual period
     */
    function getTotalMintableForCurrentAnnualPeriod() external view returns (uint256) {
        uint256 currentTime = block.timestamp;

        if (currentTime >= annualPeriodStartTime + ONE_YEAR) {
            return 0;
        }

        uint256 annualMaxMintAmount = maxAnnualEmission;
        uint256 mintableAmount = annualMaxMintAmount - annualMintedAmount;

        return mintableAmount;
    }

    /**
     * @notice Returns the total mintable amount for the current epoch
     * @return Total mintable amount for the current epoch after subtracting the
     *         amount already minted in the current epoch
     */
    function getTotalMintableForCurrentEpoch() external view returns (uint256) {
        uint256 epochDuration = trustBonding.epochLength();
        uint256 epochEndTime = epochStartTime + epochDuration;
        uint256 currentTime = block.timestamp;

        if (currentTime >= epochEndTime) {
            return 0;
        }

        uint256 epochMaxMintAmount = getMaxMintAmountPerEpoch();
        uint256 mintableAmount = epochMaxMintAmount - epochMintedAmount;

        return mintableAmount;
    }

    /**
     * @notice Returns the maximum mint amount per epoch in Trust tokens for the current epoch
     * @return Maximum mint amount per epoch in Trust tokens
     */
    function getMaxMintAmountPerEpoch() public view returns (uint256) {
        uint256 epochMaxMintAmount = (maxAnnualEmission * maxEmissionPerEpochBasisPoints) / BASIS_POINTS_DIVISOR;
        return epochMaxMintAmount;
    }

    /**
     * @notice Returns the annual emission reduction amount in Trust tokens for the current year
     * @return Trust token emission reduction amount in basis points
     */
    function getAnnualReductionAmount() public view returns (uint256) {
        uint256 reductionAmount = (maxAnnualEmission * annualReductionBasisPoints) / BASIS_POINTS_DIVISOR;
        return reductionAmount;
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses the pausable contract methods
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the pausable contract methods
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Sets the TrustBonding contract address
     * @param newTrustBonding TrustBonding contract address
     */
    function setTrustBonding(address newTrustBonding) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTrustBonding == address(0)) {
            revert Errors.Trust_ZeroAddress();
        }

        trustBonding = ITrustBonding(newTrustBonding);

        emit TrustBondingSet(newTrustBonding);
    }

    /**
     * @notice Sets the maximum emission per epoch in basis points of max annual emission
     * @param newMaxEmissionPerEpochBasisPoints New maximum emission per epoch in basis points
     */
    function setMaxEmissionPerEpochBasisPoints(uint256 newMaxEmissionPerEpochBasisPoints)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newMaxEmissionPerEpochBasisPoints > BASIS_POINTS_DIVISOR) {
            revert Errors.Trust_InvalidMaxEmissionPerEpochBasisPoints();
        }

        maxEmissionPerEpochBasisPoints = newMaxEmissionPerEpochBasisPoints;

        emit MaxEmissionPerEpochBasisPointsChanged(newMaxEmissionPerEpochBasisPoints);
    }

    /**
     * @notice Sets the annual reduction percentage in basis points of max annual emission
     * @param newAnnualReductionBasisPoints New annual reduction percentage
     */
    function setAnnualReductionBasisPoints(uint256 newAnnualReductionBasisPoints)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newAnnualReductionBasisPoints >= BASIS_POINTS_DIVISOR) {
            revert Errors.Trust_InvalidAnnualReductionBasisPoints();
        }

        annualReductionBasisPoints = newAnnualReductionBasisPoints;

        emit AnnualReductionBasisPointsChanged(newAnnualReductionBasisPoints);
    }

    /*//////////////////////////////////////////////////////////////
                             MINTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint new energy tokens to an address
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external nonReentrant whenNotPaused onlyRole(MINTER_ROLE) {
        if (amount == 0) {
            revert Errors.Trust_ZeroAmount();
        }

        // Check and update annual and epoch minting limits
        _updateMinting(amount);

        _mint(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to update annual and epoch minting amounts
     * @param amount Amount of Trust tokens to mint
     */
    function _updateMinting(uint256 amount) internal {
        // Adjust maxAnnualEmission annually
        if (block.timestamp >= annualPeriodStartTime + ONE_YEAR) {
            // Reduce maxAnnualEmission by annualReductionBasisPoints
            uint256 reductionAmount = getAnnualReductionAmount();
            maxAnnualEmission -= reductionAmount;

            // Emit an event for the change in maxAnnualEmission
            emit MaxAnnualEmissionChanged(maxAnnualEmission);

            // Reset the annual minted amount
            annualMintedAmount = 0;

            // Update the annual period start time
            annualPeriodStartTime = block.timestamp;
        }

        // Ensure that the annual minted amount plus the new amount does not exceed the maximum
        if (annualMintedAmount + amount > maxAnnualEmission) {
            revert Errors.Trust_AnnualMintingLimitExceeded();
        }

        // Update the annual minted amount
        annualMintedAmount += amount;

        uint256 epochDuration = trustBonding.epochLength();

        // Epoch minting logic
        if (block.timestamp >= epochStartTime + epochDuration) {
            epochStartTime = block.timestamp;
            epochMintedAmount = 0;
        }

        // Calculate maximum emission per epoch
        uint256 epochMaxMintAmount = getMaxMintAmountPerEpoch();

        // Ensure that the epoch minted amount plus the new amount does not exceed the maximum
        if (epochMintedAmount + amount > epochMaxMintAmount) {
            revert Errors.Trust_EpochMintingLimitExceeded();
        }

        // Update the epoch minted amount
        epochMintedAmount += amount;
    }
}
