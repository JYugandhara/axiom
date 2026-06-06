// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MoveSystem}             from "../../src/mud/systems/MoveSystem.sol";
import {TerritoryMapStore}      from "../../src/mud/tables/TerritoryMap.sol";
import {CivilizationStateStore, CivilizationState} from "../../src/mud/tables/CivilizationState.sol";
import {GameConfigStore}        from "../../src/mud/tables/GameConfig.sol";

contract MockFogVerifier {
    bool public shouldPass = true;
    function verify(bytes calldata, bytes32[] calldata) external view returns (bool) { return shouldPass; }
    function setShouldPass(bool v) external { shouldPass = v; }
}

contract MoveSystemTest is Test {
    MoveSystem             moveSystem;
    MockFogVerifier        verifier;
    TerritoryMapStore      territory;
    CivilizationStateStore civs;
    GameConfigStore        cfg;

    address alice = address(0xA);
    uint256 CIV   = 1;
    bytes32 FROM  = keccak256("tile_from");
    bytes32 TO    = keccak256("tile_to");

    function setUp() public {
        verifier  = new MockFogVerifier();
        civs      = new CivilizationStateStore(address(this));
        territory = new TerritoryMapStore(address(this));
        cfg       = new GameConfigStore(address(this), address(this));

        moveSystem = new MoveSystem(address(verifier), address(territory), address(civs), address(cfg));

        // Bootstrap: give alice a civ + a tile. Tables trust this contract as world,
        // but MoveSystem mutates via its own address — grant by re-pointing world.
        CivilizationState.Data memory d;
        d.owner = alice; d.territory = 1; d.moveNonce = 0; d.season = 1;
        d.attackPower = 50; d.defensePower = 50;
        civs.set(CIV, d);
        territory.claim(FROM, CIV);

        // Re-deploy tables owned by the move system so it can mutate them.
        // (In production AxiomWorld owns all tables; here we wire directly.)
        _rewireWorld();
    }

    function _rewireWorld() internal {
        // Deploy fresh tables owned by moveSystem, re-seed state.
        civs      = new CivilizationStateStore(address(moveSystem));
        territory = new TerritoryMapStore(address(moveSystem));
        cfg       = new GameConfigStore(address(moveSystem), address(this));
        moveSystem = new MoveSystem(address(verifier), address(territory), address(civs), address(cfg));
        // re-create with correct ownership
        civs      = new CivilizationStateStore(address(moveSystem));
        territory = new TerritoryMapStore(address(moveSystem));
    }

    function test_invalidProofReverts() public {
        // With mock verifier returning false, any move reverts.
        verifier.setShouldPass(false);
        vm.prank(alice);
        vm.expectRevert();
        moveSystem.move(CIV, FROM, TO, 5, 0, bytes("bad"));
    }

    function test_moveTooFarReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        moveSystem.move(CIV, FROM, TO, 100, 0, bytes("proof"));
    }

    function test_wrongOwnerReverts() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        moveSystem.move(CIV, FROM, TO, 5, 0, bytes("proof"));
    }
}
