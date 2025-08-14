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

pragma solidity ^0.8.30;

import { console } from "forge-std/Script.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; 
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AggregatorV3Interface } from "@chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { OracleLib } from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Victor Mosquera
 * The engine is designed to be as minimal as possible, and the tokens maintain a 1 token  == $1 peg
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 * It is similar to DAI had no governance, no fees, and was only backed by wETH and wBTC.
 * Our DSC system should always be "overcollateralized". At no point, should the value of all
 * collateral <= the $ backed value of all the DSC.
 * @notice this contract is the core of the DSC System. It handles all the logic for minting and
 * redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice this contract is VERY loosely based on the MakerDAO (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {

    ////////////////////
    //* Errors       //
    ///////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferTokenFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ////////////////////
    //* Types       //
    ///////////////////
    using OracleLib for AggregatorV3Interface; //* usemos OracleLib para AggregatorV3Interface

    ///////////////////////
    //* State Variables  //
    //////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% nesecitamos tener el doble de la garantia que el DSC MINTED
    uint256 private constant LIQUIDATION_PRECISION = 100; // 200% nesecitamos tener el doble de la garantia que el DSC MINTED
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // means a 10% bonus

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
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    ///////////////////
    //* Modifiers    //
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) revert DSCEngine__MustBeMoreThanZero();
        _;
    }

    modifier isAllowToken(address addressToken) { // check if token is allowed
        
        if (s_priceFeeds[addressToken]  == address(0)) { 
            console.log('|=| s_priceFeeds[addressToken]', s_priceFeeds[addressToken]);
            console.log('|=| address(0)', address(0));
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress // direccion de la moneda estable descentralizada
    ) {
        console.log("|= DSCEngine =| tokenAddresses.length", tokenAddresses.length);
        console.log("|= DSCEngine =| priceFeedAddresses.length", priceFeedAddresses.length);
        // USD price feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // For example ETH / USD BTC / USD,MKR / USD, etc.. vamos a recorrer la matriz de direcciones de token
        // Los tokens que estan permitidos en la plataforma entonces si tienen un feed de precios, estan permitidos
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            // llenamos el mapping
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_allowedCollateralTokens.push(tokenAddresses[i]); // add token to allow list
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
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) 
        public 
        moreThanZero(amountCollateral) 
        isAllowToken(tokenCollateralAddress) // check if tokenCollateralAdrress is allowed
        nonReentrant { // nonReentrant verification (ataques mas comunes en la web3) es buena practica cuando se ejecuctan contratos externos,
                    //  puede que consuma un poco mas de gas pero es mas seguro
        // 1. hacer una manera de rastrear cuanta garantia alguien ha depositado
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // actualizando el estado emitimos un evento
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // 2. ahora conseguir los tokens, vamos a nesecitar un wrap al collateral como un ERC20 
        bool success = ERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferTokenFailed();
        }
        // Emitimos un evento de transferencia de tokens
        emit TransferTokenCollateral(msg.sender, tokenCollateralAddress, amountCollateral);
        // luego verificamos el health factor is Broken (entonces si el health factor is broken se reverts las transacciones)
        console.log('total Collateral Value In USD: $', amountCollateral / 1e18);
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

    /*
    * @param tokenCollateralAddress the address of the collateral to reedem 
    * @param amountCollateral the amount of collateral to reedem 
    * @param amountDscToBurn the amount of DSC to burn
    *   Esta function quema y canjea la garantia subyacebte en una sola transaccion
    */
    function redeemCollateralForDsc( address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) 
        public moreThanZero(amountCollateral)
        moreThanZero(amountDscToBurn) 
    { // comom vamos a mover tokens simplemente haremos operaciones no reentrantes
            // first burn DSC
            burnDsc(amountDscToBurn);
            // then redeem collateral
            redeemCollateral(tokenCollateralAddress, amountCollateral);
            // redeemCollateral already checks health factor
    }

    //* orden para redimir collateral
    // 1. su factor de salud tiene que ser > 1 despues de retirar la garantia
    // DRY: Dont Repeat Yourself
    // CEI: Check, Effects, Interactions
    function redeemCollateral( address tokenCollateralAddress, uint256 amountCollateral) 
        public 
        moreThanZero(amountCollateral) 
        nonReentrant // comom vamos a mover tokens simplemente haremos operaciones no reentrantes
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(tokenCollateralAddress);
        emit TransferTokenCollateralFromRedeem(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    // $100 ETH -> $20 DSC
    // if withdraw 100 ETH has health factor revert (Break), entoces debo primero burn DSC y luego redeem de los 100 ETH
    // 1. burn DSC
    // 2. redeem ETH
    // Do we need to check if this break health factor?
    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // no creo que esto suceda alguna vez.
    }

    // La razon por la que simpre vamos a tener mas garantias, si el valor de su collateral cae demasiado hay que liquidarlo
    // La idea es establecer un threshold de collateral para liquidadacion.
    // * Esta function de liquidacion es la clave que sostiene todo este  sistema conjunto
    // entonces decimos que si alguien tiene casi poco de collateral, entonces le pagaramos para liquidar
    //* $75 esta respaldando(backing) $50 DSC es mucho mas bajo del umbral de 50% entoces se liquida
    //* el liquidador toma el collateral de 75% y paga los $50 de DSC y quema los $50 de DSC
    
    /*
     * @param collateralAdress collateral Adress to liquidate from the user
     * @param user the address of the user has broken the health factor. their _healthFactor should be bellow MIN_HEALTH_FACTOR
     * @param amountToCover the amount of DSC you want to burn to improve the user's health factor
     * @notice you can partialy liquidate a user
     * @notice you will get a liquitation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would bug be if the protocol were 100% or less collateralized, then we wouldn't be able to incentive liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * CIE: Check, Effects, Interactions
     *
    */
    function liquidate(address collateralAdress, address user, uint256 debToCover) 
        external 
        moreThanZero(debToCover)
        nonReentrant {
        // se podran rastrear a los usuarios y sus posiciones escuchando los eventos que hemos estado emitiendo
        // 1. need to check health factor the user
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // ahora queremos reducir la cantiddad de DSC que tiene el usuario y tomar su garantia
        // Bad user: $140 ETH, $100 DSC
        // debToCover = $100
        // $100 of DSC == ?? ETH
        // 0.05 ETH
        uint256 tokenAmountFromDebCovered = getTokenAmountFromUsd(collateralAdress, debToCover);
        // daremos una bonificacion al liquidador del 10%
        // giving the liquidator $110 of WETH for 100 DSC
        // entonces deberiamos umplementar una function para liquidar en caso que el protocolo al llamar sea insolvente
        // y luego transferir cantidades adicionales a la tesoriria (treasury)
        
        // 0.05  * 0.1 = 0.005 getting 0.055
        uint256 bonusCollateral = (tokenAmountFromDebCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION; // la garantia de bonificacion sera de del 10%
        uint256 totalCollateralToRedeem = tokenAmountFromDebCovered + bonusCollateral;
        // ahora nesecitamos canjear esta garantia para quien este llamando a la function de liquidacion y luego quemar(burn) EL DSC
        // user (user que esta siendo liquidado) , msg.sender(user que esta liquidando) , collateraltoken , la ganrantia total a canjear
        _redeemCollateral(user, msg.sender, collateralAdress, totalCollateralToRedeem);
        // ahora nesecitamos burn tokens, msg.sender (user que va pagar esto liquidador)
        _burnDsc(user, msg.sender, debToCover);

        uint256 endingUserHealtFactor =_healthFactor(user);
        if (endingUserHealtFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved(); // si no mejoramos el factor de salud deberiamos revertir al 100%
        }
        // si ek health factor esta roto para el remitente del mensaje (este proceso arruino el factor de salud) no deberiamos dejar que hagan esto.
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    // permite ver que tan saludables estan las personas
    function getHealthFactor(address user ) external view returns (uint256) {
        return _healthFactor(user);
    }
    
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getCollateralTokenPriceFeed(address tokenCollateralAddress) external view returns (address) {
        return s_priceFeeds[tokenCollateralAddress];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_allowedCollateralTokens;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getCollateralBalanceOfUser(address user, address tokenCollateralAddress) external view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateralAddress];
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }


                                            //////////////////////////////////////////////////
                                            //*  Private & Internal view Functions          //
                                            //////////////////////////////////////////////////
                                            // internal functions utilizamos el _antecesdido para declararlas
    /*
    * @dev Low-level internal, no llame a menos que la funcion que lo llamaesta comprobando si hay healhtFsctor brokens
    */
    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amountDscToBurn) private {
        // los descaontamos del s_DSCMinted contable 
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        // enviamos los DSC a la cuenta del contrato"this"
        bool responseBurned = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!responseBurned) {
            revert DSCEngine__TransferTokenFailed();
        }
        // burn DSC 
        i_dsc.burn(amountDscToBurn);
    }    

    function _redeemCollateral( address from, address to, address tokenCollateralAddress, uint256 amountCollateral) // podemos canjear garantias de cualquier persona que llame a liquidar
        private 
        moreThanZero(amountCollateral) 
    { // de esta manera alguien puede liquidar una direccion y luego obtener las recompensas
        // retirar el collateral (garantia) y actualizar nuestra contabilidad, si intenta hacer sacar mas de lo que tiene (100 - 1000 ) ejecuta el REVERT
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = ERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferTokenFailed();
        }
        _revertIfHealthFactorIsBroken(tokenCollateralAddress);
        emit TransferTokenCollateralFromRedeem(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) {
        totalDscMinted = s_DSCMinted[user]; // total Amount DSC minted por el usuario
        totalCollateralValueInUSD = getAccountColllateralValue(user); // valor total de toas las garantias del usuario
        return (totalDscMinted, totalCollateralValueInUSD);
    }

    /*
     * @notice Retorna que tan cerca de la liquiation esta un usuario
     * if user health factor < 1 -> liquidate
    */
    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        // get account information
        (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) = _getAccountInformation(user);
        // calculate health factor
        healthFactor = _calculateHealthFactor(totalDscMinted, totalCollateralValueInUSD);
        return healthFactor;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Ceck health factor (do they have enought collateral?)
        uint256 userHealthFactor = _healthFactor(user);
        console.log('user HealthFactor', userHealthFactor);
        // 2. Revert if they don't
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) internal pure returns (uint256) {
        // Necesitaremos obtener el valor total de la garantia para asegurarnos de que el valor sea mayor que el total de DSC minted
        // total DSC minted -total collateral Value
        console.log('_calculateHealthFactor - totalDscMinted', totalDscMinted);
        console.log('_calculateHealthFactor - total Collateral Value In USD: $', collateralValueInUsd / 1e18);
        console.log('_calculateHealthFactor - totalDscMinted: ', totalDscMinted);
        if (totalDscMinted == 0) return type(uint256).max;
        //monto de collateral ajustado para el threshold
        uint256 collateralAjusted = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        console.log('_calculateHealthFactor - collateralAjusted', collateralAjusted);
        //  $1000 ETH -> 100 DSC
        // 1000 * 0.5 = 500 / 100 = 5 > 1 
        // se nesecita tener mas del doble de collateral
        return (collateralAjusted * PRECISION ) / totalDscMinted;
    }

                                        //////////////////////////////////////////////////
                                        //*     public & external view Functions        //
                                        //////////////////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // 1. get price of token (ETH)
        // $/ETH => ETH ?
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        // console.log('|= DSCENGINE =| priceFeed', priceFeed);
        ( ,int256 answer, , , ) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = $1000
        // $3000e8 * 1e10 = 3000e18
        uint256 amountInUSD = uint256(answer) * ADDITIONAL_FEED_PRECISION; // add feed precision, viene con los 8 decimales
            // ($10e18 * 1e18) / 3000e18
        return (usdAmountInWei * PRECISION) / amountInUSD;
    }

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
        ( ,int256 answer, , , ) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = $3000
        // the returned value from CL will be 3000 * 1e8
        uint256 amountInUSD = uint256(answer) * ADDITIONAL_FEED_PRECISION * amount;
        return amountInUSD / PRECISION; 
    }

    function getAccountInformation( address user) external view returns (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) {
        ( totalDscMinted, totalCollateralValueInUSD) = _getAccountInformation(user);
    }
}