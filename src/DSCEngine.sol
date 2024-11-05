// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.25;

/**
 * @title DSCEngine
 * @author Victor mosquera
 * The engine is desingned to be as minimal as posible, and the tokens maintain a 1 token  == $1 peg
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algoritmically Stable
 * It is similar to DAI had no governance, no fees, and was only backed by wETH and wBTC.
 * Our DSC system should always be "overcollateralized". At no point, should the vallue of all
 * collateral <= the $ backed value of all the DSC.
 * @notice this contract is the core of the DSC System. It handles all the logic for minting and
 * reddeeming DSC, as well as depositing and withdrawing collateral.
 * @notice this contract is VERY loosely based on the MakerDAO (DAI) system.
 */

import { console } from "forge-std/Script.sol";

contract DSCEngine {

    ///////////////////
    //* Errors    //
    ///////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddresessAndPriceFeedAdressessMustBeSameLenght();


    ///////////////////////
    //* State Variables  //
    //////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // token price feed


    ///////////////////
    //* Modifiers    //
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    // modifier isAllowToken(address addressToken) { // check if token is allowed
    //     if (amount <= 0) {
    //         revert DSCEngine__MustBeMoreThanZero();
    //     }
    //     _;
    // }


     ///////////////////
    //* Functions    //
    ///////////////////
    constructor(
        address[] memory tokenAddressess,
        address[] memory priceFeedAddressess,
        address dscAddress
    ) {
        // USD price feeds
        if (tokenAddressess.length != priceFeedAddressess.length) {
            revert DSCEngine__TokenAddresessAndPriceFeedAdressessMustBeSameLenght();
        }
        // For example ETH / USD BTC / USD,MKR / USD, etc.. vamos a recorrer la matriz de direcciones de token
        for (uint256 i = 0; i < tokenAddressess.length; i++) {
            s_priceFeeds[tokenAddressess[i]] = priceFeedAddressess[i];
        }
    }


     /////////////////////////
    //* External Functions //
    ////////////////////////

     // elegir que tipo de garantia quiere depositar 
    /*
    * @param tokenCollateralAdrress the address of the collateral deposit token
    * @param amountCollateral the amount of collateral deposit
    */
    function depositCollateral(
        address tokenCollateralAdrress, 
        uint256 amountCollateral
    ) moreThanZero(amountCollateral) external {

    }

    function depositCollateralAndMintDsc() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function burnDsc() external {}

    // La razon por la que simpre vamos a tener mas garantias, si el valor de su collateral cae demasiado hay que liquidarlo
    // La idea es establecer un threshold de collateral para liquidadacion.
    function liquidate() external {}

    // permite ver que tn saludables estan las personas
    function getHealthFactor() external view returns (uint256) {}


}