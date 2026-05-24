// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/mud/systems/ClaimSystem.sol";
import "../../src/mud/tables/TerritoryMap.sol";
import "../../src/mud/tables/CivilizationState.sol";
import "../../src/mud/tables/AgentActions.sol";

contract MockTerritoryVerifier {
    bool public pass = true;
    function verify(bytes calldata, bytes32[] calldata) external view returns (bool) { return pass; }
    function setPass(bool v) external { pass = v; }
}

contract ClaimSystemTest is Test {
    ClaimSystem            claim;
    MockTerritoryVerifier  verifier;
    TerritoryMapStore      territory;
    CivilizationStateStore civs;
    GameConfigStore        cfg;

    address alice = address(0xA);
    uint256 CIV   = 1;
    bytes32 ANCHOR = keccak256("anchor");
    bytes32 TILE   = keccak256("new_tile");
    bytes32 CIVHASH = keccak256("civhash");

    function setUp() public {
        verifier  = new MockTerritoryVerifier();
        civs      = new CivilizationStateStore(address(this));
        territory = new TerritoryMapStore(address(this));
        cfg       = new GameConfigStore(address(this), address(this));

        claim = new ClaimSystem(
            address(verifier),
            address(territory),
            address(civs),
            address(cfg)
        );

        // Bootstrap civ
        CivilizationState.Data memory d;
        d.owner = alice; d.territory = 1; d.claimNonce = 0; d.season = 1;
        civs.set(CIV, d);

        // Alice already owns anchor tile
        territory.claim(ANCHOR, CIV);
    }

    function test_validClaim() public {
        vm.prank(alice);
        claim.claim(CIV, TILE, ANCHOR, CIVHASH, 0, bytes("proof"));
        assertEq(territory.ownerOf(TILE), CIV);
    }

    function test_claimIncreasesTerritoryCount() public {
        vm.prank(alice);
        claim.claim(CIV, TILE, ANCHOR, CIVHASH, 0, bytes("proof"));
        CivilizationState.Data memory d = civs.get(CIV);
        assertEq(d.territory, 2); // was 1, now 2
    }

    function test_claimIncrementsNonce() public {
        vm.prank(alice);
        claim.claim(CIV, TILE, ANCHOR, CIVHASH, 0, bytes("proof"));
        CivilizationState.Data memory d = civs.get(CIV);
        assertEq(d.claimNonce, 1);
    }

    function test_notOwnerReverts() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(ClaimSystem.NotCivOwner.selector);
        claim.claim(CIV, TILE, ANCHOR, CIVHASH, 0, bytes("proof"));
    }

    function test_wrongNonceReverts() public {
        vm.prank(alice);
        vm.expectRevert(ClaimSystem.InvalidNonce.selector);
        claim.claim(CIV, TILE, ANCHOR, CIVHASH, 5, bytes("proof")); // nonce should be 0
    }

    function test_anchorNotOwnedReverts() public {
        bytes32 fakeAnchor = keccak256("not_owned");
        vm.prank(alice);
        vm.expectRevert(ClaimSystem.AnchorNotOwned.selector);
        claim.claim(CIV, TILE, fakeAnchor, CIVHASH, 0, bytes("proof"));
    }

    function test_invalidProofReverts() public {
        verifier.setPass(false);
        vm.prank(alice);
        vm.expectRevert(ClaimSystem.InvalidProof.selector);
        claim.claim(CIV, TILE, ANCHOR, CIVHASH, 0, bytes("bad"));
    }

    function test_doubleClaimReverts() public {
        vm.prank(alice);
        claim.claim(CIV, TILE, ANCHOR, CIVHASH, 0, bytes("proof"));
        // Try to claim same tile again
        vm.prank(alice);
        vm.expectRevert(); // TileAlreadyClaimed
        claim.claim(CIV, TILE, ANCHOR, CIVHASH, 1, bytes("proof"));
    }

    function test_pausedGameReverts() public {
        cfg.pause(true);
        vm.prank(alice);
        vm.expectRevert(ClaimSystem.GamePaused.selector);
        claim.claim(CIV, TILE, ANCHOR, CIVHASH, 0, bytes("proof"));
    }

    function testFuzz_multipleConsecutiveClaims(uint8 n) public {
        n = uint8(bound(n, 1, 5));
        for (uint8 i = 0; i < n; i++) {
            bytes32 newTile = keccak256(abi.encode("tile", i));
            bytes32 anchor  = i == 0 ? ANCHOR : keccak256(abi.encode("tile", i - 1));
            vm.prank(alice);
            claim.claim(CIV, newTile, anchor, CIVHASH, i, bytes("proof"));
        }
        CivilizationState.Data memory d = civs.get(CIV);
        assertEq(d.territory, 1 + n);
        assertEq(d.claimNonce, n);
    }
}
