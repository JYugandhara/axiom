// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PredictionMarket} from "../../src/economy/PredictionMarket.sol";

/// @notice Minimal mock $AXM for prediction-market testing.
contract MockAXM {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external { balanceOf[to] += amt; }
    function approve(address spender, uint256 amt) external returns (bool) {
        allowance[msg.sender][spender] = amt; return true;
    }
    function transfer(address to, uint256 amt) external returns (bool) {
        require(balanceOf[msg.sender] >= amt, "bal");
        balanceOf[msg.sender] -= amt; balanceOf[to] += amt; return true;
    }
    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        require(balanceOf[from] >= amt, "bal");
        require(allowance[from][msg.sender] >= amt, "allow");
        balanceOf[from] -= amt; balanceOf[to] += amt;
        allowance[from][msg.sender] -= amt; return true;
    }
}

/// @title PredictionMarketTest
/// @notice Unit tests for the AMM-based prediction market.
contract PredictionMarketTest is Test {
    PredictionMarket market;
    MockAXM          axm;

    address admin    = address(this);
    address treasury = address(0x7A0);
    address alice    = address(0xA11CE);
    address bob      = address(0xB0B);

    uint256 constant SEED = 100e18;

    function setUp() public {
        axm    = new MockAXM();
        market = new PredictionMarket(address(axm), treasury, admin);

        // Fund treasury for seeding markets
        axm.mint(treasury, 10_000e18);
        vm.prank(treasury);
        axm.approve(address(market), type(uint256).max);

        // Fund bettors
        axm.mint(alice, 1_000e18);
        axm.mint(bob,   1_000e18);
        vm.prank(alice); axm.approve(address(market), type(uint256).max);
        vm.prank(bob);   axm.approve(address(market), type(uint256).max);
    }

    // ── Market creation ────────────────────────────────────────

    function test_createMarket() public {
        uint256 id = market.createMarket(42, 1, 1000);
        assertEq(id, 1);
        (uint256 season, uint256 civId, uint256 yes, uint256 no,,,) = market.markets(id);
        assertEq(season, 1);
        assertEq(civId, 42);
        assertEq(yes, SEED);
        assertEq(no,  SEED);
    }

    function test_createMarket_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        market.createMarket(1, 1, 1000);
    }

    function test_initialOddsAreEven() public {
        uint256 id = market.createMarket(1, 1, 1000);
        // Equal pools → 50% implied probability
        assertEq(market.impliedProbabilityYes(id), 5000);
    }

    // ── Betting ────────────────────────────────────────────────

    function test_betYes() public {
        uint256 id = market.createMarket(1, 1, 1000);
        vm.prank(alice);
        market.bet(id, true, 100e18);

        (,, uint256 yes,,,,) = market.markets(id);
        // Pool grew by net amount (after 2% fee): 100 - 2 = 98
        assertEq(yes, SEED + 98e18);
        assertEq(market.betCount(alice), 1);
    }

    function test_betChargesFee() public {
        uint256 id = market.createMarket(1, 1, 1000);
        uint256 treasuryBefore = axm.balanceOf(treasury);
        vm.prank(alice);
        market.bet(id, true, 100e18);
        // 2% fee = 2 AXM to treasury (plus the original treasury balance)
        assertEq(axm.balanceOf(treasury), treasuryBefore + 2e18);
    }

    function test_betZeroReverts() public {
        uint256 id = market.createMarket(1, 1, 1000);
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.ZeroAmount.selector);
        market.bet(id, true, 0);
    }

    function test_betAfterCloseReverts() public {
        uint256 id = market.createMarket(1, 1, 10);
        vm.roll(block.number + 11); // past close
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.MarketClosed.selector);
        market.bet(id, true, 100e18);
    }

    function test_bettingShiftsOdds() public {
        uint256 id = market.createMarket(1, 1, 1000);
        uint256 before = market.impliedProbabilityYes(id);
        vm.prank(alice);
        market.bet(id, true, 200e18); // big YES bet
        uint256 afterBet = market.impliedProbabilityYes(id);
        // More YES liquidity → YES probability should rise
        assertGt(afterBet, before);
    }

    // ── Resolution + claiming ──────────────────────────────────

    function test_resolveMarket() public {
        uint256 id = market.createMarket(1, 1, 1000);
        market.resolve(id, true);
        (,,,, bool resolved, bool outcome,) = market.markets(id);
        assertTrue(resolved);
        assertTrue(outcome);
    }

    function test_resolveOnlyResolver() public {
        uint256 id = market.createMarket(1, 1, 1000);
        vm.prank(alice);
        vm.expectRevert();
        market.resolve(id, true);
    }

    function test_doubleResolveReverts() public {
        uint256 id = market.createMarket(1, 1, 1000);
        market.resolve(id, true);
        vm.expectRevert(PredictionMarket.AlreadyResolved.selector);
        market.resolve(id, false);
    }

    function test_winnerClaims() public {
        uint256 id = market.createMarket(1, 1, 1000);
        vm.prank(alice);
        market.bet(id, true, 100e18);

        market.resolve(id, true); // YES wins

        uint256 balBefore = axm.balanceOf(alice);
        vm.prank(alice);
        market.claim(0);
        // Winner gets stake + share of losing pool
        assertGt(axm.balanceOf(alice), balBefore);
    }

    function test_loserClaimsNothing() public {
        uint256 id = market.createMarket(1, 1, 1000);
        vm.prank(alice);
        market.bet(id, false, 100e18); // bets NO

        market.resolve(id, true); // YES wins, alice loses

        uint256 balBefore = axm.balanceOf(alice);
        vm.prank(alice);
        market.claim(0); // no revert, but no payout
        assertEq(axm.balanceOf(alice), balBefore);
    }

    function test_doubleClaimReverts() public {
        uint256 id = market.createMarket(1, 1, 1000);
        vm.prank(alice);
        market.bet(id, true, 100e18);
        market.resolve(id, true);

        vm.prank(alice);
        market.claim(0);
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.AlreadyClaimed.selector);
        market.claim(0);
    }

    function test_claimBeforeResolveReverts() public {
        uint256 id = market.createMarket(1, 1, 1000);
        vm.prank(alice);
        market.bet(id, true, 100e18);
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.NotResolved.selector);
        market.claim(0);
    }

    // ── Fuzz ───────────────────────────────────────────────────

    function testFuzz_betSharesPositive(uint256 amount, bool side) public {
        amount = bound(amount, 1e18, 500e18);
        uint256 id = market.createMarket(1, 1, 1000);
        vm.prank(alice);
        market.bet(id, side, amount);
        (, bool isYes, uint256 shares, uint256 axmIn,) = market.userBets(alice, 0);
        assertEq(isYes, side);
        assertGt(shares, 0,        "shares must be positive");
        assertEq(axmIn, amount,    "recorded amount mismatch");
    }
}
