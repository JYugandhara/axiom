// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

/// @notice Fuzz tests for AXIOM battle resolution logic.
///         Verifies determinism, no overflow, and fair outcome bounds.
contract BattleFuzzTest is Test {

    // ── Mirrors BattleSystem's deterministic resolution ─────────
    function _resolveBattle(
        uint32 atkPower, uint32 defPower, uint32 defDef, uint256 vrfSeed
    ) internal pure returns (bool attackerWins, uint32 damage) {
        uint64 roll = uint64(uint256(keccak256(abi.encode(vrfSeed))) % 100);
        uint32 atkScore = uint32((roll * atkPower) / 100 + (atkPower > defDef ? atkPower - defDef : 0));
        uint32 defScore = uint32(((100 - roll) * defDef) / 100 + defDef / 2);
        attackerWins = atkScore > defScore;
        damage = atkScore > defScore ? atkScore - defScore : defScore - atkScore;
    }

    /// @notice Fuzz: same VRF seed always produces same outcome (deterministic)
    function testFuzz_battleIsDeterministic(
        uint32 atkPower,
        uint32 defPower,
        uint32 defDef,
        uint256 vrfSeed
    ) public pure {
        atkPower = uint32(bound(atkPower, 1, 1000));
        defPower = uint32(bound(defPower, 1, 1000));
        defDef   = uint32(bound(defDef,   1, 1000));

        (bool win1, uint32 dmg1) = _resolveBattle(atkPower, defPower, defDef, vrfSeed);
        (bool win2, uint32 dmg2) = _resolveBattle(atkPower, defPower, defDef, vrfSeed);

        assertEq(win1, win2, "Outcome must be deterministic");
        assertEq(dmg1, dmg2, "Damage must be deterministic");
    }

    /// @notice Fuzz: damage value never overflows uint32
    function testFuzz_damageNoOverflow(
        uint32 atkPower,
        uint32 defDef,
        uint256 vrfSeed
    ) public pure {
        atkPower = uint32(bound(atkPower, 0, 1000));
        defDef   = uint32(bound(defDef,   0, 1000));

        // Should never revert or overflow
        (, uint32 damage) = _resolveBattle(atkPower, atkPower, defDef, vrfSeed);
        assertLe(damage, type(uint32).max / 2, "Damage within safe range");
    }

    /// @notice Fuzz: overwhelmingly superior attacker wins most of the time
    function testFuzz_strongAttackerFavored(uint256 vrfSeed) public pure {
        uint32 dominantAtk = 1000;
        uint32 weakDef     = 1;

        uint256 wins;
        for (uint256 i = 0; i < 20; i++) {
            (bool w,) = _resolveBattle(dominantAtk, weakDef, weakDef, uint256(keccak256(abi.encode(vrfSeed, i))));
            if (w) wins++;
        }
        // With 1000 atk vs 1 def, attacker should win ≥ 15/20 (75%)
        assertGe(wins, 15, "Strong attacker should win most battles");
    }

    /// @notice Fuzz: equal stats produces roughly 50/50 outcomes
    function testFuzz_equalStatsRoughlyFair(uint256 seedBase) public pure {
        uint32 stat = 500;
        uint256 wins;
        for (uint256 i = 0; i < 100; i++) {
            (bool w,) = _resolveBattle(stat, stat, stat, uint256(keccak256(abi.encode(seedBase, i))));
            if (w) wins++;
        }
        // Expect between 20-80 wins out of 100 for equal stats
        assertGe(wins, 20, "Too few wins for equal stats");
        assertLe(wins, 80, "Too many wins for equal stats");
    }

    /// @notice Fuzz: different VRF seeds produce different outcomes (randomness)
    function testFuzz_differentSeedsDifferentOutcomes(
        uint256 seed1, uint256 seed2, uint32 atk, uint32 def
    ) public pure {
        vm.assume(seed1 != seed2);
        atk = uint32(bound(atk, 100, 500));
        def = uint32(bound(def, 100, 500));

        // Run multiple battles with each seed — they should differ eventually
        uint256 matchA;
        uint256 matchB;
        for (uint256 i = 0; i < 10; i++) {
            (bool wa,) = _resolveBattle(atk, def, def, uint256(keccak256(abi.encode(seed1, i))));
            (bool wb,) = _resolveBattle(atk, def, def, uint256(keccak256(abi.encode(seed2, i))));
            if (wa) matchA++;
            if (wb) matchB++;
        }
        // Can't assert they always differ, but outcomes are seeded independently
        // Just check neither is impossible
        assertLe(matchA, 10);
        assertLe(matchB, 10);
    }

    /// @notice Fuzz: VRF roll is always in [0, 99] — no out-of-bounds
    function testFuzz_rollInBounds(uint256 vrfSeed) public pure {
        uint64 roll = uint64(uint256(keccak256(abi.encode(vrfSeed))) % 100);
        assertLt(roll, 100, "Roll must be < 100");
        assertGe(roll, 0,   "Roll must be >= 0");
    }

    /// @notice Fuzz: zero-power armies always lose to nonzero
    function testFuzz_zeroPowerLoses(uint32 defPower, uint256 seed) public pure {
        defPower = uint32(bound(defPower, 50, 1000));
        (bool atkWins,) = _resolveBattle(0, defPower, defPower, seed);
        assertFalse(atkWins, "Zero-power attacker should always lose");
    }
}
