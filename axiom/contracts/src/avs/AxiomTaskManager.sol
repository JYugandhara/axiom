// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./OperatorRegistry.sol";

/// @title AxiomTaskManager
/// @notice Manages game compute tasks dispatched to EigenLayer AVS operators.
///         Emits NewTask events that avs-operator nodes listen to.
///         Receives submitTaskResponse() calls with results + ZK proofs.
contract AxiomTaskManager is AccessControl, ReentrancyGuard {
    bytes32 public constant WORLD_ROLE    = keccak256("WORLD_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    // ── Task types (must match TaskType in avs-operator/src/types.rs) ──
    uint8 public constant TASK_PATHFINDING       = 0;
    uint8 public constant TASK_AI_ACTION         = 1;
    uint8 public constant TASK_BATTLE_RESOLUTION = 2;

    uint64 public constant DEADLINE_BLOCKS = 50; // ~25s at 500ms blocks

    struct Task {
        uint8   taskType;
        bytes   payload;
        uint256 civId;
        uint64  createdBlock;
        uint64  deadlineBlock;
        bool    completed;
        address operator;
    }

    OperatorRegistry public immutable registry;

    uint256 public taskCount;
    mapping(uint256 => Task)    private _tasks;
    uint256[]                   private _pendingIds;
    mapping(uint256 => uint256) private _pendingIdx;

    // ── Events ─────────────────────────────────────────────────
    event NewTask(
        uint256 indexed taskId,
        uint8           taskType,
        bytes           payload,
        uint256 indexed civId,
        uint64          deadlineBlock
    );
    event TaskResponded(
        uint256 indexed taskId,
        address indexed operator,
        bool            accepted
    );
    event TaskExpired(uint256 indexed taskId);

    // ── Errors ─────────────────────────────────────────────────
    error NotRegisteredOperator(address op);
    error TaskAlreadyCompleted(uint256 taskId);
    error TaskDeadlinePassed(uint256 taskId, uint64 deadline, uint64 current);
    error TaskNotFound(uint256 taskId);
    error InvalidTaskType(uint8 taskType);

    constructor(address admin, address _registry) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RESOLVER_ROLE,      admin);
        registry = OperatorRegistry(_registry);
    }

    // ── Task creation ──────────────────────────────────────────

    /// @notice Create a new compute task. Only callable by the world contract.
    /// @param taskType  Task type constant (0=pathfinding, 1=AI, 2=battle).
    /// @param payload   ABI-encoded task parameters.
    /// @param civId     Civilization NFT ID that triggered this task.
    /// @return taskId   Incrementing task identifier.
    function createTask(
        uint8 taskType,
        bytes calldata payload,
        uint256 civId
    ) external onlyRole(WORLD_ROLE) returns (uint256 taskId) {
        if (taskType > TASK_BATTLE_RESOLUTION) revert InvalidTaskType(taskType);

        taskId = ++taskCount;
        uint64 deadline = uint64(block.number) + DEADLINE_BLOCKS;

        _tasks[taskId] = Task({
            taskType    : taskType,
            payload     : payload,
            civId       : civId,
            createdBlock: uint64(block.number),
            deadlineBlock: deadline,
            completed   : false,
            operator    : address(0)
        });

        _pendingIdx[taskId] = _pendingIds.length;
        _pendingIds.push(taskId);

        emit NewTask(taskId, taskType, payload, civId, deadline);
    }

    // ── Task response ──────────────────────────────────────────

    /// @notice Submit a computed task response. Called by AVS operators.
    /// @param taskId        The task being answered.
    /// @param taskType      Must match the stored task type.
    /// @param resultPayload ABI-encoded result data.
    /// @param zkProof       EZKL proof bytes (for AI tasks).
    /// @param signature     Operator ECDSA signature over keccak256(taskId || resultPayload).
    function submitTaskResponse(
        uint256 taskId,
        uint8   taskType,
        bytes calldata resultPayload,
        bytes calldata zkProof,
        bytes calldata signature
    ) external nonReentrant {
        if (!registry.isRegistered(msg.sender)) revert NotRegisteredOperator(msg.sender);

        Task storage t = _tasks[taskId];
        if (t.createdBlock == 0)        revert TaskNotFound(taskId);
        if (t.completed)                revert TaskAlreadyCompleted(taskId);
        if (block.number > t.deadlineBlock)
            revert TaskDeadlinePassed(taskId, t.deadlineBlock, uint64(block.number));

        t.completed = true;
        t.operator  = msg.sender;

        _removePending(taskId);

        // Track operator performance
        registry.recordTask(msg.sender, true);

        emit TaskResponded(taskId, msg.sender, true);
    }

    /// @notice Mark expired tasks so operators can skip them.
    function expireTask(uint256 taskId) external {
        Task storage t = _tasks[taskId];
        if (t.createdBlock == 0)  revert TaskNotFound(taskId);
        if (t.completed)          revert TaskAlreadyCompleted(taskId);
        require(block.number > t.deadlineBlock, "TaskManager: not expired");

        t.completed = true;
        _removePending(taskId);

        emit TaskExpired(taskId);
    }

    // ── Views ──────────────────────────────────────────────────

    function getTask(uint256 taskId) external view returns (Task memory) {
        return _tasks[taskId];
    }

    function pendingTaskIds() external view returns (uint256[] memory) {
        return _pendingIds;
    }

    function isOperatorRegistered(address op) external view returns (bool) {
        return registry.isRegistered(op);
    }

    // ── Admin ──────────────────────────────────────────────────

    function setWorldRole(address world) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(WORLD_ROLE, world);
    }

    // ── Internal ───────────────────────────────────────────────

    function _removePending(uint256 taskId) internal {
        uint256 idx  = _pendingIdx[taskId];
        uint256 last = _pendingIds[_pendingIds.length - 1];
        _pendingIds[idx] = last;
        _pendingIdx[last] = idx;
        _pendingIds.pop();
        delete _pendingIdx[taskId];
    }
}
