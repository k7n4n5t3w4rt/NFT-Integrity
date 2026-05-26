// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../contracts/NFTIntegrity.sol";
import "forge-std/Script.sol";

/// @title DeployNFTIntegrity
/// @notice Deploys the NFTIntegrity contract with role-based access control.
///
/// Usage:
///   forge script script/DeployNFTIntegrity.s.sol --broadcast --rpc-url $RPC_URL
///
/// Environment variables:
///   MINTER_ADDRESS  — granted MINTER_ROLE
///   MANIFEST_ADDR   — granted MANIFEST_UPDATER_ROLE
///   DERIVATIVE_ADDR — granted DERIVATIVE_MANAGER_ROLE
///   NFT_NAME        — token name (default: "NFTIntegrity Collection")
///   NFT_SYMBOL      — token symbol (default: "INTEGRITY")
///
/// Note: The deployer address (msg.sender) becomes owner / DEFAULT_ADMIN_ROLE.
contract DeployNFTIntegrity is Script {

    function run() external {
        string memory name     = vm.envOr("NFT_NAME",     string("NFTIntegrity Collection"));
        string memory symbol   = vm.envOr("NFT_SYMBOL",   string("INTEGRITY"));

        address minter       = vm.envOr("MINTER_ADDRESS",   msg.sender);
        address manifestAddr = vm.envOr("MANIFEST_ADDR",    msg.sender);
        address derivAddr    = vm.envOr("DERIVATIVE_ADDR",  msg.sender);

        vm.startBroadcast();

        NFTIntegrity nft = new NFTIntegrity(
            name,
            symbol,
            minter,
            manifestAddr,
            derivAddr
        );

        vm.stopBroadcast();

        console.log("NFTIntegrity deployed at:", address(nft));
        console.log("  Name:               ", name);
        console.log("  Symbol:             ", symbol);
        console.log("  Owner (admin):      ", msg.sender);
        console.log("  MINTER_ROLE:        ", minter);
        console.log("  MANIFEST_UPDATER:   ", manifestAddr);
        console.log("  DERIVATIVE_MANAGER: ", derivAddr);
    }
}
