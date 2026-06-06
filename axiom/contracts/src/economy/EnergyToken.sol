// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title EnergyToken
/// @notice $ENERGY — uncapped in-game resource token (L3 only).
///         Minted by EnergySystem per block per tile.
///         Burned for in-game actions (battles, upgrades).
contract EnergyToken is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(address world) ERC20("AXIOM Energy", "ENERGY") {
        _grantRole(DEFAULT_ADMIN_ROLE, world);
        _grantRole(MINTER_ROLE, world);
        _grantRole(BURNER_ROLE, world);
    }

    /// @notice Mint $ENERGY. Only callable by EnergySystem / Staking.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Burn $ENERGY from an account. Only callable by game systems.
    function burnFrom(address account, uint256 amount)
        public override onlyRole(BURNER_ROLE)
    {
        _burn(account, amount);
    }

    /// @notice Grant minter role to additional contracts (e.g. Staking rewards).
    function grantMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, minter);
    }
}
