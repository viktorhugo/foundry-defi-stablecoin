// SPDX-License-Identifier: MIT
pragma solidity  0.8.25;

import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { console } from "forge-std/Script.sol";

//* obtener el valor del cuenta de garantia
//* asegurarnos de que el mint funcione
//* asegurarnos de que el constructor funcione
//* asegurarnos de que el deposit funcione
contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    DecentralizedStableCoin decentralizedStableCoin;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;


    function setUp() public {
        deployer = new DeployDSC();
        (decentralizedStableCoin, dscEngine, helperConfig ) = deployer.run();
        // GET network config
        ( wethUsdPriceFeed, wbtcUsdPriceFeed, weth,wbtc, ) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        console.log('MINT STARTING BALANCE: ', STARTING_ERC20_BALANCE);
    }


    ////////////////////////
    //* Price Tests      //
    //////////////////////

    function testGetUsdValue() public view{
        uint256 ethAmout = 15e18;
        // 15e18 * 3000/ETH = 45000E18
        uint256 expectedValue = 45000e18;
        uint256 usdValue = dscEngine.getUsdValue(weth, ethAmout);
        console.log('usdValue', usdValue);
        assertEq(expectedValue, usdValue);
    }

     /////////////////////////////////
    //* DepositCollateral Tests    //
    ////////////////////////////////

    function testRevertIfDepositCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(address(weth), 0);
        vm.stopPrank();
    }
}
