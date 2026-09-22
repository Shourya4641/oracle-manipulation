// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./MiniAMM.sol";
import "./interfaces/IOracle.sol";

contract NaiveSpotOracle is IOracle {
    MiniAMM public amm;

    //////////////////////////// FUNCTIONS /////////////////////////////

    constructor(MiniAMM _amm) {
        amm = _amm;
    }

    //////////////////////////// EXTERNAL FUNCTIONS /////////////////////////////

    // price of 1 COLL in QUOTE, 1e18 scaled.
    // instantaneous reserve ratio = movable in one tx = not a price.
    function priceOfColl() external view returns (uint256) {
        (uint256 _rCollateral, uint256 rQuote) = amm.reserves();
        return (rQuote * 1e18) / _rCollateral;
    }
}
