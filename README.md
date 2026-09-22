# Oracle Manipulation Simulation

**Exploit Lab #2** — a runnable Foundry simulation of spot-price oracle manipulation against a lending vault, with a working fix and a test that flips.

> Series: [Lab 1 — Reentrancy](https://github.com/Shourya4641/re-entrancy-simulation) · **Lab 2 — Oracle Manipulation**

---

## Summary

A lending protocol reads the price of its collateral from an on-chain AMM's *current reserve ratio*. That ratio is not a price — it is a number any trader can move inside a single transaction. An attacker swaps a large amount into a thin pool, the reported price jumps 100x, the vault values their collateral at the inflated number, and lends out far more than the collateral is worth. The loan is never repaid.

In this simulation the attacker turns **9,000 QUOTE of (flash-loanable) capital into 16,888.89 QUOTE** — a realised profit of **7,888.89 QUOTE** — and leaves the vault holding **~7,900 QUOTE of unbacked bad debt**, all in one atomic transaction.

Point the same vault at a TWAP oracle instead, run the **identical** attack, and it inverts: `borrow` reverts, the attacker realises a **loss of 111.11 QUOTE**, and the vault is untouched.

**Vulnerability class:** price oracle manipulation / unsafe price source
**Root cause:** using a spot reserve ratio as a price feed
**Impact:** unbacked borrowing, loss of depositor funds

---

## The setup

| Contract | Role |
|---|---|
| `MockERC20` | Two tokens: `COLL` (collateral) and `QUOTE` (borrowable asset) |
| `MiniAMM` | Constant-product pool, seeded 1,000 COLL / 1,000 QUOTE → honest price 1 COLL = 1 QUOTE |
| `NaiveSpotOracle` | Reports the pool's instantaneous reserve ratio as "the price" |
| `LendingVault` | Lends QUOTE against COLL at 80% LTV, using whatever `IOracle` it is given |

The pool is deliberately thin relative to the vault's liquidity — the vault holds 10,000 QUOTE to lend, while the pool holds only 1,000 QUOTE. **That asymmetry is the vulnerability's precondition:** it is cheap to move the price relative to what can be borrowed against the move.

---

## The vulnerable line

`src/NaiveSpotOracle.sol`

```solidity
function priceOfColl() external view returns (uint256) {
    (uint256 rColl, uint256 rQuote) = amm.reserves();
    return (rQuote * 1e18) / rColl;   // <-- instantaneous ratio, movable in one tx
}
```

This returns the pool's balance ratio *right now*. There is no history, no averaging, and no external reference. Anyone who can change the two balances can change the output — and changing the two balances is just "making a trade," which is what the pool exists to allow.

The poison enters the protocol here, in `src/LendingVault.sol`:

```solidity
function borrow(uint256 amount) external {
    uint256 price = oracle.priceOfColl();            // <-- trusts a movable number
    uint256 value = (collateralOf[msg.sender] * price) / 1e18;
    uint256 maxDebt = (value * LTV) / 100;
    require(debtOf[msg.sender] + amount <= maxDebt, "undercollateralized");
    debtOf[msg.sender] += amount;
    quote.transfer(msg.sender, amount);
}
```

Note that the collateralisation check itself is *correct*. The vault does gate the loan on collateral value, and the arithmetic is right. The bug is not missing validation — it is that the input to a correct calculation is attacker-controlled.

---

## Attack mechanics

All six steps execute in one transaction, so no one can react in between and any failure reverts the whole thing.

1. **Observe the honest price.** Pool holds 1,000 COLL / 1,000 QUOTE. `priceOfColl()` returns `1e18` — 1 COLL = 1 QUOTE.
2. **Manipulate.** Swap 9,000 QUOTE into the pool. Constant-product math (`x * y = k`) leaves the pool with **100 COLL / 10,000 QUOTE**, and sends 900 COLL to the attacker.
3. **Re-read the price.** `priceOfColl()` now returns `100e18`. COLL "costs" 100 QUOTE — a **100x** move. Nothing about COLL changed anywhere else; one pool's two balances were rearranged.
4. **Deposit collateral.** Attacker deposits 100 COLL into the vault. At the honest price that is worth ~100 QUOTE. At the manipulated price the vault values it at 10,000 QUOTE.
5. **Over-borrow.** `borrow(8_000e18)` passes the LTV check: `100 COLL × 100 × 80% = 8,000`. The vault transfers out **8,000 QUOTE** against collateral genuinely worth ~100.
6. **Unwind.** Sell the remaining 800 COLL back to the pool for 8,888.89 QUOTE. Attacker ends holding **16,888.89 QUOTE** against a 9,000 QUOTE start, abandons the 100 COLL, and never repays the debt.

In production step 2's capital comes from a flash loan repaid in step 6, so the attack requires **no upfront capital** — only that the round trip is profitable. Note that it is profitable here *even self-financed*; the flash loan removes the capital requirement, it does not create the profit.

---

## Proof — the attack

```
forge test --match-test test_NaiveOracleAllowsMassiveOverBorrow -vvvv
```

```
[PASS] test_NaiveOracleAllowsMassiveOverBorrow() (gas: 588817)
Traces:
  [598417] OracleAttackTest::test_NaiveOracleAllowsMassiveOverBorrow()
    ├─ [22827] NaiveSpotOracle::priceOfColl() [staticcall]
    │   ├─ [16775] MiniAMM::reserves() [staticcall]
    │   │   └─ ← [Return] 1000000000000000000000 [1e21], 1000000000000000000000 [1e21]
    │   └─ ← [Return] 1000000000000000000 [1e18]                 <-- honest price: 1.0
    ├─ [77896] MiniAMM::swapQuoteForColl(9000000000000000000000 [9e21])
    │   ├─ [15014] MockERC20::transferFrom(0x...A11cE, MiniAMM, 9000000000000000000000 [9e21])
    │   ├─ [26578] MockERC20::transfer(0x...A11cE, 900000000000000000000 [9e20])
    │   └─ ← [Return] 900000000000000000000 [9e20]
    ├─ [22827] NaiveSpotOracle::priceOfColl() [staticcall]
    │   ├─ [16775] MiniAMM::reserves() [staticcall]
    │   │   └─ ← [Return] 100000000000000000000 [1e20], 10000000000000000000000 [1e22]
    │   └─ ← [Return] 100000000000000000000 [1e20]                <-- manipulated price: 100.0
    ├─ [83779] LendingVault::deposit(100000000000000000000 [1e20])
    │   └─ ← [Stop]
    ├─ [107042] LendingVault::borrow(8000000000000000000000 [8e21])
    │   ├─ [22827] NaiveSpotOracle::priceOfColl() [staticcall]
    │   │   └─ ← [Return] 100000000000000000000 [1e20]            <-- vault prices collateral at 100x
    │   ├─ [28578] MockERC20::transfer(0x...A11cE, 8000000000000000000000 [8e21])
    │   └─ ← [Stop]                                                <-- 8,000 QUOTE paid out
    ├─ [60850] MiniAMM::swapCollForQuote(800000000000000000000 [8e20])
    │   └─ ← [Return] 8888888888888888888889 [8.888e21]            <-- unwind
    ├─ [2845] MockERC20::balanceOf(0x...A11cE) [staticcall]
    │   └─ ← [Return] 16888888888888888888889 [1.688e22]           <-- final: 16,888.89 QUOTE
```

*Trace abridged — repeated `balanceOf` and `approve` frames removed. Full output: [`traces/attack.txt`](traces/attack.txt).*

### The numbers

| | Value |
|---|---|
| Attacker starting capital | 9,000 QUOTE (flash-loanable) |
| Price before / after manipulation | 1.0 → 100.0 (**100x**) |
| Collateral deposited | 100 COLL (honest value ~100 QUOTE) |
| Borrowed | **8,000 QUOTE** |
| Attacker final balance | 16,888.89 QUOTE |
| **Attacker realised profit** | **+7,888.89 QUOTE** |
| Vault QUOTE: before → after | 10,000 → 2,000 |
| **Vault bad debt** | **~7,900 QUOTE** (8,000 lent against ~100 of real collateral) |

**Attacker profit (7,888.89) ≠ protocol loss (~7,900).** The 11.11 QUOTE difference is round-trip slippage paid to the pool's liquidity providers — the attacker pays the AMM a toll to move the price, and pays again to move it back. That toll is the real economic brake on manipulation: it scales with how far the price is pushed and how deep the pool is. A thin pool makes the toll trivially small relative to what can be borrowed against the move, which is exactly why *thin liquidity* is the precondition for this attack class.

---

## The fix

Stop asking "what is the ratio right now" and start asking "what has the ratio averaged over a meaningful stretch of time" — a **TWAP** (time-weighted average price).

A one-transaction spike lasts a few seconds. Averaged over a 30-minute window it contributes ~0 to the result, so the reported price barely moves. To actually drag a TWAP to 100x, the attacker would have to *hold* the dislocated price for much of the window, exposed to arbitrageurs the entire time, with capital locked.

**TWAP does not make manipulation impossible. It makes it slow and expensive.** That is the honest framing — it converts a free, instant, risk-free exploit into a costly sustained one. See the takeaways for where that guarantee has weakened since the Merge.

### What had to change

`src/MiniAMMTWAP.sol` — the pool itself, not just the oracle:

```solidity
function _update(uint256 newColl, uint256 newQuote) internal {
    uint256 dt = block.timestamp - blockTimestampLast;
    if (blockTimestampLast != 0 && dt > 0 && _reserveColl != 0) {
        // credit the elapsed interval with the price that ACTUALLY held over it = OLD reserves
        priceCumulativeLast += (_reserveQuote * 1e18 / _reserveColl) * dt;
    }
    _reserveColl = newColl;
    _reserveQuote = newQuote;
    blockTimestampLast = block.timestamp;
}
```

Two deliberate changes from the vulnerable pool:

- **Stored reserves, not `balanceOf`.** The vulnerable `MiniAMM` derives reserves from live token balances, so a plain token *donation* — no swap at all — moves the reported price.
- **Accumulate the old price, then overwrite.** Order matters. An accumulator that reads reserves *after* a swap has already moved them credits the just-elapsed honest interval with the manipulated price, silently poisoning the average it is supposed to protect. This is a bug I wrote and caught while building the fix; it is the kind of error that leaves a TWAP looking correct while providing no protection.

`src/TwapOracle.sol` — the consumer:

```solidity
function priceOfColl() external view returns (uint256) {
    (uint256 cumNow, uint256 tsNow) = amm.currentCumulative();
    uint256 elapsed = tsNow - snapshotTimestamp;
    require(elapsed >= minWindow, "twap: window too short");
    return (cumNow - snapshotCumulative) / elapsed;
}
```

**The fix is not a patch to the lending contract.** `LendingVault` is unchanged — it only swaps which oracle it points at, since both implement `IOracle`. But a TWAP requires the pool to *record price history*, which the original pool does not do. In production this means the fix depends on infrastructure the collateral's trading venue must already provide. That is a real migration cost, not a one-line change.

---

## Proof — the same attack against the fix

The attacker runs **identical** steps: same 9,000 capital, same 9,000-QUOTE swap, same 100 COLL deposit, same `borrow(8_000e18)`, same unwind. Only the oracle changed.

```
forge test --match-test test_TwapDefeatsSameAttack -vvvv
```

```
[PASS] test_TwapDefeatsSameAttack() (gas: 587561)
Traces:
  [597161] OracleFixTest::test_TwapDefeatsSameAttack()
    ├─ [0] VM::warp(1802)                                          <-- accrue one honest 30-min window
    ├─ [113313] MiniAMMTWAP::swapQuoteForColl(9000000000000000000000 [9e21])
    │   └─ ← [Return] 900000000000000000000 [9e20]                 <-- SAME manipulation
    ├─ [4711] MiniAMMTWAP::reserves() [staticcall]
    │   └─ ← [Return] 100000000000000000000 [1e20], 10000000000000000000000 [1e22]
    │                                                              <-- spot IS still 100.0
    ├─ [15298] TwapOracle::priceOfColl() [staticcall]
    │   ├─ [4886] MiniAMMTWAP::currentCumulative() [staticcall]
    │   │   └─ ← [Return] 1801000000000000000000 [1.801e21], 1802
    │   └─ ← [Return] 1000000000000000000 [1e18]                   <-- TWAP still 1.0
    ├─ [83779] LendingVault::deposit(100000000000000000000 [1e20])
    │   └─ ← [Stop]
    ├─ [0] VM::expectRevert(undercollateralized)
    ├─ [47871] LendingVault::borrow(8000000000000000000000 [8e21])
    │   ├─ [15298] TwapOracle::priceOfColl() [staticcall]
    │   │   └─ ← [Return] 1000000000000000000 [1e18]
    │   └─ ← [Revert] undercollateralized                          <-- the flip
    ├─ [2846] LendingVault::debtOf(0x...A11cE) [staticcall]
    │   └─ ← [Return] 0
    ├─ [87224] MiniAMMTWAP::swapCollForQuote(800000000000000000000 [8e20])
    │   └─ ← [Return] 8888888888888888888889 [8.888e21]            <-- SAME unwind
    ├─ [2845] MockERC20::balanceOf(0x...A11cE) [staticcall]
    │   └─ ← [Return] 8888888888888888888889 [8.888e21]            <-- final: 8,888.89 (from 9,000)
    ├─ [2845] MockERC20::balanceOf(LendingVault) [staticcall]
    │   └─ ← [Return] 10000000000000000000000 [1e22]               <-- vault QUOTE untouched
    ├─ [2845] MockERC20::balanceOf(LendingVault) [staticcall]
    │   └─ ← [Return] 100000000000000000000 [1e20]                 <-- 100 COLL stranded
```

*Trace abridged. Full output: [`traces/fix.txt`](traces/fix.txt).*

The load-bearing moment: **the pool's reserves really are 100 / 10,000 — spot price is genuinely 100.0 — while the oracle reports 1.0.** The manipulation still succeeds. The vault simply stops caring, and `borrow` reverts `undercollateralized` instead of paying out.

Note the accumulator arithmetic in the trace: `1801e18 / 1801 seconds = 1e18`. The manipulated price was in effect for **0 seconds** of the window, so it contributed nothing to the average.

---

## Attack vs fix

| | Naive spot oracle | TWAP oracle |
|---|---|---|
| Spot price after swap | 100.0 | 100.0 (still manipulated) |
| Price the vault reads | **100.0** | **1.0** |
| `borrow(8_000e18)` | pays out 8,000 QUOTE | **reverts** `undercollateralized` |
| Attacker realised P&L | **+7,888.89 QUOTE** | **−111.11 QUOTE** |
| Vault bad debt | **~7,900 QUOTE** | **0** |

Same attacker, same capital, same six steps. One dependency changed, and the attack inverts from profitable to loss-making. The attacker's 111.11 loss is precisely the round-trip slippage from the previous section — they paid the AMM's toll and got nothing for it.

---

## Takeaways

**1. A spot reserve ratio is not a price.** It is a number that is true for one instant and controllable by whoever trades next. Any protocol reading `reserve0 / reserve1` as a price feed has an open manipulation vector, regardless of how correct the rest of its math is.

**2. Attacker profit and protocol loss are different numbers.** Here: +7,888.89 vs ~7,900, with 11.11 lost to slippage. When assessing severity, model both — the gap is the manipulation cost, and it determines whether the attack is worth running at scale.

**3. Thin liquidity relative to borrowable size is the precondition.** The exploit works because moving the pool 100x costs less than what can be borrowed against the move. Deeper pools, borrow caps, and per-asset debt ceilings all attack the same inequality.

**4. The naive fix has its own bug: a permissionless TWAP `update()` is a DoS.** If anyone can roll the snapshot forward at will, they can keep `elapsed` below the minimum window and make `priceOfColl()` revert permanently — freezing all borrowing. `TwapOracle.update()` gates on `minWindow` for exactly this reason. Introducing a liveness failure while fixing a pricing failure is a recurring pattern in oracle patches.

**5. Size TWAP windows in *time*, not blocks.** On a fast L2, an N-block window can be a fraction of a second — cheap to hold a dislocated price across. Seconds are the unit that costs an attacker something; blocks are not. On Arbitrum specifically, `block.number` reflects the L1 block and updates roughly once a minute, so block-based timing is wrong there in more ways than one.

**6. Proof-of-stake weakened the TWAP guarantee.** Validators learn one epoch (32 slots, ~6m24s) in advance whether they will propose, so a proposer with two consecutive slots can push the price in block N via a private bundle — where arbitrageurs cannot correct it — and revert in N+1 at near-zero cost. Uniswap's own research on v3 TWAPs in PoS names this as removing one of the major defences. The practical consequence: TWAPs are still reasonable as a secondary or sanity oracle on deep pools, but are no longer sufficient as the sole primary oracle for a thin-liquidity asset.

### If you use an external feed instead (a different attack surface)

Replacing the AMM oracle with a push feed removes *this* attack but introduces integration bugs. These are notes, not code in this repo — they defend a different vector and would not stop the manipulation demonstrated above.

- **Staleness: use `updatedAt`, not `answeredInRound`.** Chainlink's API reference marks `answeredInRound` deprecated; in current OCR aggregators it always equals `roundId`, so `require(answeredInRound >= roundId)` can never trip and is a no-op. The real check is `answer > 0`, `updatedAt != 0`, and `block.timestamp - updatedAt <= maxAge`.

```solidity
(, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
require(answer > 0, "bad price");
require(updatedAt != 0, "incomplete round");
require(block.timestamp - updatedAt <= maxAge, "stale price");
```

- **`maxAge` must be per feed, not a global constant.** Different feeds have different heartbeats; reusing one staleness constant across feeds is itself a common audit finding. Wrap the call in `try/catch` — a retired feed's `latestRoundData` reverts, which will otherwise brick every function that prices that asset.

- **The `minAnswer` / `maxAnswer` circuit-breaker trap — and why the usual advice is now wrong.** Aggregators historically clamped reported prices to a floor and ceiling. During the May 2022 LUNA collapse the LUNA/USD floor sat at ~$0.10, so as the real price fell to ~$0.01 the feed kept reporting ~$0.107 with every staleness check passing; attackers deposited near-worthless LUNA valued at the floor and drained lending markets (Venus ~$11.2M, Blizz ~$8.28M). The commonly repeated fix — read the aggregator's own `minAnswer`/`maxAnswer` and revert on the bound — is **largely obsolete**: Chainlink's docs now state these values are no longer used on most feeds, so that check is frequently a no-op. Two consequences worth knowing: **hardcode your own per-asset sanity bounds** rather than deferring to the aggregator's, and note that some feeds (notably on Arbitrum) *do* still enforce bounds, so it remains a live finding there — verify on-chain per feed rather than asserting it generically.

- **L2 sequencer uptime.** When an L2 sequencer is down, feeds stop updating — but `block.timestamp` freezes too, so a naive `updatedAt + threshold > block.timestamp` check still passes. On resume, queued borrows and liquidations execute against pre-outage prices. Chainlink's Sequencer Uptime Feed exposes `answer` (0 = up, 1 = down) and `startedAt`; the documented pattern reverts while down and during a grace period after recovery (Chainlink's example uses 3600 seconds). Two current caveats: Chainlink has stopped expanding these feeds to new networks, so a protocol on a newer L2 may have none and needs a different safeguard; and on Arbitrum `startedAt` can be `0` before initialisation, so add `require(startedAt != 0)`.

- **Production alternatives, briefly.** Chainlink Data Feeds (push; heartbeat + deviation) remain the default. Chainlink Data Streams and Pyth are pull-based with sub-second latency, suited to perps. RedStone covers long-tail and LST/LRT assets. API3 auctions oracle-extractable value back to the integrating protocol. Consensus practice is multi-source pricing with deviation limits and circuit breakers, not a single feed.

---

## Run it

```bash
forge install foundry-rs/forge-std
forge test -vvvv
```

| Test | Asserts |
|---|---|
| `test_NaiveOracleAllowsMassiveOverBorrow` | manipulation succeeds, 8,000 QUOTE extracted, attacker nets +7,888.89 |
| `test_TwapDefeatsSameAttack` | same attack, `borrow` reverts, attacker nets −111.11, vault untouched |

---

## Known simplifications

This is a minimal simulation, not a production protocol. Deliberately omitted:

- **No flash loan contract.** The attacker's 9,000 QUOTE is pre-minted. The unwind proves the round trip is profitable, which is the only property a flash loan requires.
- **No swap fees.** Real AMM fees add to the attacker's cost and make thin-pool manipulation marginally less profitable.
- **`LendingVault` has no `withdraw` or liquidation.** Deposited collateral is permanently stranded — which is why the attacker abandoning 100 COLL is modelled as a pure cost rather than a recoverable position.
- **No interest accrual.** Irrelevant to an attack that completes in one transaction.
- **`MockERC20` is not ERC-20 compliant.** No events, no return-value conventions, no supply accounting. It exists to move balances.

---

## Real-world instances of this exact bug

**Moonwell, Base — August 2026 (~$8 – 9M).** The closest real-world mirror of this lab. An attacker inflated the illiquid MAMO token from roughly $0.01 to $0.43 against a spot oracle with no TWAP protection, then borrowed against the inflated collateral across four markets, draining cbBTC and other assets. Same shape as the simulation above, at production scale, four years after the pattern was well documented.

**Inverse Finance, April 2022 (~$15.6M).** Planned as the next lab: a forked-mainnet replication. Worth stating the mechanism precisely, because it is widely described incorrectly — **this was not a flash loan attack.** The attacker funded it with their own capital from Tornado Cash and manipulated a Keep3r TWAP oracle reading SushiSwap INV pools. The oracle's `timeElapsed > periodSize` guard was bypassed (`timeElapsed == 15`), so a manipulated price submitted as a private bundle in one block was recorded into the accumulator and reused in the next. Inverse stated publicly that no flash loan was involved.

That is a **TWAP sampling bug**, not a TWAP failure — a direct sequel to takeaway #4 in this lab, and the reason the accumulator ordering in `MiniAMMTWAP._update` is worth getting right.

Not to be confused with Inverse's *second* 2022 incident (June, ~$5.83M DOLA bad debt), which **was** a flash-loan attack, against an LP-token price derived from manipulable Curve pool balances. Two different bugs, two months apart, same protocol.
