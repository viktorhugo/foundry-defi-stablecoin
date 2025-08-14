// SPDX-License-Identifier: MIT
//* este controlador va a limitar la forma en que llamamos funciones
pragma solidity ^0.8.30;
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import { console } from "lib/forge-std/src/Script.sol";

import { MockV3Aggregator } from "../../test/mocks/MockV3Aggregator.sol";

contract  Handler is Test {

    DSCEngine dscEngine;
    DecentralizedStableCoin decentralizedStableCoin;
    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 public timesMintIsCalled = 0;
    address[] public usersWithCollateralDeposited;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; //* esto obtine el maximo de un tipo de 96 bits

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _decentralizedStableCoin) {
        dscEngine = _dscEngine;
        decentralizedStableCoin = _decentralizedStableCoin;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        //* ahora tenemos un feed de precios eth en USD
        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    //* desposit collateral
    //* queremos que deposite garantias aleatorias que sean garantias validas
    function mintAndDepositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        //* lo que vamos hacer con este seed es que elegirenos entre nuestras dos collaterals (weth y wbtc)
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE); //* limita el rango
        ERC20Mock collateral = _getRandomCollateralFromSeed(collateralSeed);

        //* nesecitamos aprobar el protocolo para depositar la garantia, hagamos un prank (broma)
        vm.startPrank(msg.sender); //* msg.sender es que es quien llama a la funcion (remitente)
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        //* double push
        usersWithCollateralDeposited.push(msg.sender);
    }

    //* redeem collateral
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        //* lo que vamos hacer con este seed es que elegirenos entre nuestras dos collaterals (weth y wbtc)
        ERC20Mock collateral = _getRandomCollateralFromSeed(collateralSeed);
        vm.startPrank(msg.sender); //* msg.sender es que es quien llama a la funcion (remitente)
        //* obtenemos el balance de la garantia del usuario
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        //* vamos a vincualr el monto de la garantia que vamos a redimir con el monto maximo que podemos redimir
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        //* redimimos la garantia
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    //* mint DSC
    function mintDsc(uint256 addressSeed, uint256 amountDscToMint) public {
        //* para que podamos mintar DSC solo si es con una direccion que tiene la garantia depositada
        //* por que es imposible que alguien acuñe dsc sin haber depositado garantias
        if(usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length]; // obtenemos un sender que ya deposito garantias
        //* random amount
        amountDscToMint = bound(amountDscToMint, 1, MAX_DEPOSIT_SIZE);
        //* verificar que el monto de DSC sea mayor que el valor del sistema(para que no revert el health factor)
        //* solo deberiamos poder mint DSC si la cantidad es menor que la garantia (collateral)
        (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) = dscEngine.getAccountInformation(address(sender));
        int256 maxDscToMint = ( int256(totalCollateralValueInUSD) / 2 ) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        console.log('maxDscToMint', maxDscToMint);
        amountDscToMint = bound(amountDscToMint, 0, uint256(maxDscToMint));
        if (amountDscToMint == 0) {
            return;
        }
        vm.startPrank(sender); //* msg.sender es que es quien llama a la funcion (remitente)
        dscEngine.mintDsc(amountDscToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    //* esto rompe nuestro conjunto de pruebas invariantes y esto seria 100% B,
    //* en una auditoria  de smart contracts dicen, hey si el precio de un activo
    //* cae tambien rapidamente el sistema tambien se rompe
    // function updateCollateralPrice(uint96 newPrice) public {
    //     console.log('updateCollateralPrice', newPrice);
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function invariant_gettersShouldNptRevert() public view {
        dscEngine.getLiquidationBonus();
        dscEngine.getCollateralTokens();
        dscEngine.getMinHealthFactor();
        dscEngine.getLiquidationThreshold();
        dscEngine.getDsc();
        dscEngine.getPrecision();
        dscEngine.getAdditionalFeedPrecision();
        dscEngine.getLiquidationPrecision();
    }

    // Helper functions
    function _getRandomCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        //* solo podemos obtener un tipo de garantia valido
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }



}