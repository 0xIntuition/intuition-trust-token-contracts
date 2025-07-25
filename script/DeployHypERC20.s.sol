// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HypERC20} from "@hyperlane-xyz/token/HypERC20.sol";
import {IMailbox} from "@hyperlane-xyz/interfaces/IMailbox.sol";

contract DeployHypERC20 is Script {
    /// @notice Constants
    address public constant multisig = 0xa28d4AAcA48bE54824dA53a19b05121DE71Ef480;
    string public constant name = "Intuition";
    string public constant symbol = "TRUST";
    uint8 public constant decimals = 18;
    uint256 public constant scale = 1e18;
    uint256 public constant initialSupply = 0;

    /// @notice Chain-specific constants
    address public mailbox;
    address public hook;
    address public ism;

    uint256 public chainId;

    error UnsupportedChainId();

    function run() external {
        chainId = block.chainid;

        // Allow the script to run only on Arbitrum Mainnet or ETH Mainnet
        if (chainId != 42_161 && chainId != 1) {
            revert UnsupportedChainId();
        }

        if (chainId == 42_161) {
            mailbox = 0x979Ca5202784112f4738403dBec5D0F3B9daabB9;
            hook = address(IMailbox(mailbox).defaultHook());
            ism = address(IMailbox(mailbox).defaultIsm());
        } else if (chainId == 1) {
            mailbox = 0xc005dc82818d67AF737725bD4bf75435d065D239;
            hook = address(IMailbox(mailbox).defaultHook());
            ism = address(IMailbox(mailbox).defaultIsm());
        }

        vm.startBroadcast();

        // Deploy the HypERC20 token to set the immutable values
        HypERC20 syntheticToken = new HypERC20(decimals, scale, mailbox);
        console.log("HypERC20 deployed at: ", address(syntheticToken));

        // Initialize the HypERC20 token
        syntheticToken.initialize(initialSupply, name, symbol, hook, ism, multisig);

        vm.stopBroadcast();
    }
}
