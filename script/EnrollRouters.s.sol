// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {HypERC20} from "@hyperlane-xyz/token/HypERC20.sol";
import {HypERC20Collateral} from "@hyperlane-xyz/token/HypERC20Collateral.sol";
import {TypeCasts} from "@hyperlane-xyz/libs/TypeCasts.sol";

/// NOTE: This script only enrolls the routers between Base <> Arbitrum <> Ethereum, since Intuition L3 is not yet deployed.
contract EnrollRouters is Script {
    using TypeCasts for address;

    uint256 public chainId;

    error UnsupportedChainId();

    function run() external {
        vm.startBroadcast();

        address multisig = 0xa28d4AAcA48bE54824dA53a19b05121DE71Ef480; // Admin Safe (address is the same across all chains)

        HypERC20Collateral baseCollateral = HypERC20Collateral(address(1)); // Replace with the actual HypERC20Collateral address on Base
        HypERC20 arbSynthetic = HypERC20(address(2)); // Replace with the actual HypERC20 address on Arbitrum
        HypERC20 mainnetSynthetic = HypERC20(address(3)); // Replace with the actual HypERC20 address on Mainnet

        uint32 baseDomain = 8453;
        uint32 arbDomain = 42_161;
        uint32 mainnetDomain = 1;

        chainId = block.chainid;

        if (chainId != 8453 && chainId != 42161 && chainId != 1) {
            revert UnsupportedChainId();
        }

        // 1. Enroll routers on Base
        if (chainId == 8453) {
            console.log("=== Enrolling routers on Base ===");
            baseCollateral.enrollRemoteRouter(arbDomain, address(arbSynthetic).addressToBytes32());
            console.log("Base -> Arbitrum route enrolled");

            baseCollateral.enrollRemoteRouter(mainnetDomain, address(mainnetSynthetic).addressToBytes32());
            console.log("Base -> Mainnet route enrolled");

            baseCollateral.transferOwnership(multisig);
            console.log("Base collateral ownership transferred to multisig");
        }

        // 2. Enroll routers on Arbitrum
        if (chainId == 42_161) {
            console.log("\n=== Enrolling routers on Arbitrum ===");
            arbSynthetic.enrollRemoteRouter(baseDomain, address(baseCollateral).addressToBytes32());
            console.log("Arbitrum -> Base route enrolled");

            arbSynthetic.enrollRemoteRouter(mainnetDomain, address(mainnetSynthetic).addressToBytes32());
            console.log("Arbitrum -> Mainnet route enrolled");

            arbSynthetic.transferOwnership(multisig);
            console.log("Arbitrum synthetic ownership transferred to multisig");
        }

        // 3. Enroll routers on Mainnet
        if (chainId == 1) {
            console.log("\n=== Enrolling routers on Mainnet ===");
            mainnetSynthetic.enrollRemoteRouter(baseDomain, address(baseCollateral).addressToBytes32());
            console.log("Mainnet -> Base route enrolled");

            mainnetSynthetic.enrollRemoteRouter(arbDomain, address(arbSynthetic).addressToBytes32());
            console.log("Mainnet -> Arbitrum route enrolled");

            mainnetSynthetic.transferOwnership(multisig);
            console.log("Mainnet synthetic ownership transferred to multisig");
        }

        vm.stopBroadcast();
    }
}
