forge script script/DeployTestTrust.s.sol:DeployTestTrust --fork-url $BASE_SEPOLIA_RPC_URL

cast send 0x2F17ECB6D6ca4CAdE6e1301711689CF0b85dF387 "mint(address,uint256)" 0x5Ee4df0596E527Fd7a7C1059639e6cad483DcEc0 1000000000000000000000 --rpc-url $BASE_SEPOLIA_RPC_URL --interactive