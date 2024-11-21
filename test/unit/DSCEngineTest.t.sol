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


    /////////////////////////
    //* Constructor Tests //
    ///////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function testRevertsIfTokenLengthDoesMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        // expect revert
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine( tokenAddresses, priceFeedAddresses, address(decentralizedStableCoin) );
    }


    ////////////////////////
    //* Price Tests      //
    //////////////////////

    function testGetUsdValue() public view{
        uint256 ethAmount = 15e18;
        // 15e18 * 3000/ETH = 45000E18
        uint256 expectedValue = 45000e18;
        uint256 usdValue = dscEngine.getUsdValue(weth, ethAmount);
        console.log('usdValue', usdValue);
        console.log('expectedValue', expectedValue);
        assertEq(expectedValue, usdValue);
    }

    function testGetTokenAmountFromUsd() public view{
        uint256 usdAmountInWei = 300 ether;
        // $3.000 / ETH, $300
        uint256 expectedValue = 0.1 ether;
        uint256 actualWethValue = dscEngine.getTokenAmountFromUsd(weth, usdAmountInWei);
        console.log('actualWeth', actualWethValue);
        console.log('expectedValue', expectedValue);
        assertEq(expectedValue, actualWethValue);
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

    function testRevertsWithUnapprovedCollateral() public depositedCollateral { // tratar de depositar un token que no esta permitido
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(address(weth), AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) = dscEngine.getAccountInformation(USER);
        console.log('totalDscMinted', totalDscMinted);
        console.log('totalCollateralValueInUSD', totalCollateralValueInUSD);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositedCollateralAmount = dscEngine.getTokenAmountFromUsd(weth, totalCollateralValueInUSD);
        console.log('expectedDepositedCollateralAmount', expectedDepositedCollateralAmount);
        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(expectedDepositedCollateralAmount, AMOUNT_COLLATERAL);
    }

}
