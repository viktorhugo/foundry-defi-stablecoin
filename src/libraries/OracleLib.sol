// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { AggregatorV3Interface } from "@chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/*
* @title OracleLib
* @Author: Victor Mosquera
* @dev Funciones para limitar el rango de valores
* @notice this library is used to check the Chainlink Oracle for stale data.
* If a price is stale, the function will revert, and render the DSCEngine unusable. 
* Queremos que DSEngine se congele si los precios se estancan
* Entonces, si la red de Chainlink explota y tienes mucho dinero locked en el protocol... to bad.
*/
library OracleLib {

    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800 seconds
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns (uint80, int256, uint256, uint256, uint80) {
        ( 
            uint80 roundId, 
            int256 answer, 
            uint256 startedAt, 
            uint256 updatedAt, 
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        uint256 secondsSinceUpdate = block.timestamp - updatedAt;
        if (secondsSinceUpdate > TIMEOUT) { // 
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

//* ====== Usaremos libreria para verificar si el precio esta obsoleto