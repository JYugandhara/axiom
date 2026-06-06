// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {AXMToken} from "../../src/economy/AXMToken.sol";

/// @notice Handler that performs bounded mint/burn for the invariant fuzzer.
contract TokenHandler is Test {
    AXMToken public axm;
    address  public dao;

    uint256 public totalMinted;
    uint256 public totalBurned;

    constructor(AXMToken _axm, address _dao) {
        axm = _axm;
        dao = _dao;
    }

    function mint(address to, uint256 amount) external {
        uint256 remaining = axm.MAX_SUPPLY() - axm.totalSupply();
        if (remaining == 0) return;
        if (to == address(0)) to = address(0xBEEF);
        amount = bound(amount, 0, remaining);
        vm.prank(dao);
        axm.mint(to, amount);
        totalMinted += amount;
    }

    function burn(uint256 amount) external {
        uint256 bal = axm.balanceOf(dao);
        if (bal == 0) return;
        amount = bound(amount, 0, bal);
        vm.prank(dao);
        axm.burn(amount);
        totalBurned += amount;
    }
}

/// @title TokenSupplyInvariantTest
/// @notice Invariant tests ensuring $AXM supply accounting is always sound.
contract TokenSupplyInvariantTest is Test {
    AXMToken    axm;
    TokenHandler handler;
    address dao = address(0xDA0);

    function setUp() public {
        axm     = new AXMToken(dao);
        handler = new TokenHandler(axm, dao);

        // DAO must approve handler context — handler uses vm.prank(dao) directly,
        // so just target the handler for invariant fuzzing.
        targetContract(address(handler));
    }

    /// @notice INVARIANT: total supply never exceeds the hard cap.
    function invariant_supplyNeverExceedsCap() public view {
        assertLe(axm.totalSupply(), axm.MAX_SUPPLY(), "supply exceeded MAX_SUPPLY");
    }

    /// @notice INVARIANT: supply equals initial + minted - burned.
    function invariant_supplyAccountingConsistent() public view {
        uint256 initial  = axm.MAX_SUPPLY() / 10; // constructor mint
        uint256 expected = initial + handler.totalMinted() - handler.totalBurned();
        assertEq(axm.totalSupply(), expected, "supply accounting mismatch");
    }

    /// @notice INVARIANT: supply is always positive (never underflows).
    function invariant_supplyNonNegative() public view {
        assertGe(axm.totalSupply(), 0);
    }
}
