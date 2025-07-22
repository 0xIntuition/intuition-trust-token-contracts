// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Errors} from "src/libraries/Errors.sol";
import {Trust} from "src/Trust.sol";

/// @dev Mock contract to simulate TrustBonding behavior
contract MockTrustBonding {
    uint256 public epochLength;
    uint256 public startTimestamp;

    function setEpochLength(uint256 _epochLength) external {
        epochLength = _epochLength;
    }

    function setStartTimestamp(uint256 _startTimestamp) external {
        startTimestamp = _startTimestamp;
    }
}

/// @dev Mock contract to simulate Hyperlane mailbox behavior
contract MockHyperlaneMailbox {
    uint32 public localDomain;
    address public defaultHook;
    address public defaultIsm;

    constructor(uint32 _localDomain, address _defaultHook, address _defaultIsm) {
        localDomain = _localDomain;
        defaultHook = _defaultHook;
        defaultIsm = _defaultIsm;
    }
}

/// @dev Hyperlane only checks that the ISM and hook are contracts, so we can use empty mocks
contract MockDefaultHook {}

contract MockDefaultIsm {}

contract TrustTest is Test {
    /// @notice Constants
    uint256 public constant BASIS_POINTS_DIVISOR = 10_000;
    uint256 public constant MAX_POSSIBLE_ANNUAL_EMISSION = 1e8 * 1e18;
    uint256 public constant ONE_YEAR = 365 days;

    /// @notice Hyperlane-specific constants
    uint32 public constant localDomain = 123; // Example domain ID for Intuition L3
    uint8 public constant decimals = 18;
    uint256 public constant scale = 1e18;
    uint256 public constant initialHypERC20Supply = 0;
    address public hook = address(new MockDefaultHook());
    address public ism = address(new MockDefaultIsm());

    /// @notice Test actors
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public admin = makeAddr("admin");
    address public proxyAdmin = makeAddr("proxyAdmin");
    address public pauser = makeAddr("pauser");
    address public unauthorized = makeAddr("unauthorized");

    /// @notice Contracts
    Trust public trust;
    MockTrustBonding public trustBonding;
    MockHyperlaneMailbox public mailbox;

    /// @notice Test config
    uint256 public maxAnnualEmission = 1e8 * 1e18;
    uint256 public maxEmissionPerEpochBasisPoints = 1000;
    uint256 public annualReductionBasisPoints = 1000;
    uint256 public epochLength = 14 days;
    uint256 public startTimestamp;

    /// @notice Events
    event TrustBondingSet(address indexed newTrustBonding);
    event MaxAnnualEmissionChanged(uint256 indexed newMaxAnnualEmission);
    event MaxEmissionPerEpochBasisPointsChanged(uint256 indexed newMaxEmissionPerEpochBasisPoints);
    event AnnualReductionBasisPointsChanged(uint256 indexed newAnnualReductionBasisPoints);

    function setUp() external {
        startTimestamp = block.timestamp + 1 hours;

        // Deploy mock TrustBonding
        trustBonding = new MockTrustBonding();
        trustBonding.setEpochLength(epochLength);
        trustBonding.setStartTimestamp(startTimestamp);

        // Deploy mock Hyperlane contracts
        mailbox = new MockHyperlaneMailbox(localDomain, hook, ism);

        // Deploy Trust contract
        Trust implementation = new Trust(decimals, scale, address(mailbox));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), proxyAdmin, "");
        trust = Trust(address(proxy));

        // Initialize Trust
        trust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            annualReductionBasisPoints,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );

        // Warp to start time
        vm.warp(startTimestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_successful() external {
        Trust freshTrust = _deployFreshTrust();

        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            annualReductionBasisPoints,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );

        assertTrue(freshTrust.hasRole(freshTrust.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(freshTrust.hasRole(freshTrust.PAUSER_ROLE(), admin));
        assertTrue(freshTrust.hasRole(freshTrust.MINTER_ROLE(), address(trustBonding)));
        assertEq(address(freshTrust.trustBonding()), address(trustBonding));
        assertEq(freshTrust.maxAnnualEmission(), maxAnnualEmission);
        assertEq(freshTrust.maxEmissionPerEpochBasisPoints(), maxEmissionPerEpochBasisPoints);
        assertEq(freshTrust.annualReductionBasisPoints(), annualReductionBasisPoints);
        assertEq(freshTrust.annualPeriodStartTime(), startTimestamp);
        assertEq(freshTrust.epochStartTime(), startTimestamp);
    }

    function test_initialize_revertsOnZeroAdmin() external {
        Trust freshTrust = _deployFreshTrust();

        vm.expectRevert(Errors.Trust_ZeroAddress.selector);
        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            annualReductionBasisPoints,
            initialHypERC20Supply,
            hook,
            ism,
            address(0)
        );
    }

    function test_initialize_revertsOnZeroTrustBonding() external {
        Trust freshTrust = _deployFreshTrust();

        vm.expectRevert(Errors.Trust_ZeroAddress.selector);
        freshTrust.initialize(
            address(0),
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            annualReductionBasisPoints,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );
    }

    function test_initialize_revertsOnInvalidMaxAnnualEmission() external {
        Trust freshTrust = _deployFreshTrust();

        vm.expectRevert(Errors.Trust_InvalidMaxAnnualEmission.selector);
        freshTrust.initialize(
            address(trustBonding),
            MAX_POSSIBLE_ANNUAL_EMISSION + 1,
            maxEmissionPerEpochBasisPoints,
            annualReductionBasisPoints,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );
    }

    function test_initialize_revertsOnInvalidMaxEmissionPerEpochBasisPoints() external {
        Trust freshTrust = _deployFreshTrust();

        vm.expectRevert(Errors.Trust_InvalidMaxEmissionPerEpochBasisPoints.selector);
        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            BASIS_POINTS_DIVISOR + 1,
            annualReductionBasisPoints,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );
    }

    function test_initialize_revertsOnZeroMaxEmissionPerEpochBasisPoints() external {
        Trust freshTrust = _deployFreshTrust();

        vm.expectRevert(Errors.Trust_InvalidMaxEmissionPerEpochBasisPoints.selector);
        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            0,
            annualReductionBasisPoints,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );
    }

    function test_initialize_revertsOnInvalidAnnualReductionBasisPoints() external {
        Trust freshTrust = _deployFreshTrust();

        vm.expectRevert(Errors.Trust_InvalidAnnualReductionBasisPoints.selector);
        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            BASIS_POINTS_DIVISOR,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );
    }

    function test_initialize_revertsOnDoubleInitialization() external {
        Trust freshTrust = _deployFreshTrust();

        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            annualReductionBasisPoints,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );

        vm.expectRevert();
        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            annualReductionBasisPoints,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );
    }

    function test_initialize_withMaximumValidValues() external {
        Trust freshTrust = _deployFreshTrust();

        freshTrust.initialize(
            address(trustBonding),
            MAX_POSSIBLE_ANNUAL_EMISSION,
            BASIS_POINTS_DIVISOR,
            BASIS_POINTS_DIVISOR - 1,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );

        assertEq(freshTrust.maxAnnualEmission(), MAX_POSSIBLE_ANNUAL_EMISSION);
        assertEq(freshTrust.maxEmissionPerEpochBasisPoints(), BASIS_POINTS_DIVISOR);
        assertEq(freshTrust.annualReductionBasisPoints(), BASIS_POINTS_DIVISOR - 1);
    }

    function test_initialize_withMinimumValidValues() external {
        Trust freshTrust = _deployFreshTrust();

        freshTrust.initialize(address(trustBonding), 0, 1, 0, initialHypERC20Supply, hook, ism, admin);

        assertEq(freshTrust.maxAnnualEmission(), 0);
        assertEq(freshTrust.maxEmissionPerEpochBasisPoints(), 1);
        assertEq(freshTrust.annualReductionBasisPoints(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSE/UNPAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pause_successful() external {
        vm.prank(admin);
        trust.pause();

        assertTrue(trust.paused());
    }

    function test_pause_revertsOnUnauthorized() external {
        vm.prank(unauthorized);
        vm.expectRevert();
        trust.pause();
    }

    function test_unpause_successful() external {
        vm.prank(admin);
        trust.pause();

        vm.prank(admin);
        trust.unpause();

        assertFalse(trust.paused());
    }

    function test_unpause_revertsOnUnauthorized() external {
        vm.prank(admin);
        trust.pause();

        vm.prank(unauthorized);
        vm.expectRevert();
        trust.unpause();
    }

    function test_mint_revertsWhenPaused() external {
        vm.prank(admin);
        trust.pause();

        vm.prank(address(trustBonding));
        vm.expectRevert();
        trust.mint(alice, 1000);
    }

    function test_viewFunctions_workWhenPaused() external {
        vm.prank(admin);
        trust.pause();

        // View functions should still work
        trust.getTotalMintableForCurrentAnnualPeriod();
        trust.getTotalMintableForCurrentEpoch();
        trust.getMaxMintAmountPerEpoch();
        trust.getAnnualReductionAmount();
    }

    /*//////////////////////////////////////////////////////////////
                        MINT FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_mint_successful() external {
        uint256 amount = 1000 * 1e18;
        uint256 initialBalance = trust.balanceOf(alice);
        uint256 initialSupply = trust.totalSupply();

        vm.prank(address(trustBonding));
        trust.mint(alice, amount);

        assertEq(trust.balanceOf(alice), initialBalance + amount);
        assertEq(trust.totalSupply(), initialSupply + amount);
    }

    function test_mint_revertsOnUnauthorized() external {
        vm.prank(unauthorized);
        vm.expectRevert();
        trust.mint(alice, 1000);
    }

    function test_mint_revertsOnZeroAmount() external {
        vm.prank(address(trustBonding));
        vm.expectRevert(Errors.Trust_ZeroAmount.selector);
        trust.mint(alice, 0);
    }

    function test_mint_revertsOnExceedingAnnualLimit() external {
        uint256 exceedingAmount = trust.maxAnnualEmission() + 1;

        vm.prank(address(trustBonding));
        vm.expectRevert(Errors.Trust_AnnualMintingLimitExceeded.selector);
        trust.mint(alice, exceedingAmount);
    }

    function test_mint_revertsOnExceedingEpochLimit() external {
        uint256 exceedingAmount = trust.getMaxMintAmountPerEpoch() + 1;

        vm.prank(address(trustBonding));
        vm.expectRevert(Errors.Trust_EpochMintingLimitExceeded.selector);
        trust.mint(alice, exceedingAmount);
    }

    function test_mint_updatesAnnualMintedAmount() external {
        uint256 amount = 1000 * 1e18;
        uint256 initialAnnualMinted = trust.annualMintedAmount();

        vm.prank(address(trustBonding));
        trust.mint(alice, amount);

        assertEq(trust.annualMintedAmount(), initialAnnualMinted + amount);
    }

    function test_mint_updatesEpochMintedAmount() external {
        uint256 amount = 1000 * 1e18;
        uint256 initialEpochMinted = trust.epochMintedAmount();

        vm.prank(address(trustBonding));
        trust.mint(alice, amount);

        assertEq(trust.epochMintedAmount(), initialEpochMinted + amount);
    }

    function test_mint_resetsAnnualLimitAfterYear() external {
        uint256 initialMaxAnnualEmission = trust.maxAnnualEmission();
        uint256 reductionAmount = trust.getAnnualReductionAmount();

        // Warp past one year
        vm.warp(startTimestamp + ONE_YEAR);

        vm.prank(address(trustBonding));
        trust.mint(alice, 1);

        // Annual emission should be reduced
        assertEq(trust.maxAnnualEmission(), initialMaxAnnualEmission - reductionAmount);
        assertEq(trust.annualMintedAmount(), 1);
        assertEq(trust.annualPeriodStartTime(), startTimestamp + ONE_YEAR);
    }

    function test_mint_resetsEpochLimitAfterEpoch() external {
        // Warp past one epoch
        vm.warp(startTimestamp + epochLength);

        vm.prank(address(trustBonding));
        trust.mint(alice, 1);

        assertEq(trust.epochMintedAmount(), 1);
        assertEq(trust.epochStartTime(), startTimestamp + epochLength);
    }

    function test_mint_simultaneousAnnualAndEpochReset() external {
        // Set epoch length to exactly one year for this test
        trustBonding.setEpochLength(ONE_YEAR);

        uint256 initialMaxAnnualEmission = trust.maxAnnualEmission();
        uint256 reductionAmount = trust.getAnnualReductionAmount();

        // Warp past one year (which is also one epoch)
        vm.warp(startTimestamp + ONE_YEAR);

        vm.prank(address(trustBonding));
        trust.mint(alice, 1);

        // Both annual and epoch should reset
        assertEq(trust.maxAnnualEmission(), initialMaxAnnualEmission - reductionAmount);
        assertEq(trust.annualMintedAmount(), 1);
        assertEq(trust.epochMintedAmount(), 1);
        assertEq(trust.annualPeriodStartTime(), startTimestamp + ONE_YEAR);
        assertEq(trust.epochStartTime(), startTimestamp + ONE_YEAR);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setTrustBonding_successful() external {
        address newTrustBonding = makeAddr("newTrustBonding");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit TrustBondingSet(newTrustBonding);
        trust.setTrustBonding(newTrustBonding);

        assertEq(address(trust.trustBonding()), newTrustBonding);
    }

    function test_setTrustBonding_revertsOnZeroAddress() external {
        vm.prank(admin);
        vm.expectRevert(Errors.Trust_ZeroAddress.selector);
        trust.setTrustBonding(address(0));
    }

    function test_setTrustBonding_revertsOnUnauthorized() external {
        vm.prank(unauthorized);
        vm.expectRevert();
        trust.setTrustBonding(makeAddr("newTrustBonding"));
    }

    function test_setMaxEmissionPerEpochBasisPoints_successful() external {
        uint256 newValue = 2000;

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit MaxEmissionPerEpochBasisPointsChanged(newValue);
        trust.setMaxEmissionPerEpochBasisPoints(newValue);

        assertEq(trust.maxEmissionPerEpochBasisPoints(), newValue);
    }

    function test_setMaxEmissionPerEpochBasisPoints_revertsOnInvalidValue() external {
        vm.prank(admin);
        vm.expectRevert(Errors.Trust_InvalidMaxEmissionPerEpochBasisPoints.selector);
        trust.setMaxEmissionPerEpochBasisPoints(BASIS_POINTS_DIVISOR + 1);
    }

    function test_setMaxEmissionPerEpochBasisPoints_revertsOnUnauthorized() external {
        vm.prank(unauthorized);
        vm.expectRevert();
        trust.setMaxEmissionPerEpochBasisPoints(2000);
    }

    function test_setAnnualReductionBasisPoints_successful() external {
        uint256 newValue = 2000;

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit AnnualReductionBasisPointsChanged(newValue);
        trust.setAnnualReductionBasisPoints(newValue);

        assertEq(trust.annualReductionBasisPoints(), newValue);
    }

    function test_setAnnualReductionBasisPoints_revertsOnInvalidValue() external {
        vm.prank(admin);
        vm.expectRevert(Errors.Trust_InvalidAnnualReductionBasisPoints.selector);
        trust.setAnnualReductionBasisPoints(BASIS_POINTS_DIVISOR);
    }

    function test_setAnnualReductionBasisPoints_revertsOnUnauthorized() external {
        vm.prank(unauthorized);
        vm.expectRevert();
        trust.setAnnualReductionBasisPoints(2000);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getTotalMintableForCurrentAnnualPeriod() external view {
        uint256 expectedMintable = trust.maxAnnualEmission() - trust.annualMintedAmount();
        uint256 actualMintable = trust.getTotalMintableForCurrentAnnualPeriod();
        assertEq(actualMintable, expectedMintable);
    }

    function test_getTotalMintableForCurrentAnnualPeriod_returnsZeroAfterYear() external {
        vm.warp(startTimestamp + ONE_YEAR + 1);
        uint256 mintable = trust.getTotalMintableForCurrentAnnualPeriod();
        assertEq(mintable, 0);
    }

    function test_getTotalMintableForCurrentEpoch() external view {
        uint256 expectedMintable = trust.getMaxMintAmountPerEpoch() - trust.epochMintedAmount();
        uint256 actualMintable = trust.getTotalMintableForCurrentEpoch();
        assertEq(actualMintable, expectedMintable);
    }

    function test_getTotalMintableForCurrentEpoch_returnsZeroAfterEpoch() external {
        vm.warp(startTimestamp + epochLength + 1);
        uint256 mintable = trust.getTotalMintableForCurrentEpoch();
        assertEq(mintable, 0);
    }

    function test_getMaxMintAmountPerEpoch() external view {
        uint256 expected = (trust.maxAnnualEmission() * trust.maxEmissionPerEpochBasisPoints()) / BASIS_POINTS_DIVISOR;
        uint256 actual = trust.getMaxMintAmountPerEpoch();
        assertEq(actual, expected);
    }

    function test_getAnnualReductionAmount() external view {
        uint256 expected = (trust.maxAnnualEmission() * trust.annualReductionBasisPoints()) / BASIS_POINTS_DIVISOR;
        uint256 actual = trust.getAnnualReductionAmount();
        assertEq(actual, expected);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_mint_withZeroAnnualReduction() external {
        // Deploy with zero annual reduction
        Trust freshTrust = _deployFreshTrust();
        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            0, // Zero annual reduction
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );

        vm.warp(startTimestamp + ONE_YEAR);

        vm.prank(address(trustBonding));
        freshTrust.mint(alice, 1);

        // Max annual emission should not change
        assertEq(freshTrust.maxAnnualEmission(), maxAnnualEmission);
    }

    function test_mint_withMaximumAnnualReduction() external {
        // Deploy with maximum annual reduction
        Trust freshTrust = _deployFreshTrust();
        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            BASIS_POINTS_DIVISOR - 1, // Maximum annual reduction
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );

        vm.warp(startTimestamp + ONE_YEAR);

        vm.prank(address(trustBonding));
        freshTrust.mint(alice, 1);

        // Max annual emission should be reduced to minimum
        uint256 expectedReduction = (maxAnnualEmission * (BASIS_POINTS_DIVISOR - 1)) / BASIS_POINTS_DIVISOR;
        assertEq(freshTrust.maxAnnualEmission(), maxAnnualEmission - expectedReduction);
    }

    function test_mint_multipleYearReductions() external {
        uint256 initialMaxAnnualEmission = trust.maxAnnualEmission();
        uint256 currentMaxAnnualEmission = initialMaxAnnualEmission;

        for (uint256 i = 0; i < 5; i++) {
            vm.warp(startTimestamp + (ONE_YEAR * (i + 1)));

            uint256 expectedReduction = (currentMaxAnnualEmission * annualReductionBasisPoints) / BASIS_POINTS_DIVISOR;
            currentMaxAnnualEmission -= expectedReduction;

            vm.prank(address(trustBonding));
            trust.mint(alice, 1);

            assertEq(trust.maxAnnualEmission(), currentMaxAnnualEmission);
        }
    }

    function test_mint_exactLimits() external {
        uint256 epochLimit = trust.getMaxMintAmountPerEpoch();
        uint256 annualLimit = trust.maxAnnualEmission();

        // Mint up to the epoch limit in epoch 0
        vm.prank(address(trustBonding));
        trust.mint(alice, epochLimit);

        // Epoch cap hit – next mint this epoch must revert
        vm.prank(address(trustBonding));
        vm.expectRevert(Errors.Trust_EpochMintingLimitExceeded.selector);
        trust.mint(alice, 1);

        uint256 remaining = annualLimit - epochLimit;
        while (remaining > 0) {
            // Move to the next epoch
            vm.warp(block.timestamp + trustBonding.epochLength());

            uint256 toMint = remaining > epochLimit ? epochLimit : remaining;

            vm.prank(address(trustBonding));
            trust.mint(alice, toMint);

            remaining -= toMint;
        }

        // After the loop the annual limit should be fully consumed
        assertEq(trust.annualMintedAmount(), annualLimit);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_integration_withTrustBondingChanges() external {
        // Change epoch length
        trustBonding.setEpochLength(7 days);

        // Move to next epoch with new length
        vm.warp(startTimestamp + epochLength);

        vm.prank(address(trustBonding));
        trust.mint(alice, 1);

        // Epoch should reset, but with old epoch length calculation
        assertEq(trust.epochMintedAmount(), 1);
    }

    function test_integration_eventEmissions() external {
        // Test TrustBondingSet event
        MockTrustBonding newTrustBonding = new MockTrustBonding();
        trustBonding.setEpochLength(epochLength);

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit TrustBondingSet(address(newTrustBonding));
        trust.setTrustBonding(address(newTrustBonding));

        // Test MaxAnnualEmissionChanged event (triggered by annual reduction)
        vm.warp(startTimestamp + ONE_YEAR + 1 days);
        vm.expectEmit(true, false, false, false);
        emit MaxAnnualEmissionChanged(trust.maxAnnualEmission() - trust.getAnnualReductionAmount());
        vm.prank(address(trustBonding));
        trust.mint(alice, 1);

        // Test MaxEmissionPerEpochBasisPointsChanged event
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit MaxEmissionPerEpochBasisPointsChanged(2000);
        trust.setMaxEmissionPerEpochBasisPoints(2000);

        // Test AnnualReductionBasisPointsChanged event
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit AnnualReductionBasisPointsChanged(2000);
        trust.setAnnualReductionBasisPoints(2000);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZING TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_initialize_parameters(
        uint256 maxAnnualEmissionFuzz,
        uint256 maxEmissionPerEpochBasisPointsFuzz,
        uint256 annualReductionBasisPointsFuzz
    ) external {
        maxAnnualEmissionFuzz = bound(maxAnnualEmissionFuzz, 0, MAX_POSSIBLE_ANNUAL_EMISSION);
        maxEmissionPerEpochBasisPointsFuzz = bound(maxEmissionPerEpochBasisPointsFuzz, 1, BASIS_POINTS_DIVISOR);
        annualReductionBasisPointsFuzz = bound(annualReductionBasisPointsFuzz, 0, BASIS_POINTS_DIVISOR - 1);

        Trust freshTrust = _deployFreshTrust();
        freshTrust.initialize(
            address(trustBonding),
            maxAnnualEmissionFuzz,
            maxEmissionPerEpochBasisPointsFuzz,
            annualReductionBasisPointsFuzz,
            initialHypERC20Supply,
            hook,
            ism,
            admin
        );

        assertEq(freshTrust.maxAnnualEmission(), maxAnnualEmissionFuzz);
        assertEq(freshTrust.maxEmissionPerEpochBasisPoints(), maxEmissionPerEpochBasisPointsFuzz);
        assertEq(freshTrust.annualReductionBasisPoints(), annualReductionBasisPointsFuzz);
    }

    function testFuzz_mint_validAmounts(uint256 amount) external {
        uint256 maxMintable = trust.getTotalMintableForCurrentEpoch();
        amount = bound(amount, 1, maxMintable);

        uint256 initialBalance = trust.balanceOf(alice);
        uint256 initialSupply = trust.totalSupply();

        vm.prank(address(trustBonding));
        trust.mint(alice, amount);

        assertEq(trust.balanceOf(alice), initialBalance + amount);
        assertEq(trust.totalSupply(), initialSupply + amount);
    }

    function testFuzz_setMaxEmissionPerEpochBasisPoints_validValues(uint256 value) external {
        value = bound(value, 1, BASIS_POINTS_DIVISOR);

        vm.prank(admin);
        trust.setMaxEmissionPerEpochBasisPoints(value);

        assertEq(trust.maxEmissionPerEpochBasisPoints(), value);
    }

    function testFuzz_setAnnualReductionBasisPoints_validValues(uint256 value) external {
        value = bound(value, 0, BASIS_POINTS_DIVISOR - 1);

        vm.prank(admin);
        trust.setAnnualReductionBasisPoints(value);

        assertEq(trust.annualReductionBasisPoints(), value);
    }

    function testFuzz_timeBoundaries(uint256 timeOffset) external {
        timeOffset = bound(timeOffset, 0, ONE_YEAR * 10);

        vm.warp(startTimestamp + timeOffset);

        // View functions should not revert
        trust.getTotalMintableForCurrentAnnualPeriod();
        trust.getTotalMintableForCurrentEpoch();
        trust.getMaxMintAmountPerEpoch();
        trust.getAnnualReductionAmount();
    }

    function testFuzz_multipleYearReductions(uint256 _years) external {
        _years = bound(_years, 1, 20);

        uint256 currentMaxAnnualEmission = trust.maxAnnualEmission();

        for (uint256 i = 0; i < _years; i++) {
            vm.warp(startTimestamp + (ONE_YEAR * (i + 1)));

            uint256 expectedReduction = (currentMaxAnnualEmission * annualReductionBasisPoints) / BASIS_POINTS_DIVISOR;
            currentMaxAnnualEmission -= expectedReduction;

            vm.prank(address(trustBonding));
            trust.mint(alice, 1);

            assertEq(trust.maxAnnualEmission(), currentMaxAnnualEmission);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deployFreshTrust() internal returns (Trust) {
        Trust implementation = new Trust(decimals, scale, address(mailbox));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), admin, "");
        return Trust(address(proxy));
    }
}
