// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./MockERC20.sol";

contract MiniAMM {
    MockERC20 public coll;
    MockERC20 public quote;
    constructor(MockERC20 _coll, MockERC20 _quote) {
        coll = _coll;
        quote = _quote;
    }

    function reserves() public view returns (uint256 rColl, uint256 rQuote) {
        rColl = coll.balanceOf(address(this));
        rQuote = quote.balanceOf(address(this));
    }
    
    // push QUOTE in, take COLL out -> COLL reserve falls -> spot price of COLL rises
    function swapQuoteForColl(uint256 amountIn) external returns (uint256 out) {
        (uint256 rColl, uint256 rQuote) = reserves();
        quote.transferFrom(msg.sender, address(this), amountIn);
        uint256 k = rColl * rQuote;
        uint256 newQuote = rQuote + amountIn;
        uint256 newColl = k / newQuote;
        out = rColl - newColl;
        coll.transfer(msg.sender, out);
    }
}
