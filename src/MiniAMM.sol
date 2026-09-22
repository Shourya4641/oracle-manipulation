// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./MockERC20.sol";

contract MiniAMM {
    MockERC20 public collateral;
    MockERC20 public quote;

    //////////////////////////// FUNCTIONS /////////////////////////////

    constructor(MockERC20 _collateral, MockERC20 _quote) {
        collateral = _collateral;
        quote = _quote;
    }

    //////////////////////////// EXTERNAL FUNCTIONS /////////////////////////////

    // push QUOTE in, take COLLATERAL out -> COLLATERAL reserve falls -> spot price of COLLATERAL rises
    function swapQuoteForColl(uint256 amountIn) external returns (uint256 out) {
        (uint256 rCollateral, uint256 rQuote) = reserves();
        quote.transferFrom(msg.sender, address(this), amountIn);
        uint256 k = rCollateral * rQuote;
        uint256 newQuote = rQuote + amountIn;
        uint256 newColl = k / newQuote;
        out = rCollateral - newColl;
        collateral.transfer(msg.sender, out);
    }

    function swapCollForQuote(uint256 amountIn) external returns (uint256 out) {
        (uint256 rCollateral, uint256 rQuote) = reserves();
        collateral.transferFrom(msg.sender, address(this), amountIn);
        uint256 k = rCollateral * rQuote;
        uint256 newColl = rCollateral + amountIn;
        uint256 newQuote = k / newColl;
        out = rQuote - newQuote;
        quote.transfer(msg.sender, out);
    }

    //////////////////////////// PUBLIC FUNCTIONS /////////////////////////////

    function reserves()
        public
        view
        returns (uint256 rCollateral, uint256 rQuote)
    {
        rCollateral = collateral.balanceOf(address(this));
        rQuote = quote.balanceOf(address(this));
    }
}
