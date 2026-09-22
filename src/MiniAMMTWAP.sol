// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockERC20.sol";

/// @notice Fixed AMM used by the TWAP oracle.
/// Two differences from the vulnerable MiniAMM:
///   1. Reserves are STORED and only ever mutated through `_update`, never read
///      live from `balanceOf` (a live-balance oracle can be nudged by a plain
///      token donation, with no swap at all).
///   2. `_update` accumulates the price that held over the PAST interval using the
///      OLD reserves, THEN overwrites them. The drafted `_accumulate` read live
///      reserves at call time, so if it ran after a swap moved balances it would
///      credit the just-elapsed (honest) interval with the manipulated price.
contract MiniAMMTWAP {
    MockERC20 public coll;
    MockERC20 public quote;

    uint256 private _reserveColl;
    uint256 private _reserveQuote;

    /// @notice Sum over time of (rQuote * 1e18 / rColl) * secondsElapsed.
    uint256 public priceCumulativeLast;
    uint256 public blockTimestampLast;

    constructor(MockERC20 _coll, MockERC20 _quote) {
        coll = _coll;
        quote = _quote;
    }

    function reserves() public view returns (uint256 rColl, uint256 rQuote) {
        rColl = _reserveColl;
        rQuote = _reserveQuote;
    }

    /// @notice Register tokens already sent to the pool as reserves (toy liquidity seeding).
    function sync() external {
        _update(coll.balanceOf(address(this)), quote.balanceOf(address(this)));
    }

    /// @dev Accumulate the OLD reserves' price over [last, now], THEN store the new reserves.
    function _update(uint256 newColl, uint256 newQuote) internal {
        uint256 dt = block.timestamp - blockTimestampLast;
        if (blockTimestampLast != 0 && dt > 0 && _reserveColl != 0) {
            priceCumulativeLast += (_reserveQuote * 1e18 / _reserveColl) * dt;
        }
        _reserveColl = newColl;
        _reserveQuote = newQuote;
        blockTimestampLast = block.timestamp;
    }

    /// @notice Cumulative extrapolated to `now`, adding the pending interval since the
    /// last swap. The consumer needs this so a read between swaps is still current.
    function currentCumulative() public view returns (uint256 cum, uint256 ts) {
        ts = block.timestamp;
        cum = priceCumulativeLast;
        uint256 dt = ts - blockTimestampLast;
        if (dt > 0 && _reserveColl != 0) {
            cum += (_reserveQuote * 1e18 / _reserveColl) * dt;
        }
    }

    /// @notice Push QUOTE in, take COLL out. Same constant-product math as the
    /// vulnerable pool, so the manipulation moves spot price identically.
    function swapQuoteForColl(uint256 amountIn) external returns (uint256 out) {
        uint256 rColl = _reserveColl;
        uint256 rQuote = _reserveQuote;
        quote.transferFrom(msg.sender, address(this), amountIn);
        uint256 k = rColl * rQuote;
        uint256 newQuote = rQuote + amountIn;
        uint256 newColl = k / newQuote;
        out = rColl - newColl;
        coll.transfer(msg.sender, out);
        _update(newColl, newQuote); // credits [last, now] with the pre-swap price
    }

    /// @notice Push COLL in, take QUOTE out. The unwind leg: lets the attacker sell
    /// back the COLL they bought, so both labs can measure realised P&L identically.
    function swapCollForQuote(uint256 amountIn) external returns (uint256 out) {
        uint256 rColl = _reserveColl;
        uint256 rQuote = _reserveQuote;
        coll.transferFrom(msg.sender, address(this), amountIn);
        uint256 k = rColl * rQuote;
        uint256 newColl = rColl + amountIn;
        uint256 newQuote = k / newColl;
        out = rQuote - newQuote;
        quote.transfer(msg.sender, out);
        _update(newColl, newQuote);
    }
}
