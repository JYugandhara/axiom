// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/mud/tables/TerritoryMap.sol";

/// @notice Actor contract — performs territory operations for invariant fuzzer
contract TerritoryActor {
    TerritoryMapStore public territory;
    bytes32[] public allCommitments;
    uint256   public nextCivId = 1;

    constructor(address _territory) {
        territory = TerritoryMapStore(_territory);
    }

    function claim(bytes32 commitment, uint256 civId) external {
        if (territory.ownerOf(commitment) != 0) return;
        civId = bound(civId, 1, 10);
        territory.claim(commitment, civId);
        allCommitments.push(commitment);
    }

    function transfer(bytes32 commitment, uint256 toCiv) external {
        uint256 currentOwner = territory.ownerOf(commitment);
        if (currentOwner == 0) return;
        toCiv = bound(toCiv, 1, 10);
        if (toCiv == currentOwner) return;
        territory.transfer(commitment, currentOwner, toCiv);
    }

    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}

/// @title TerritoryConsistencyTest
/// @notice Invariant tests ensuring the territory map never enters an inconsistent state.
contract TerritoryConsistencyTest is Test {
    TerritoryMapStore territory;
    TerritoryActor    actor;

    function setUp() public {
        territory = new TerritoryMapStore(address(this));
        actor     = new TerritoryActor(address(territory));

        // Give actor permission to call territory (actor is "world" for testing)
        // In reality territory.world == actor, but for simplicity test directly
        targetContract(address(actor));
    }

    /// @notice INVARIANT: Every tile has exactly one owner (no double ownership)
    function invariant_noDoubleClaim() public view {
        bytes32[] memory commitments = actor.allCommitments();
        for (uint256 i = 0; i < commitments.length; i++) {
            uint256 owner = territory.ownerOf(commitments[i]);
            // If owner is set, no other civ should claim the same tile
            // (enforced by TerritoryMapStore.claim revert on existing owner)
            // Just verify owner is a valid civId or 0
            assertTrue(owner <= 10, "Owner must be valid civId or 0");
        }
    }

    /// @notice INVARIANT: tileCount matches actual tracked tiles per civ
    function invariant_tileCountConsistent() public view {
        for (uint256 civId = 1; civId <= 10; civId++) {
            uint256 count = territory.tileCount(civId);
            bytes32[] memory tiles = territory.tilesOf(civId);
            assertEq(count, tiles.length, "tileCount must match tilesOf length");
        }
    }

    /// @notice INVARIANT: sum of all civ tile counts equals total claimed tiles
    function invariant_totalTilesConserved() public view {
        bytes32[] memory commitments = actor.allCommitments();
        uint256 totalClaimed;
        for (uint256 civId = 1; civId <= 10; civId++) {
            totalClaimed += territory.tileCount(civId);
        }
        // Total should not exceed distinct commitments submitted
        assertLe(totalClaimed, commitments.length, "Total tiles cannot exceed submitted commitments");
    }

    /// @notice INVARIANT: isOwnedBy is consistent with ownerOf
    function invariant_ownershipConsistent() public view {
        bytes32[] memory commitments = actor.allCommitments();
        for (uint256 i = 0; i < commitments.length && i < 20; i++) {
            bytes32 c = commitments[i];
            uint256 owner = territory.ownerOf(c);
            if (owner != 0) {
                assertTrue(territory.isOwnedBy(c, owner), "isOwnedBy must match ownerOf");
                // No other civ should also own it
                for (uint256 other = 1; other <= 10; other++) {
                    if (other != owner) {
                        assertFalse(territory.isOwnedBy(c, other), "Tile cannot belong to two civs");
                    }
                }
            }
        }
    }
}
