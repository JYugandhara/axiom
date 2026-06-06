// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./OperatorRegistry.sol";
import "./AxiomTaskManager.sol";

/// @title AxiomServiceManager
/// @notice Top-level EigenLayer AVS contract.
///         Handles operator registration/deregistration with EigenLayer,
///         coordinates with OperatorRegistry and AxiomTaskManager,
///         and manages the slashing vault.
contract AxiomServiceManager is AccessControl {
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    OperatorRegistry public immutable registry;
    AxiomTaskManager public immutable taskManager;

    address public slashingVault;
    uint256 public totalSlashed;
    uint256 public totalRewardsPaid;

    // Minimum blocks between slash events per operator (cooldown)
    uint256 public constant SLASH_COOLDOWN = 100;
    mapping(address => uint256) public lastSlashBlock;

    // ── Events ─────────────────────────────────────────────────
    event AVSOperatorRegistered(address indexed operator, uint256 stake);
    event AVSOperatorDeregistered(address indexed operator);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event RewardPaid(address indexed operator, uint256 amount);
    event SlashingVaultUpdated(address newVault);

    // ── Errors ─────────────────────────────────────────────────
    error SlashCooldownActive(address op, uint256 nextAllowedBlock);
    error ZeroAddress();
    error ZeroSlashAmount();

    constructor(
        address admin,
        address _registry,
        address _taskManager,
        address _slashingVault
    ) {
        if (admin == address(0) || _slashingVault == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SLASHER_ROLE,       admin);

        registry      = OperatorRegistry(_registry);
        taskManager   = AxiomTaskManager(_taskManager);
        slashingVault = _slashingVault;
    }

    // ── Operator lifecycle ─────────────────────────────────────

    /// @notice Register an operator with the AXIOM AVS.
    ///         Called by operators after EigenLayer opt-in.
    /// @param operator   Operator's EOA address.
    /// @param stake      AXM stake amount (must meet minStake).
    function registerOperatorToAVS(
        address operator,
        uint256 stake
    ) external {
        // In production: verify EigenLayer delegation before registering
        registry.register(stake);
        emit AVSOperatorRegistered(operator, stake);
    }

    /// @notice Deregister an operator from the AVS.
    function deregisterOperatorFromAVS(address operator) external {
        require(
            msg.sender == operator || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "ServiceManager: not authorized"
        );
        registry.deregister();
        emit AVSOperatorDeregistered(operator);
    }

    // ── Slashing ───────────────────────────────────────────────

    /// @notice Slash a misbehaving operator.
    ///         Reasons: wrong proof, wrong result, missed deadline.
    function slashOperator(
        address operator,
        uint256 amount,
        string calldata reason
    ) external onlyRole(SLASHER_ROLE) {
        if (amount == 0) revert ZeroSlashAmount();

        // Enforce cooldown between slashes
        uint256 nextAllowed = lastSlashBlock[operator] + SLASH_COOLDOWN;
        if (block.number < nextAllowed) revert SlashCooldownActive(operator, nextAllowed);

        registry.slash(operator, amount, reason);
        lastSlashBlock[operator] = block.number;
        totalSlashed += amount;

        emit OperatorSlashed(operator, amount, reason);
    }

    // ── Views ──────────────────────────────────────────────────

    /// @notice EigenLayer interface: return restakeable strategy list.
    function getRestakeableStrategies() external pure returns (address[] memory strategies) {
        strategies = new address[](0);
        // Populate with EigenLayer strategy contracts on mainnet
    }

    /// @notice EigenLayer interface: return operator-specific strategies.
    function getOperatorRestakedStrategies(address) external pure returns (address[] memory strategies) {
        strategies = new address[](0);
    }

    function isOperatorRegistered(address op) external view returns (bool) {
        return registry.isRegistered(op);
    }

    function activeOperatorCount() external view returns (uint256) {
        return registry.activeOperators().length;
    }

    // ── Admin ──────────────────────────────────────────────────

    function setSlashingVault(address vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vault == address(0)) revert ZeroAddress();
        slashingVault = vault;
        emit SlashingVaultUpdated(vault);
    }
}
