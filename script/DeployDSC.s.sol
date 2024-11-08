// SPDX-License-Identifier: MIT
pragma solidity  0.8.24;

import { Script } from "forge-std/Script.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";

contract DeployDSC is Script {
    // HelperConfig public helperConfig;
    function run() external returns (DecentralizedStableCoin ,DSCEngine){
        vm.startBroadcast();
        // DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        // DSCEngine dscEngine = new DSCEngine(address(dsc));
        // deploy your contract here...
        vm.stopBroadcast();
    }
}