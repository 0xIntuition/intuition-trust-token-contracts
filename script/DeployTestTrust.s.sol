// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";

import {Trust} from "src/Trust.sol";
import {TestTrust} from "src/TestTrust.sol";

/* To run this:
forge script script/DeployTestTrust.s.sol:DeployTestTrust \
--broadcast \
--verify \
--etherscan-api-key $ETHERSCAN_API_KEY
*/
contract DeployTestTrust is Script {
    /// @notice Custom errors
    error UnsupportedChainId();

    function run() external {
        vm.createSelectFork(vm.envString("BASE_SEPOLIA_RPC_URL"));
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        if (block.chainid != 84_532) {
            revert UnsupportedChainId();
        }

        TestTrust testTrust = new TestTrust(vm.envAddress("ADMIN_ADDRESS"));
        console.log("TestTrust token address: ", address(testTrust));

        vm.stopBroadcast();
    }
}
