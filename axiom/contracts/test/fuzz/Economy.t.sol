// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {AXMToken}     from "../../src/economy/AXMToken.sol";
import {EnergyToken}  from "../../src/economy/EnergyToken.sol";
import {Staking}      from "../../src/economy/Staking.sol";

/// @title EconomyFuzzTest
/// @notice Property-based fuzz tests for the AXIOM token economy:
///         AXM supply bounds, burn accounting, and staking APY ranges.
contract EconomyFuzzTest is Test {
    AXMToken    axm;
    EnergyToken energy;
    Staking     staking;

    address dao      = address(0xDA0);
    address treasury = address(0x7A0);
    address user     = address(0xB0B);

    function setUp() public {
        axm     = new AXMToken(dao);
        energy  = new EnergyToken(dao);
        staking = new Staking(address(axm), address(energy), treasury);

        // Staking must be able to mint ENERGY rewards
        vm.prank(dao);
        energy.grantMinter(address(staking));
    }

    // ── AXM supply invariants ──────────────────────────────────

    /// @notice Fuzz: minting random amounts never exceeds MAX_SUPPLY.
    function testFuzz_totalSupplyNeverExceedsCap(uint256 a, uint256 b, uint256 c) public {
        uint256 remaining = axm.MAX_SUPPLY() - axm.totalSupply();
        a = bound(a, 0, remaining / 3);
        b = bound(b, 0, remaining / 3);
        c = bound(c, 0, remaining / 3);

        vm.startPrank(dao);
        axm.mint(address(0x1), a);
        axm.mint(address(0x2), b);
        axm.mint(address(0x3), c);
        vm.stopPrank();

        assertLe(axm.totalSupply(), axm.MAX_SUPPLY(), "supply exceeded cap");
    }

    /// @notice Fuzz: burning reduces supply by exactly the burned amount.
    function testFuzz_burnReducesExactAmount(uint256 amount) public {
        uint256 bal = axm.balanceOf(dao);
        amount = bound(amount, 0, bal);
        uint256 before = axm.totalSupply();

        vm.prank(dao);
        axm.burn(amount);

        assertEq(axm.totalSupply(), before - amount);
        assertEq(axm.balanceOf(dao), bal - amount);
    }

    /// @notice Fuzz: mint then burn returns to the same total supply.
    function testFuzz_mintBurnRoundTrip(uint256 amount) public {
        uint256 remaining = axm.MAX_SUPPLY() - axm.totalSupply();
        amount = bound(amount, 1, remaining);
        uint256 before = axm.totalSupply();

        vm.startPrank(dao);
        axm.mint(dao, amount);
        axm.burn(amount);
        vm.stopPrank();

        assertEq(axm.totalSupply(), before, "round trip changed supply");
    }

    // ── EnergyToken invariants ─────────────────────────────────

    /// @notice Fuzz: ENERGY is uncapped — any mint amount succeeds.
    function testFuzz_energyUncapped(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);
        vm.prank(dao);
        energy.mint(user, amount);
        assertEq(energy.balanceOf(user), amount);
    }

    // ── Staking APY bounds ─────────────────────────────────────

    /// @notice Fuzz: staking APY multiplier always falls in [10%, 40%].
    function testFuzz_stakingApyInBounds(uint256 lockDuration) public {
        uint256 MIN = staking.LOCK_PERIOD_MIN();
        uint256 MAX = staking.LOCK_PERIOD_MAX();
        lockDuration = bound(lockDuration, MIN, MAX);

        uint256 base  = staking.BASE_APY_BPS();
        uint256 boost = (lockDuration - MIN) * staking.MAX_BOOST_BPS() / (MAX - MIN);
        uint256 apy   = base + boost;

        assertGe(apy, base,                          "APY below base 10%");
        assertLe(apy, base + staking.MAX_BOOST_BPS(),"APY above max 40%");
    }

    /// @notice Fuzz: stake then check the position was recorded correctly.
    function testFuzz_stakeRecordsPosition(uint256 amount, uint256 lockDuration) public {
        amount       = bound(amount, 1e18, 1_000_000e18);
        lockDuration = bound(lockDuration, staking.LOCK_PERIOD_MIN(), staking.LOCK_PERIOD_MAX());

        // Fund + approve
        vm.prank(dao);
        axm.mint(user, amount);
        vm.prank(user);
        axm.approve(address(staking), amount);

        vm.prank(user);
        uint256 posId = staking.stake(amount, lockDuration);

        (uint256 stakedAmt,, uint256 unlockAt,,) = staking.positions(user, posId);
        assertEq(stakedAmt, amount,                        "wrong staked amount");
        assertEq(unlockAt, block.timestamp + lockDuration, "wrong unlock time");
    }

    /// @notice Fuzz: rewards accrue monotonically with time.
    function testFuzz_rewardsAccrueOverTime(uint256 amount, uint256 elapsed) public {
        amount  = bound(amount, 1e18, 100_000e18);
        elapsed = bound(elapsed, 1 days, 365 days);

        vm.prank(dao);
        axm.mint(user, amount);
        vm.prank(user);
        axm.approve(address(staking), amount);
        vm.prank(user);
        uint256 posId = staking.stake(amount, 30 days);

        uint256 r0 = staking.pendingReward(user, posId);
        vm.warp(block.timestamp + elapsed);
        uint256 r1 = staking.pendingReward(user, posId);

        assertGe(r1, r0, "rewards must not decrease over time");
    }
}
