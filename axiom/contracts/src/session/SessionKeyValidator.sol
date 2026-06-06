// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SessionKeyValidator
/// @notice ERC-4337 session key management for gasless AXIOM gameplay.
///         Players sign a session key once (24h) — all game moves
///         are then signed by the ephemeral key and bundled by a paymaster.
///         The session key is scoped to specific game contracts only.
contract SessionKeyValidator {

    uint256 public constant MAX_SESSION_DURATION = 24 hours;
    uint256 public constant MIN_SESSION_DURATION = 5 minutes;

    struct SessionKey {
        address  key;                   // Ephemeral signer address
        uint256  validUntil;            // Unix timestamp
        bytes32  allowedContractsMask;  // Bitmask of allowed contract indices (up to 256)
        bool     active;
    }

    // wallet → active session
    mapping(address => SessionKey)    public sessionKeys;
    // registered game contracts → index in bitmask
    mapping(address => uint8)         public contractIndex;
    // index → contract address (for reverse lookup)
    mapping(uint8 => address)         public indexedContracts;
    uint8                             public contractCount;

    address public owner;

    // ── Events ─────────────────────────────────────────────────
    event SessionCreated(
        address indexed wallet,
        address indexed key,
        uint256 validUntil
    );
    event SessionRevoked(address indexed wallet);
    event ContractRegistered(address indexed contractAddr, uint8 index);

    // ── Errors ─────────────────────────────────────────────────
    error DurationTooShort();
    error DurationTooLong();
    error SessionExpired(address wallet);
    error InvalidSessionKey(address wallet, address key);
    error ContractNotAllowed(address target);
    error NotOwner();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _owner, address[] memory gameContracts) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
        for (uint256 i = 0; i < gameContracts.length; i++) {
            _registerContract(gameContracts[i]);
        }
    }

    // ── Session management ─────────────────────────────────────

    /// @notice Create a session key allowing gasless gameplay.
    /// @param key              Ephemeral key address (generated client-side).
    /// @param duration         How long the session lasts (seconds).
    /// @param allowedContracts Array of game contract addresses this key can call.
    function createSession(
        address          key,
        uint256          duration,
        address[] calldata allowedContracts
    ) external {
        if (duration < MIN_SESSION_DURATION) revert DurationTooShort();
        if (duration > MAX_SESSION_DURATION) revert DurationTooLong();
        if (key == address(0))              revert ZeroAddress();

        bytes32 mask;
        for (uint256 i = 0; i < allowedContracts.length; i++) {
            uint8 idx = contractIndex[allowedContracts[i]];
            mask |= bytes32(uint256(1) << idx);
        }

        sessionKeys[msg.sender] = SessionKey({
            key                 : key,
            validUntil          : block.timestamp + duration,
            allowedContractsMask: mask,
            active              : true
        });

        emit SessionCreated(msg.sender, key, block.timestamp + duration);
    }

    /// @notice Revoke the active session for the caller.
    function revokeSession() external {
        sessionKeys[msg.sender].active = false;
        emit SessionRevoked(msg.sender);
    }

    // ── Validation ─────────────────────────────────────────────

    /// @notice Check if a session key is valid for a specific contract call.
    /// @param wallet   The wallet that owns the session.
    /// @param key      The ephemeral key being validated.
    /// @param target   The contract being called.
    /// @return valid   True if the session key is authorized.
    function validateSessionKey(
        address wallet,
        address key,
        address target
    ) external view returns (bool valid) {
        SessionKey memory s = sessionKeys[wallet];
        if (!s.active)                    return false;
        if (s.key != key)                 return false;
        if (block.timestamp > s.validUntil) return false;

        uint8  idx  = contractIndex[target];
        bytes32 bit = bytes32(uint256(1) << idx);
        return (s.allowedContractsMask & bit) != 0;
    }

    /// @notice Get remaining session time in seconds (0 if expired).
    function sessionTimeRemaining(address wallet) external view returns (uint256) {
        SessionKey memory s = sessionKeys[wallet];
        if (!s.active || block.timestamp >= s.validUntil) return 0;
        return s.validUntil - block.timestamp;
    }

    // ── Admin ──────────────────────────────────────────────────

    /// @notice Register a game contract so it can be included in session masks.
    function registerContract(address contractAddr) external onlyOwner {
        _registerContract(contractAddr);
    }

    function _registerContract(address contractAddr) internal {
        if (contractAddr == address(0)) revert ZeroAddress();
        uint8 idx = contractCount++;
        contractIndex[contractAddr]  = idx;
        indexedContracts[idx]        = contractAddr;
        emit ContractRegistered(contractAddr, idx);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
}
