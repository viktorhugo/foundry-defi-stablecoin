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

import { console } from "forge-std/Script.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; 
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

contract DSCEngine is ReentrancyGuard{

    ///////////////////
    //* Errors    //
    ///////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddresessAndPriceFeedAdressessMustBeSameLenght();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferTokenCollateralFailed();

    ///////////////////////
    //* State Variables  //
    //////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // token price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    DecentralizedStableCoin private immutable i_dsc; // DSC contract

    ///////////////////////
    //*    Events       //
    //////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    ///////////////////
    //* Modifiers    //
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) revert DSCEngine__MustBeMoreThanZero();
        _;
    }

    modifier isAllowToken(address addressToken) { // check if token is allowed
        if (s_priceFeeds[addressToken]  == address(0)) revert DSCEngine__NotAllowedToken();
        _;
    }

     ///////////////////
    //* Functions    //
    ///////////////////
    constructor(
        address[] memory tokenAddressess,
        address[] memory priceFeedAddressess,
        address dscAddress // direccion de la moneda estable descentralizada
    ) {
        // USD price feeds
        if (tokenAddressess.length != priceFeedAddressess.length) {
            revert DSCEngine__TokenAddresessAndPriceFeedAdressessMustBeSameLenght();
        }
        // For example ETH / USD BTC / USD,MKR / USD, etc.. vamos a recorrer la matriz de direcciones de token
        // Los tokens que estan permitidos en la plataforma entonces si tienen un feed de precios, estan permitidos
        for (uint256 i = 0; i < tokenAddressess.length; i++) {
            // llenamos el mapping
            s_priceFeeds[tokenAddressess[i]] = priceFeedAddressess[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

     /////////////////////////
    //* External Functions //
    ////////////////////////

     // elegir que tipo de garantia quiere depositar 
    /*
    * @notice follows CEI pattern (verifica las interacciones de los efectos)
    * @param tokenCollateralAdrress the address of the collateral deposit token
    * @param amountCollateral the amount of collateral deposit
    */
    function depositCollateral(
        address tokenCollateralAdrress, 
        uint256 amountCollateral
    ) 
        external 
        moreThanZero(amountCollateral) 
        isAllowToken(tokenCollateralAdrress) // check if tokenCollateralAdrress is allowed
        nonReentrant { // nonReentrant verification (ataques mas comunes en la web3) 
            // es buena practica cuando se ejecuctan contratos externos, ppuede que consuma un poco mas de gas pero es mas seguro

        // 1. hacer una manera de rastrear cuanta garantia alguien ha depositado
        s_collateralDeposited[msg.sender][tokenCollateralAdrress] += amountCollateral;
        // actualizando el estado emitimos un evento
        emit CollateralDeposited(msg.sender, tokenCollateralAdrress, amountCollateral);
        // 2. ahora conseguir los tokens, vamos a nesecitar un wrap al collateral como un ERC20 
        bool success = ERC20(tokenCollateralAdrress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferTokenCollateralFailed();
        }
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