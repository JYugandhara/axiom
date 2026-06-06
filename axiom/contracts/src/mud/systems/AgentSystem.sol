// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAIVerifierAgent {
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external returns (bool);
}
interface IAgentActions {
    struct AgentAction {
        uint256 civId; uint8 actionType; bytes proof;
        uint256 taskId; uint64 submittedAt; bool executed;
    }
    function get(uint256 taskId) external view returns (AgentAction memory);
    function markExecuted(uint256 taskId) external;
}
interface ICivStateAgent {
    struct Data {
        uint256 territory; uint256 energyBalance; uint256 energyPerBlock;
        bytes32 agentModelHash; bool isAutonomous; uint64 moveNonce; uint64 claimNonce;
        uint32 attackPower; uint32 defensePower; uint32 season; address owner;
    }
    function get(uint256 civId) external view returns (Data memory);
}

/// @title AgentSystem
/// @notice Executes autonomous AI agent actions from the AgentActions queue.
///         Verifies the EZKL ML-inference proof before applying any action.
contract AgentSystem {
    IAIVerifierAgent public immutable aiVerifier;
    IAgentActions    public immutable agentActions;
    ICivStateAgent   public immutable civState;
    address          public immutable taskManager;

    event AgentActionExecuted(uint256 indexed taskId, uint256 indexed civId, uint8 action);

    error NotTaskManager();
    error AlreadyExecuted();
    error InvalidAIProof();
    error NotAutonomous(uint256 civId);

    constructor(address _verifier, address _actions, address _civ, address _tm) {
        aiVerifier   = IAIVerifierAgent(_verifier);
        agentActions = IAgentActions(_actions);
        civState     = ICivStateAgent(_civ);
        taskManager  = _tm;
    }

    /// @notice Called by TaskManager when the AVS submits an agent action + ZK proof.
    function executeAgentAction(
        uint256 taskId,
        uint256 civId,
        uint8   action,
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external {
        if (msg.sender != taskManager) revert NotTaskManager();

        IAgentActions.AgentAction memory a = agentActions.get(taskId);
        if (a.executed) revert AlreadyExecuted();

        ICivStateAgent.Data memory civ = civState.get(civId);
        if (!civ.isAutonomous) revert NotAutonomous(civId);

        // Verify the EZKL ZK proof of ML inference
        if (!aiVerifier.verify(proof, publicInputs)) revert InvalidAIProof();

        agentActions.markExecuted(taskId);
        emit AgentActionExecuted(taskId, civId, action);
        // Downstream systems apply the concrete effects based on action type (0-7).
    }
}
