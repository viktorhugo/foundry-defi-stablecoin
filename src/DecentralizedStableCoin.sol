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

pragma solidity 0.8.30;

/**
* @title Decentralized Stable Coin
* @author Victor mosquera
* @Collateral: Exogenous (ETH & BTC)
* Minting: algorithmic
* Relative Stability: pegged to USD
*
* This contract meant to be governed by DSCEngine. This contract is just the ERC2-
* implementation of our stabele coin.
*/

import { Script } from "forge-std/Script.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { console } from "forge-std/Script.sol";
// import { HelperConfig } from "./HelperConfig.s.sol";

/** Errors */
error DecentralizedStableCoinError__MustBeMoreThanZero();
error DecentralizedStableCoinError__BurnAmountExceedsBalance();
error DecentralizedStableCoinError__NotZeroAddress();

contract DecentralizedStableCoin is ERC20Burnable, Ownable {

     /** Type declarations */
    // address private s_treasury;

    constructor() 
    Ownable(msg.sender)
    ERC20("Decentralized Stable Coin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (balance < 0) {
            revert DecentralizedStableCoinError__BurnAmountExceedsBalance();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoinError__MustBeMoreThanZero();
        }
        super.burn(_amount); // super say use the burn function from ERC20Burnable (parent class)
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoinError__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoinError__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

}
