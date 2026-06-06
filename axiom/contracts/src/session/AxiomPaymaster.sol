// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SessionKeyValidator.sol";

interface IEntryPoint {
    struct UserOperation {
        address sender;
        uint256 nonce;
        bytes   initCode;
        bytes   callData;
        uint256 callGasLimit;
        uint256 verificationGasLimit;
        uint256 preVerificationGas;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        bytes   paymasterAndData;
        bytes   signature;
    }
    function getUserOpHash(UserOperation calldata userOp) external view returns (bytes32);
    function depositTo(address account) external payable;
    function balanceOf(address account) external view returns (uint256);
}

interface IAXMToken {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @title AxiomPaymaster
/// @notice ERC-4337 paymaster that accepts $AXM as gas payment.
///         Players approve this contract to spend their $AXM,
///         then all game transactions are gasless (paymaster covers ETH gas).
contract AxiomPaymaster {

    IEntryPoint          public immutable entryPoint;
    IAXMToken            public immutable axm;
    SessionKeyValidator  public immutable validator;
    address              public           treasury;
    address              public           owner;

    /// $AXM per 1 gas unit (18 decimals)
    /// e.g. 0.001 AXM per gas = 1e15
    uint256 public axmPerGasUnit = 1e15;

    uint256 public constant VALIDATION_SUCCEEDED = 0;
    uint256 public constant VALIDATION_FAILED    = 1;

    // ── Events ─────────────────────────────────────────────────
    event GasPaid(
        address indexed sender,
        uint256         axmCharged,
        uint256         gasUsed
    );
    event RateUpdated(uint256 newRate);
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);

    // ── Errors ─────────────────────────────────────────────────
    error NotEntryPoint();
    error NotOwner();
    error ZeroAddress();
    error InsufficientAXMAllowance(address sender, uint256 required, uint256 allowed);

    modifier onlyEntryPoint() {
        if (msg.sender != address(entryPoint)) revert NotEntryPoint();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        address _entryPoint,
        address _axm,
        address _treasury,
        address _validator
    ) {
        if (_entryPoint == address(0) || _axm == address(0)) revert ZeroAddress();
        entryPoint = IEntryPoint(_entryPoint);
        axm        = IAXMToken(_axm);
        treasury   = _treasury;
        validator  = SessionKeyValidator(_validator);
        owner      = msg.sender;
    }

    // ── ERC-4337 Paymaster interface ───────────────────────────

    /// @notice Called by EntryPoint to validate the paymaster will pay.
    ///         Checks the sender has approved enough $AXM.
    function validatePaymasterUserOp(
        IEntryPoint.UserOperation calldata userOp,
        bytes32 /*userOpHash*/,
        uint256 maxCost
    ) external onlyEntryPoint returns (bytes memory context, uint256 validationData) {
        address sender  = userOp.sender;
        uint256 axmCost = _estimateAxmCost(maxCost);

        uint256 allowed = axm.allowance(sender, address(this));
        if (allowed < axmCost) {
            revert InsufficientAXMAllowance(sender, axmCost, allowed);
        }

        // Precharge the estimated cost
        axm.transferFrom(sender, treasury, axmCost);

        context        = abi.encode(sender, axmCost, maxCost);
        validationData = VALIDATION_SUCCEEDED;
    }

    /// @notice Called after the operation to settle actual gas cost.
    function postOp(
        uint8          /*mode*/,
        bytes calldata context,
        uint256        actualGasCost
    ) external onlyEntryPoint {
        (address sender, uint256 preCharged, uint256 maxCost) =
            abi.decode(context, (address, uint256, uint256));

        uint256 actualAxmCost = _estimateAxmCost(actualGasCost);

        // Refund overcharge
        if (preCharged > actualAxmCost) {
            uint256 refund = preCharged - actualAxmCost;
            axm.transfer(sender, refund);
        }

        emit GasPaid(sender, actualAxmCost, actualGasCost);
    }

    // ── Internal ───────────────────────────────────────────────

    function _estimateAxmCost(uint256 gasCost) internal view returns (uint256) {
        return (gasCost * axmPerGasUnit) / 1e18;
    }

    // ── Admin ──────────────────────────────────────────────────

    /// @notice Deposit ETH into EntryPoint to cover gas for users.
    function deposit() external payable onlyOwner {
        entryPoint.depositTo{value: msg.value}(address(this));
        emit Deposited(msg.value);
    }

    /// @notice Check how much ETH is deposited in EntryPoint.
    function getDeposit() external view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /// @notice Update $AXM per gas unit rate.
    function setAxmPerGasUnit(uint256 newRate) external onlyOwner {
        axmPerGasUnit = newRate;
        emit RateUpdated(newRate);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        treasury = newTreasury;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    receive() external payable {}
}
