// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IMailbox} from "@hyperlane-xyz/interfaces/IMailbox.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Trust} from "src/Trust.sol";

contract DeployTrust is Script {
    /// @notice Hyperlane-specific constants
    uint8 public constant decimals = 18;
    uint256 public constant scale = 1e18;
    uint256 public constant initialSupply = 0;
    address public mailbox;
    address public hook;
    address public ism;

    /// @notice Trust-specific constants
    address public constant multisig = 0xa28d4AAcA48bE54824dA53a19b05121DE71Ef480; // Admin multisig address
    address public constant trustBonding = address(1); // Replace with the actual deployed TrustBonding address
    uint256 public constant maxAnnualEmission = 100_000_000 * 1e18; // 100 million TRUST
    uint256 public constant maxEmissionPerEpochBasisPoints = 10_000; // 100% of max annual emission (no epoch-level restrictions; useful in
    // cases where we want admin multisig to mint any possibly unclaimed rewards, but can always be changed later)
    uint256 public constant annualReductionBasisPoints = 1000; // 10% annual reduction in the annual emission rate

    /// @notice Core contracts
    Trust public trust;
    ProxyAdmin public proxyAdmin;

    /// @notice Custom errors
    error UnsupportedChainId();

    function run() external {
        vm.startBroadcast();

        // Allow the script to run only on Base Sepolia to prevent accidental deployments on mainnet
        // NOTE: When deploying in a production setting, make sure to replace the chain ID with the
        // chain ID of the Intuition L3 rollup, as that is where this token will be used.
        if (block.chainid != 84532) {
            revert UnsupportedChainId();
        }

        mailbox = address(1); // Replace with actual Intuition L3 mailbox address
        hook = address(IMailbox(mailbox).defaultHook());
        ism = address(IMailbox(mailbox).defaultIsm());

        // deploy the ProxyAdmin contract
        proxyAdmin = new ProxyAdmin();
        proxyAdmin.transferOwnership(multisig);

        // deploy the Trust token implementation contract
        trust = new Trust(decimals, scale, mailbox);
        console.log("Trust implementation address: ", address(trust));

        // deploy the Trust token proxy contract
        TransparentUpgradeableProxy trustProxy =
            new TransparentUpgradeableProxy(address(trust), address(proxyAdmin), "");
        trust = Trust(address(trustProxy));
        console.log("Trust token proxy address: ", address(trust));

        // initialize the Trust token
        trust.initialize(
            trustBonding,
            maxAnnualEmission,
            maxEmissionPerEpochBasisPoints,
            annualReductionBasisPoints,
            initialSupply,
            hook,
            ism,
            multisig
        );

        vm.stopBroadcast();
    }
}
