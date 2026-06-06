// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AgentActionsStore
/// @notice MUD v2 table — queue of pending autonomous agent actions
///         submitted by EigenLayer AVS operators with ZK proofs.
contract AgentActionsStore {
    struct AgentAction {
        uint256 civId;
        uint8   actionType;   // 0-7 matches ACTION_NAMES from train.py
        bytes   proof;        // EZKL ZK proof
        uint256 taskId;       // EigenLayer task ID
        uint64  submittedAt;  // block.number when submitted
        bool    executed;
    }

    mapping(uint256 => AgentAction) private _actions;       // taskId → action
    uint256[]                       private _pendingTaskIds;
    mapping(uint256 => uint256)     private _pendingIndex;  // taskId → array index

    address public world;
    modifier onlyWorld() { require(msg.sender == world, "AgentActions: not world"); _; }

    event ActionQueued(uint256 indexed taskId, uint256 indexed civId, uint8 actionType);
    event ActionExecuted(uint256 indexed taskId, uint256 indexed civId);

    constructor(address _world) { world = _world; }

    function enqueue(uint256 taskId, uint256 civId, uint8 actionType, bytes calldata proof)
        external onlyWorld
    {
        _actions[taskId] = AgentAction(civId, actionType, proof, taskId, uint64(block.number), false);
        _pendingIndex[taskId] = _pendingTaskIds.length;
        _pendingTaskIds.push(taskId);
        emit ActionQueued(taskId, civId, actionType);
    }

    function markExecuted(uint256 taskId) external onlyWorld {
        AgentAction storage a = _actions[taskId];
        a.executed = true;
        uint256 idx  = _pendingIndex[taskId];
        uint256 last = _pendingTaskIds[_pendingTaskIds.length - 1];
        _pendingTaskIds[idx] = last;
        _pendingIndex[last]  = idx;
        _pendingTaskIds.pop();
        delete _pendingIndex[taskId];
        emit ActionExecuted(taskId, a.civId);
    }

    function get(uint256 taskId) external view returns (AgentAction memory) {
        return _actions[taskId];
    }

    function pendingTaskIds() external view returns (uint256[] memory) {
        return _pendingTaskIds;
    }
}
