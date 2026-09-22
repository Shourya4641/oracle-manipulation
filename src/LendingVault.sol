// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./MockERC20.sol";
import "./NaiveSpotOracle.sol";
import "./interfaces/IOracle.sol";

contract LendingVault {
    //////////////////////////// ERRORS ///////////////////////////////
    error LendingVault__UserAssetIsUnderCollateralised();

    MockERC20 public collateral;
    MockERC20 public quote;

    IOracle public oracle;

    //////////////////////////// STATE VARIABLES ///////////////////////////////

    mapping(address user => uint256 collateralAmount) public collateralOf;
    mapping(address user => uint256 debtAmount) public debtOf;

    uint256 public constant LTV = 80; // borrow up to 80% of collateral value

    //////////////////////////// FUNCTIONS /////////////////////////////

    constructor(MockERC20 _collateral, MockERC20 _quote, IOracle _oracle) {
        collateral = _collateral;
        quote = _quote;
        oracle = _oracle;
    }

    //////////////////////////// EXTERNAL FUNCTIONS /////////////////////////////

    function deposit(uint256 amount) external {
        collateral.transferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;
    }

    function borrow(uint256 amount) external {
        uint256 price = oracle.priceOfColl(); // <-- trusts movable price
        uint256 value = (collateralOf[msg.sender] * price) / 1e18;
        uint256 maxDebt = (value * LTV) / 100;

        if (debtOf[msg.sender] + amount <= maxDebt) {
            revert LendingVault__UserAssetIsUnderCollateralised();
        }

        debtOf[msg.sender] += amount;
        quote.transfer(msg.sender, amount);
    }
}
