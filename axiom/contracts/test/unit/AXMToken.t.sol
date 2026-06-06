// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {AXMToken} from "../../src/economy/AXMToken.sol";

/// @title AXMTokenTest
/// @notice Unit tests for the $AXM governance token.
contract AXMTokenTest is Test {
    AXMToken axm;
    address dao  = address(0xDA0);
    address user = address(0xB0B);

    function setUp() public {
        axm = new AXMToken(dao);
    }

    // ── Supply ─────────────────────────────────────────────────

    function test_initialSupply() public view {
        // 10% of MAX_SUPPLY minted to DAO at construction
        assertEq(axm.totalSupply(), axm.MAX_SUPPLY() / 10);
        assertEq(axm.balanceOf(dao), axm.MAX_SUPPLY() / 10);
    }

    function test_maxSupplyConstant() public view {
        assertEq(axm.MAX_SUPPLY(), 1_000_000_000 * 1e18);
    }

    // ── Minting ────────────────────────────────────────────────

    function test_mint_byMinter() public {
        vm.prank(dao);
        axm.mint(user, 1000e18);
        assertEq(axm.balanceOf(user), 1000e18);
    }

    function test_mint_exceedsCapReverts() public {
        vm.prank(dao);
        vm.expectRevert();
        axm.mint(user, axm.MAX_SUPPLY()); // 10% already minted
    }

    function test_mint_exactlyToCapSucceeds() public {
        uint256 remaining = axm.MAX_SUPPLY() - axm.totalSupply();
        vm.prank(dao);
        axm.mint(user, remaining);
        assertEq(axm.totalSupply(), axm.MAX_SUPPLY());
    }

    function test_mint_unauthorizedReverts() public {
        vm.prank(user);
        vm.expectRevert();
        axm.mint(user, 1e18);
    }

    // ── Burning ────────────────────────────────────────────────

    function test_burn_reducesSupply() public {
        uint256 before = axm.totalSupply();
        vm.prank(dao);
        axm.burn(500e18);
        assertEq(axm.totalSupply(), before - 500e18);
    }

    function test_burn_freesCapForReMint() public {
        vm.startPrank(dao);
        uint256 remaining = axm.MAX_SUPPLY() - axm.totalSupply();
        axm.mint(dao, remaining);       // hit the cap
        axm.burn(1000e18);              // free up space
        axm.mint(user, 1000e18);        // can mint again
        vm.stopPrank();
        assertEq(axm.totalSupply(), axm.MAX_SUPPLY());
    }

    // ── Transfers ──────────────────────────────────────────────

    function test_transfer() public {
        vm.prank(dao);
        axm.transfer(user, 100e18);
        assertEq(axm.balanceOf(user), 100e18);
    }

    function test_approveAndTransferFrom() public {
        vm.prank(dao);
        axm.approve(user, 50e18);
        vm.prank(user);
        axm.transferFrom(dao, user, 50e18);
        assertEq(axm.balanceOf(user), 50e18);
    }

    // ── Fuzz ───────────────────────────────────────────────────

    function testFuzz_mintWithinCap(uint256 amount) public {
        uint256 remaining = axm.MAX_SUPPLY() - axm.totalSupply();
        amount = bound(amount, 0, remaining);
        vm.prank(dao);
        axm.mint(user, amount);
        assertLe(axm.totalSupply(), axm.MAX_SUPPLY());
    }

    function testFuzz_burnExactReduction(uint256 amount) public {
        uint256 bal = axm.balanceOf(dao);
        amount = bound(amount, 0, bal);
        uint256 before = axm.totalSupply();
        vm.prank(dao);
        axm.burn(amount);
        assertEq(axm.totalSupply(), before - amount);
    }
}
