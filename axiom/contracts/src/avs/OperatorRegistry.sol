// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title OperatorRegistry
/// @notice Tracks EigenLayer AVS operator registrations, stakes,
///         performance scores, and slash history for AXIOM.
contract OperatorRegistry is AccessControl {
    bytes32 public constant SLASHER_ROLE   = keccak256("SLASHER_ROLE");
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    struct Operator {
        address addr;
        uint256 stakedAmount;    // AXM staked (18 decimals)
        uint256 slashCount;
        uint256 tasksCompleted;
        uint256 tasksFailed;
        bool    active;
        uint256 registeredAt;
    }

    mapping(address => Operator) public operators;
    address[]                    public operatorList;
    uint256 public minStake = 1000 * 1e18; // 1,000 AXM

    // ── Events ─────────────────────────────────────────────────
    event OperatorRegistered(address indexed op, uint256 stake);
    event OperatorDeregistered(address indexed op);
    event OperatorSlashed(address indexed op, uint256 amount, string reason);
    event TaskRecorded(address indexed op, bool success);
    event MinStakeUpdated(uint256 newMinStake);

    // ── Errors ─────────────────────────────────────────────────
    error InsufficientStake(uint256 provided, uint256 required);
    error AlreadyRegistered(address op);
    error NotRegistered(address op);
    error ZeroAddress();

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SLASHER_ROLE,       admin);
        _grantRole(REGISTRAR_ROLE,     admin);
    }

    // ── Registration ───────────────────────────────────────────

    /// @notice Register as an AVS operator.
    /// @param stakeAmount Amount of AXM being staked.
    function register(uint256 stakeAmount) external {
        if (operators[msg.sender].active) revert AlreadyRegistered(msg.sender);
        if (stakeAmount < minStake) revert InsufficientStake(stakeAmount, minStake);

        operators[msg.sender] = Operator({
            addr           : msg.sender,
            stakedAmount   : stakeAmount,
            slashCount     : 0,
            tasksCompleted : 0,
            tasksFailed    : 0,
            active         : true,
            registeredAt   : block.timestamp
        });
        operatorList.push(msg.sender);

        emit OperatorRegistered(msg.sender, stakeAmount);
    }

    /// @notice Deregister — callable by operator themselves.
    function deregister() external {
        if (!operators[msg.sender].active) revert NotRegistered(msg.sender);
        operators[msg.sender].active = false;
        emit OperatorDeregistered(msg.sender);
    }

    // ── Slashing ───────────────────────────────────────────────

    /// @notice Slash an operator's stake for misbehaviour.
    /// @param op     Operator address.
    /// @param amount Amount to slash (in AXM wei).
    /// @param reason Human-readable reason for the slash.
    function slash(
        address op,
        uint256 amount,
        string calldata reason
    ) external onlyRole(SLASHER_ROLE) {
        if (!operators[op].active) revert NotRegistered(op);

        operators[op].slashCount++;
        operators[op].stakedAmount = operators[op].stakedAmount > amount
            ? operators[op].stakedAmount - amount
            : 0;

        // Auto-deregister if stake falls below minimum
        if (operators[op].stakedAmount < minStake) {
            operators[op].active = false;
            emit OperatorDeregistered(op);
        }

        emit OperatorSlashed(op, amount, reason);
    }

    // ── Performance tracking ───────────────────────────────────

    function recordTask(address op, bool success) external onlyRole(REGISTRAR_ROLE) {
        if (!operators[op].active) revert NotRegistered(op);
        if (success) {
            operators[op].tasksCompleted++;
        } else {
            operators[op].tasksFailed++;
        }
        emit TaskRecorded(op, success);
    }

    // ── Views ──────────────────────────────────────────────────

    function isRegistered(address op) external view returns (bool) {
        return operators[op].active;
    }

    function allOperators() external view returns (address[] memory) {
        return operatorList;
    }

    function activeOperators() external view returns (address[] memory active) {
        uint256 count;
        for (uint256 i = 0; i < operatorList.length; i++) {
            if (operators[operatorList[i]].active) count++;
        }
        active = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < operatorList.length; i++) {
            if (operators[operatorList[i]].active) {
                active[idx++] = operatorList[i];
            }
        }
    }

    function operatorCount() external view returns (uint256) {
        return operatorList.length;
    }

    // ── Admin ──────────────────────────────────────────────────

    function setMinStake(uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minStake = newMin;
        emit MinStakeUpdated(newMin);
    }
}
