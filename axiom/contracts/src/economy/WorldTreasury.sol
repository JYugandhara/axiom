// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface IERC20Treasury {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title WorldTreasury
/// @notice DAO-controlled vault. Collects marketplace fees, prediction-market
///         rake, and season entry fees. Funds rewards and gas subsidies.
contract WorldTreasury is ReentrancyGuard, AccessControl {
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");

    event Received(address indexed token, address indexed from, uint256 amount);
    event Spent(address indexed token, address indexed to, uint256 amount);
    event NativeReceived(address indexed from, uint256 amount);

    error ZeroAddress();
    error TransferFailed();

    constructor(address dao) {
        if (dao == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, dao);
        _grantRole(SPENDER_ROLE, dao);
    }

    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }

    /// @notice Spend ERC-20 tokens from the treasury. DAO/spender only.
    function spend(address token, address to, uint256 amount)
        external onlyRole(SPENDER_ROLE) nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        bool ok = IERC20Treasury(token).transfer(to, amount);
        if (!ok) revert TransferFailed();
        emit Spent(token, to, amount);
    }

    /// @notice Spend native ETH from the treasury. DAO/spender only.
    function spendNative(address payable to, uint256 amount)
        external onlyRole(SPENDER_ROLE) nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Spent(address(0), to, amount);
    }

    function balance(address token) external view returns (uint256) {
        return IERC20Treasury(token).balanceOf(address(this));
    }

    function nativeBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
