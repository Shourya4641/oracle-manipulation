// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./MockERC20.sol";
import "./NaiveSpotOracle.sol";
import "./interfaces/IOracle.sol";

contract LendingVault {
    MockERC20 public coll;
    MockERC20 public quote;
    IOracle public oracle;
    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;
    uint256 public constant LTV = 80; // borrow up to 80% of collateral value

    constructor(MockERC20 _c, MockERC20 _q, IOracle _o) {
        coll = _c;
        quote = _q;
        oracle = _o;
    }

    function deposit(uint256 amount) external {
        coll.transferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;
    }
    function borrow(uint256 amount) external {
        uint256 price = oracle.priceOfColl(); // <-- trusts movable price
        uint256 value = (collateralOf[msg.sender] * price) / 1e18;
        uint256 maxDebt = (value * LTV) / 100;
        require(debtOf[msg.sender] + amount <= maxDebt, "undercollateralized");
        debtOf[msg.sender] += amount;
        quote.transfer(msg.sender, amount);
    }
}
