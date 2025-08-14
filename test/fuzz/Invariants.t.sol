// SPDX-License-Identifier: MIT

//* what are our invariants?
//* cuales son la propiedades del sistema que siempre deben cumplirse?

//* 1. the total supply of DSC should be less than total value of the collateral
//*  aca tenemos una invariante que podemos probar y deberiamos lanzar un monton de variables aleatorias(funciones intentar romper)

//* 2. Getter view functions should never revert <-- esto es un invariancia perecedera(evergreen invariant)

pragma solidity ^0.8.30;
import {Test} from "lib/forge-std/src/Test.sol";
import { StdInvariant } from "lib/forge-std/src/StdInvariant.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { console } from "lib/forge-std/src/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { Handler } from "./Handler.t.sol";

contract Invariants is StdInvariant, Test  {

    DeployDSC deployer;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    DecentralizedStableCoin decentralizedStableCoin;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (decentralizedStableCoin, dscEngine, helperConfig ) = deployer.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();
        // targetContract(address(dscEngine));
        //* hey, no llames a redeem the collateral a menos que haya collateral para redeem
        //* solo llama a canjear garantia cuando haya garantia alli
        // * entonces vanos a crear un handler que maneje la forma en hacer las llamadas al DSC
        handler = new Handler(dscEngine, decentralizedStableCoin);
        //* recuerda que cuando se trabaja con invariantes, esto se llamara contract con una tonelada de diferentes 
        //* functions y un monton de llamadas diferentes, sin embargo tambien los llamara con direcciones aleatorias
        targetContract(address(handler)); 
    }

    //* ahora podremos agregar nuestra invariante
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        //* queremos obtener el valor de todos las collaterals en el protocolo
        //* comparelo con toda la deuda (DSC)
        uint256 totalSupply = decentralizedStableCoin.totalSupply(); //* este es todo suministro de DSC en el protocolo
        console.log(" => InvariantTest - totalSupply", totalSupply );
        uint256 totalWthDeposited = IERC20(weth).balanceOf(address(dscEngine)); //* esto es el total de weth depositado en este contrato
        console.log(" => InvariantTest - totalWthDeposited", totalWthDeposited);
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine)); //* esto es el total de wbtc depositado en este contrato
        console.log(" => InvariantTest - totalBtcDeposited", totalBtcDeposited);

        uint256 wethValueUSD = dscEngine.getUsdValue(weth, totalWthDeposited);
        console.log(" => InvariantTest - wethValueUSD: $", wethValueUSD / 1e18);
        uint256 wbtcValueUSD = dscEngine.getUsdValue(wbtc, totalBtcDeposited);
        console.log(" => InvariantTest - wbtcValueUSD: $", wbtcValueUSD / 1e18);
        console.log(" => InvariantTest - Times mint is called: ", handler.timesMintIsCalled());

        console.log(" => InvariantTest - wethValueUSD + wbtcValueUSD: $", (wethValueUSD + wbtcValueUSD) / 1e18);
        //* si el total de la deuda es mayor que el total de la deuda, entonces la invariante se rompe
        assert(wethValueUSD + wbtcValueUSD >= totalSupply);
        //* si pasa entonces, quiere decir que no hay forma de que podamos logara que la oferta total sea menor
    }
}