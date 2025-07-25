// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HypERC20Collateral} from "@hyperlane-xyz/token/HypERC20Collateral.sol";
import {IMailbox} from "@hyperlane-xyz/interfaces/IMailbox.sol";

contract DeployHypERC20Collateral is Script {
    /// @notice Constants
    address public constant multisig = 0xa28d4AAcA48bE54824dA53a19b05121DE71Ef480;
    address public constant trustTokenAddress = 0x6cd905dF2Ed214b22e0d48FF17CD4200C1C6d8A3;
    uint256 public constant scale = 1e18;

    /// @notice Base-specific constants
    address public constant mailbox = 0xeA87ae93Fa0019a82A727bfd3eBd1cFCa8f64f1D;
    address public hook;
    address public ism;

    error UnsupportedChainId();

    function run() external {
        // Allow the script to run only on Base Mainnet
        if (block.chainid != 8453) {
            revert UnsupportedChainId();
        }

        hook = address(IMailbox(mailbox).defaultHook());
        ism = address(IMailbox(mailbox).defaultIsm());

        vm.startBroadcast();

        // Deploy the HypERC20Collateral contract to set the immutable values
        HypERC20Collateral collateralContract = new HypERC20Collateral(trustTokenAddress, scale, mailbox);
        console.log("HypERC20Collateral deployed at: ", address(collateralContract));

        // Initialize the HypERC20Collateral contract
        collateralContract.initialize(hook, ism, multisig);

        vm.stopBroadcast();
    }
}
