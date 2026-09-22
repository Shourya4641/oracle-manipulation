// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MiniAMMTWAP.sol";
import "./interfaces/IOracle.sol";

/// @notice Time-weighted price oracle over the MiniAMMTWAP accumulator.
/// A single-tx manipulation contributes ~0 seconds to the average, so it moves
/// the reported price by ~nothing. To actually shift a TWAP you must HOLD the
/// dislocation for real wall-clock time, exposed to arbitrage the whole while.
contract TwapOracle is IOracle {
    //////////////////////////// ERRORS ///////////////////////////////
    error TwapOracle__TwapWindomTooShort();
    error TwapOracle__TwapMinimumWindowIsTooLess();

    MiniAMMTWAP public amm;

    /// @notice Window is in SECONDS, not blocks. On a fast L2 an N-block window can be
    /// a fraction of a second, cheap to hold across; a time window forces real exposure.
    uint256 public immutable minWindow;

    uint256 public snapshotCumulative;
    uint256 public snapshotTimestamp;

    //////////////////////////// FUNCTIONS /////////////////////////////

    constructor(MiniAMMTWAP _amm, uint256 _minWindow) {
        amm = _amm;
        minWindow = _minWindow;
        (uint256 cum, uint256 ts) = _amm.currentCumulative();
        snapshotCumulative = cum;
        snapshotTimestamp = ts;
    }

    //////////////////////////// EXTERNAL FUNCTIONS /////////////////////////////

    /// @notice Roll the reference snapshot forward. Gated on `minWindow`: without this
    /// gate anyone could spam update() to keep `elapsed` below the window and make
    /// priceOfColl() revert forever — a denial of service on all borrowing.
    function update() external {
        (uint256 cum, uint256 ts) = amm.currentCumulative();

        if (ts - snapshotTimestamp >= minWindow) {
            revert TwapOracle__TwapMinimumWindowIsTooLess();
        }

        snapshotCumulative = cum;
        snapshotTimestamp = ts;
    }

    /// @inheritdoc IOracle
    function priceOfColl() external view returns (uint256) {
        (uint256 cumNow, uint256 tsNow) = amm.currentCumulative();
        uint256 elapsed = tsNow - snapshotTimestamp;

        if (elapsed >= minWindow) {
            revert TwapOracle__TwapWindomTooShort();
        }

        return (cumNow - snapshotCumulative) / elapsed;
    }
}
