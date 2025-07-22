// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {HypERC20} from "@hyperlane-xyz/token/HypERC20.sol";
import {HypERC20Collateral} from "@hyperlane-xyz/token/HypERC20Collateral.sol";
import {TypeCasts} from "@hyperlane-xyz/libs/TypeCasts.sol";

contract EnrollRouters is Script {
    using TypeCasts for address;

    function run() external {
        // Load deployments
        string memory baseJson = vm.readFile("./deployments/base.json");
        string memory arbJson = vm.readFile("./deployments/arbitrum.json");
        string memory mainnetJson = vm.readFile("./deployments/mainnet.json");

        address baseCollateral = vm.parseJsonAddress(baseJson, ".collateral");
        address arbSynthetic = vm.parseJsonAddress(arbJson, ".synthetic");
        address mainnetSynthetic = vm.parseJsonAddress(mainnetJson, ".synthetic");

        uint32 baseDomain = uint32(vm.envUint("BASE_DOMAIN"));
        uint32 arbDomain = uint32(vm.envUint("ARBITRUM_DOMAIN"));
        uint32 mainnetDomain = uint32(vm.envUint("MAINNET_DOMAIN"));

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");

        // 1. Enroll on Base
        console.log("=== Enrolling routers on Base ===");
        vm.createSelectFork(vm.envString("BASE_RPC"));
        vm.startBroadcast(deployerKey);

        HypERC20Collateral(baseCollateral).enrollRemoteRouter(arbDomain, arbSynthetic.addressToBytes32());
        console.log("Base -> Arbitrum route enrolled");

        HypERC20Collateral(baseCollateral).enrollRemoteRouter(mainnetDomain, mainnetSynthetic.addressToBytes32());
        console.log("Base -> Mainnet route enrolled");

        vm.stopBroadcast();

        // 2. Enroll on Arbitrum
        console.log("\n=== Enrolling routers on Arbitrum ===");
        vm.createSelectFork(vm.envString("ARBITRUM_RPC"));
        vm.startBroadcast(deployerKey);

        HypERC20(arbSynthetic).enrollRemoteRouter(baseDomain, baseCollateral.addressToBytes32());
        console.log("Arbitrum -> Base route enrolled");

        HypERC20(arbSynthetic).enrollRemoteRouter(mainnetDomain, mainnetSynthetic.addressToBytes32());
        console.log("Arbitrum -> Mainnet route enrolled");

        vm.stopBroadcast();

        // 3. Enroll on Mainnet
        console.log("\n=== Enrolling routers on Mainnet ===");
        vm.createSelectFork(vm.envString("MAINNET_RPC"));
        vm.startBroadcast(deployerKey);

        HypERC20(mainnetSynthetic).enrollRemoteRouter(baseDomain, baseCollateral.addressToBytes32());
        console.log("Mainnet -> Base route enrolled");

        HypERC20(mainnetSynthetic).enrollRemoteRouter(arbDomain, arbSynthetic.addressToBytes32());
        console.log("Mainnet -> Arbitrum route enrolled");

        vm.stopBroadcast();
    }
}
