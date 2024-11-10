// SPDX-License-Identifier: MIT
pragma solidity  0.8.25;

import { Script } from "forge-std/Script.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract DeployDSC is Script {

    address[] public tokenAddressess;
    address[] public priceFeedAddressess;

    function run() external returns (DecentralizedStableCoin ,DSCEngine, HelperConfig ){

        HelperConfig helperConfig = new HelperConfig();

        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
        ) = helperConfig.activeNetworkConfig();

        tokenAddressess = [weth, wbtc];
        priceFeedAddressess = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        DecentralizedStableCoin decentralizedStableCoin = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(
            tokenAddressess,
            priceFeedAddressess,
            address(decentralizedStableCoin)
        );
        // transfer to ownership ( transferencia de propiedad ) de los tokens a dscEngine
        decentralizedStableCoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (decentralizedStableCoin, dscEngine, helperConfig);
    }
}