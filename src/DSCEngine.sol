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

pragma solidity ^0.8.24;

import { console } from "forge-std/Script.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; 
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AggregatorV3Interface } from "@chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__TransferTokenFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    ///////////////////////
    //* State Variables  //
    //////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% nesecitamos tener el doble de la garantia que el DSC MINTED
    uint256 private constant LIQUIDATION_PRECISION = 100; // 200% nesecitamos tener el doble de la garantia que el DSC MINTED
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; // token price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_allowedCollateralTokens; // tokens permitidos
    
    DecentralizedStableCoin private immutable i_dsc; // DSC contract

    ///////////////////////
    //*    Events       //
    //////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event TransferTokenCollateral(address indexed user, address indexed token, uint256 amount);
    event TransferTokenCollateralFromRedeem(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 amount);

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
            s_allowedCollateralTokens.push(tokenAddressess[i]); // add token to allow list
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

     /////////////////////////
    //* External Functions //
    ////////////////////////

    /*
     * @param tokenCollateralAddress the address of the collateral deposit token
     * @param amountCollateral the amount of collateral deposit
     * @param amountDscToMint the amount of DSC to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountDscToMint
    ) external {
        // 1. deposit collateral
        depositCollateral(tokenCollateralAddress, amountCollateral);
        // 2. mint DSC
        mintDsc(amountDscToMint);
    }

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
        public 
        moreThanZero(amountCollateral) 
        isAllowToken(tokenCollateralAdrress) // check if tokenCollateralAdrress is allowed
        nonReentrant { // nonReentrant verification (ataques mas comunes en la web3) es buena practica cuando se ejecuctan contratos externos,
                    //  puede que consuma un poco mas de gas pero es mas seguro
        // 1. hacer una manera de rastrear cuanta garantia alguien ha depositado
        s_collateralDeposited[msg.sender][tokenCollateralAdrress] += amountCollateral;
        // actualizando el estado emitimos un evento
        emit CollateralDeposited(msg.sender, tokenCollateralAdrress, amountCollateral);
        // 2. ahora conseguir los tokens, vamos a nesecitar un wrap al collateral como un ERC20 
        bool success = ERC20(tokenCollateralAdrress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferTokenFailed();
        }
        // Emitimos un evento de transferencia de tokens
        emit TransferTokenCollateral(msg.sender, tokenCollateralAdrress, amountCollateral);
        // luego verificamos el health factor is Broken (entonces si el health factor is broken se reverts las transacciones)
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * 
     * @notice follow CEI
     * @param amountDscToMint the amount of DSC to mint
     * @notice the must have more collateral value than the minimum thereshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant { // verificar si el valor del collateral > DSC amount
        s_DSCMinted[msg.sender] += amountDscToMint;
        // check if they minter too much collateral (revert)
        _revertIfHealthFactorIsBroken(msg.sender);
        // mint DSC
        bool responseMinted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!responseMinted) {
            revert DSCEngine__MintFailed();
        }
    }

    function redeemCollateralForDsc() external { // comom vamos a mover tokens simplemente haremos operaciones no reentrantes

    }

    //* orden para redimir collateral
    // 1. su factor de salud tiene que ser > 1 despues de retirar la garantia
    // DRY: Dont Repeat Yourself
    // CEI: Check, Effects, Interactions
    function redeemCollateral( address tokenCollateralAddress, uint256 amountCollateral) 
    external moreThanZero(amountCollateral) 
    nonReentrant { // comom vamos a mover tokens simplemente haremos operaciones no reentrantes
        // retirar el collateral (garantia) y actualizar nuestra contabilidad, si intenta hacer sacar mas de lo que tiene (100 - 1000 ) ejecuta el REVERT
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = ERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferTokenFailed();
        }
        emit TransferTokenCollateralFromRedeem(msg.sender, tokenCollateralAddress, amountCollateral);

    }

    function burnDsc() external {}

    // La razon por la que simpre vamos a tener mas garantias, si el valor de su collateral cae demasiado hay que liquidarlo
    // La idea es establecer un threshold de collateral para liquidadacion.
    function liquidate() external {}

    // permite ver que tn saludables estan las personas
    function getHealthFactor() external view returns (uint256) {}

    //////////////////////////////////////////////////
    //*  Private & Internal view Functions          //
    //////////////////////////////////////////////////
    // internal functions utilizamos el _antecesdido para declararlas
    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUSD = getAccountColllateralValue(user); // valor total de toas las garantias del usuario
        return (totalDscMinted, totalCollateralValueInUSD);
    }

    /*
     * @notice Retorna que tan cerca de la liquiation esta un usuario
     * if user health factor < 1 -> liquidate
    */
    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        // Necesitaremos obtener el valor total de la garantia para asegurarnos de que el valor sea mayor que el total de DSC minted
        // total DSC minted -total collateral Value
        (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) = _getAccountInformation(user);
        //monto de collateral ajustado para el threshold
        uint256 collateralAjusted = (totalCollateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        //  $1000 ETH -> 100 DSC
        // 1000 * 0.5 = 500 / 100 = 5 > 1
        // se nesecita tener mas del doble de collateral
        return (collateralAjusted * PRECISION ) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Ceck health factor (do they have enought collateral?)
        uint256 userHealthFactor = _healthFactor(user);
        // 2. Revert if they don't
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }

    }

     //////////////////////////////////////////////////
    //*     public & external view Functions        //
    //////////////////////////////////////////////////

    function getAccountColllateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        // nesecitamos recorrer cada collateral TOKENS, obtener la cantidad que han depositado
        //  y luego asignelo al precio para obtener el valor en USD
        for (uint256 i = 0; i < s_allowedCollateralTokens.length; i++) {
            address addressToken = s_allowedCollateralTokens[i]; // address of token
            uint256 amountDeposited = s_collateralDeposited[user][addressToken]; // amount of token deposited by user
            totalCollateralValueInUSD+= getUsdValue(addressToken, amountDeposited);
            // simplemente sumamos el valor en USD de cada uno de los tokens
        }
        return totalCollateralValueInUSD;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        /**
         * Network: Sepolia
         * Data Feed: ETH/USD
         * Address: 0x694AA1769357215DE4FAC081bf1f309aDC325306
         */
        // obtenemos el precio del token
        // priceFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306)
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        ( ,int256 answer, , , ) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // the returned value from CL will be 1000 * 1e8
        uint256 amountInUSD = uint256(answer) * ADDITIONAL_FEED_PRECISION * amount;
        return amountInUSD / PRECISION; 
    }
}