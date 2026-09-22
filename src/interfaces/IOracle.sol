// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal price-oracle interface. Both NaiveSpotOracle (vulnerable) and
/// TwapOracle (fixed) implement it, so the SAME LendingVault can be pointed at
/// either one and the SAME attack can be run against both.
interface IOracle {
    /// @return price of 1 COLL denominated in QUOTE, scaled by 1e18.
    function priceOfColl() external view returns (uint256);
}
