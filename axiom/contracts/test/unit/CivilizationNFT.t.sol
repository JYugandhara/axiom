// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/agents/CivilizationNFT.sol";

contract MockAXM {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 amt) external { balanceOf[to] += amt; }
    function approve(address spender, uint256 amt) external { allowance[msg.sender][spender] = amt; }
    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        require(balanceOf[from] >= amt, "insufficient");
        require(allowance[from][msg.sender] >= amt, "not allowed");
        balanceOf[from] -= amt;
        balanceOf[to]   += amt;
        allowance[from][msg.sender] -= amt;
        return true;
    }
}

contract MockRegistry {
    mapping(bytes32 => address) private _accounts;
    uint256 private _counter;
    function createAccount(address, bytes32 salt, uint256, address, uint256) external returns (address addr) {
        addr = address(uint160(uint256(keccak256(abi.encode(salt, ++_counter)))));
        _accounts[salt] = addr;
    }
    function account(address, bytes32 salt, uint256, address, uint256) external view returns (address) {
        return _accounts[salt];
    }
}

contract CivilizationNFTTest is Test {
    CivilizationNFT nft;
    MockAXM         axm;
    MockRegistry    registry;

    address alice = address(0xA1);
    address bob   = address(0xB0);
    address dao   = address(0xDA0);

    uint256 constant MINT_FEE = 100e18;

    function setUp() public {
        axm      = new MockAXM();
        registry = new MockRegistry();

        nft = new CivilizationNFT(
            address(registry),
            address(0xACC), // agentAccountImpl
            address(axm),
            dao,
            MINT_FEE
        );

        // Fund alice
        axm.mint(alice, 1000e18);
        vm.prank(alice);
        axm.approve(address(nft), type(uint256).max);

        // Fund bob
        axm.mint(bob, 1000e18);
        vm.prank(bob);
        axm.approve(address(nft), type(uint256).max);
    }

    // ── Minting ────────────────────────────────────────────────

    function test_mint_success() public {
        vm.prank(alice);
        uint256 tokenId = nft.mint("Iron Citadel");

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.balanceOf(alice), 1);
    }

    function test_mint_chargesAxmFee() public {
        uint256 balBefore = axm.balanceOf(alice);
        vm.prank(alice);
        nft.mint("Storm Guild");
        assertEq(axm.balanceOf(alice), balBefore - MINT_FEE);
        assertEq(axm.balanceOf(dao), MINT_FEE);
    }

    function test_mint_createsTba() public {
        vm.prank(alice);
        uint256 tokenId = nft.mint("Test Civ");
        address tba = nft.agentAccountOf(tokenId);
        assertTrue(tba != address(0));
    }

    function test_mint_incrementingIds() public {
        vm.prank(alice);
        uint256 id1 = nft.mint("First");
        vm.prank(bob);
        uint256 id2 = nft.mint("Second");
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_mint_nameTooLongReverts() public {
        string memory longName = "This name is way too long and exceeds the maximum allowed length!!";
        vm.prank(alice);
        vm.expectRevert(CivilizationNFT.NameTooLong.selector);
        nft.mint(longName);
    }

    function test_mint_storesMetadata() public {
        vm.prank(alice);
        uint256 tokenId = nft.mint("Void Walkers");
        (string memory name, bytes32 modelHash, bool autonomous,) = nft.metadata(tokenId);
        assertEq(name, "Void Walkers");
        assertEq(modelHash, bytes32(0));
        assertFalse(autonomous);
    }

    // ── Agent model ────────────────────────────────────────────

    function test_setAgentModel_byOwner() public {
        vm.prank(alice);
        uint256 id = nft.mint("Test");
        bytes32 hash = keccak256("my_model");
        vm.prank(alice);
        nft.setAgentModel(id, hash);
        (, bytes32 stored,,) = nft.metadata(id);
        assertEq(stored, hash);
    }

    function test_setAgentModel_notOwnerReverts() public {
        vm.prank(alice);
        uint256 id = nft.mint("Test");
        vm.prank(bob);
        vm.expectRevert("CivilizationNFT: not owner");
        nft.setAgentModel(id, keccak256("hack"));
    }

    // ── Autonomy ───────────────────────────────────────────────

    function test_setAutonomous_toggles() public {
        vm.prank(alice);
        uint256 id = nft.mint("Bot Civ");
        vm.prank(alice);
        nft.setAutonomous(id, true);
        (,, bool auto1,) = nft.metadata(id);
        assertTrue(auto1);

        vm.prank(alice);
        nft.setAutonomous(id, false);
        (,, bool auto2,) = nft.metadata(id);
        assertFalse(auto2);
    }

    function test_setAutonomous_notOwnerReverts() public {
        vm.prank(alice);
        uint256 id = nft.mint("Test");
        vm.prank(bob);
        vm.expectRevert("CivilizationNFT: not owner");
        nft.setAutonomous(id, true);
    }

    // ── Transfer ───────────────────────────────────────────────

    function test_transfer_changesOwner() public {
        vm.prank(alice);
        uint256 id = nft.mint("Transfer Test");
        vm.prank(alice);
        nft.transferFrom(alice, bob, id);
        assertEq(nft.ownerOf(id), bob);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
    }

    // ── Fuzz ───────────────────────────────────────────────────

    function testFuzz_mintMultiple(uint8 count) public {
        count = uint8(bound(count, 1, 10));
        axm.mint(alice, uint256(count) * MINT_FEE);
        vm.startPrank(alice);
        axm.approve(address(nft), type(uint256).max);
        for (uint8 i = 0; i < count; i++) {
            nft.mint("Civ");
        }
        vm.stopPrank();
        assertEq(nft.balanceOf(alice), count);
    }
}
