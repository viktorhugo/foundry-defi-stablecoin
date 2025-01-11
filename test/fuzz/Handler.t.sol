// SPDX-License-Identifier: MIT
//* este controlador va a limitar la forma en que llamamos funciones
pragma solidity ^0.8.25;
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import {Test} from "lib/forge-std/src/Test.sol";

contract  Handler is Test {

    DSCEngine dscEngine;
    DecentralizedStableCoin decentralizedStableCoin;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _decentralizedStableCoin) {
        dscEngine = _dscEngine;
        decentralizedStableCoin = _decentralizedStableCoin;
    }

    //* redeem collateral 
    //* queremos que deposite garantias aleatorias que sean garantias validas
    function depositCollateral(address _collateral, uint256 _amount) external {
        dscEngine.depositCollateral(_collateral, _amount);
    }

}