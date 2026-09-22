// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockERC20.sol";
import "../src/MiniAMMTWAP.sol";
import "../src/TwapOracle.sol";
import "../src/LendingVault.sol";

/// @notice Same attack as OracleAttackTest, run against the TWAP-backed vault.
/// The manipulation still moves SPOT price 100x, but the TWAP the vault reads is
/// still honest, so the over-borrow reverts instead of paying out.
contract OracleFixTest is Test {
    MockERC20 coll;
    MockERC20 quote;
    MiniAMMTWAP amm;
    TwapOracle oracle;
    LendingVault vault;

    address attacker = address(0xA11CE);
    uint256 constant WINDOW = 30 minutes;

    function setUp() public {
        coll = new MockERC20();
        quote = new MockERC20();
        amm = new MiniAMMTWAP(coll, quote);

        coll.mint(address(amm), 1000e18);
        quote.mint(address(amm), 1000e18); // honest price: 1 COLL = 1 QUOTE
        amm.sync();                        // register stored reserves

        oracle = new TwapOracle(amm, WINDOW); // snapshots at the honest price
        vault = new LendingVault(coll, quote, oracle);

        quote.mint(address(vault), 10_000e18);
        quote.mint(attacker, 9_000e18); // "flash loan" capital
    }

    function test_TwapDefeatsSameAttack() public {
        // Let a full honest-priced window accrue before the attack.
        vm.warp(block.timestamp + WINDOW + 1);

        vm.startPrank(attacker);
        quote.approve(address(amm), type(uint256).max);
        amm.swapQuoteForColl(9_000e18); // SAME manipulation as the naive lab

        // Spot moved 100x, but the TWAP the vault reads did not.
        (uint256 rColl, uint256 rQuote) = amm.reserves();
        assertEq((rQuote * 1e18) / rColl, 100e18); // spot
        assertEq(oracle.priceOfColl(), 1e18);       // TWAP

        coll.approve(address(vault), type(uint256).max);
        vault.deposit(100e18);

        // The SAME over-borrow now reverts instead of paying out 8,000.
        vm.expectRevert("undercollateralized");
        vault.borrow(8_000e18);
        assertEq(vault.debtOf(attacker), 0);

        // SAME unwind as the attack test: sell the 800 COLL back to the pool.
        // Without this leg the attacker still holds value in COLL, so "they lost
        // everything" would be false — P&L is only real once the position is closed.
        uint256 leftover = coll.balanceOf(attacker);
        assertEq(leftover, 800e18);
        coll.approve(address(amm), type(uint256).max);
        amm.swapCollForQuote(leftover);
        vm.stopPrank();

        // Realised P&L: started with 9,000 QUOTE, ends with ~8,888.89.
        // The attack cost the attacker ~111.11 QUOTE in round-trip slippage
        // and stranded 100 COLL in the vault, for zero extracted.
        assertEq(quote.balanceOf(attacker), 8888888888888888888889);
        assertLt(quote.balanceOf(attacker), 9_000e18);

        // The vault never paid out and never took bad debt.
        assertEq(quote.balanceOf(address(vault)), 10_000e18);
        assertEq(coll.balanceOf(address(vault)), 100e18);
    }
}
