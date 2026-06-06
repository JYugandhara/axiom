// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20Staking {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}
interface IEnergyMinter {
    function mint(address to, uint256 amount) external;
}

/// @title Staking
/// @notice Lock $AXM to earn boosted $ENERGY generation.
///         Longer locks → higher APY multiplier (10% → 40%).
contract Staking is ReentrancyGuard {
    IERC20Staking public immutable axm;
    IEnergyMinter public immutable energy;
    address       public immutable treasury;

    uint256 public constant LOCK_PERIOD_MIN = 7 days;
    uint256 public constant LOCK_PERIOD_MAX = 365 days;
    uint256 public constant BASE_APY_BPS    = 1000; // 10% base
    uint256 public constant MAX_BOOST_BPS   = 3000; // +30% for max lock → 40% total

    struct Position {
        uint256 amount;
        uint256 lockedAt;
        uint256 unlockAt;
        uint256 multiplierBps;
        uint256 lastClaimed;
    }

    mapping(address => Position[]) public positions;

    event Staked(address indexed user, uint256 indexed posId, uint256 amount, uint256 unlockAt);
    event Unstaked(address indexed user, uint256 indexed posId, uint256 amount);
    event Claimed(address indexed user, uint256 indexed posId, uint256 energyReward);

    error LockTooShort();
    error LockTooLong();
    error StillLocked(uint256 unlockAt);
    error NothingToClaim();
    error InvalidPosition();

    constructor(address _axm, address _energy, address _treasury) {
        axm      = IERC20Staking(_axm);
        energy   = IEnergyMinter(_energy);
        treasury = _treasury;
    }

    /// @notice Stake $AXM for a lock duration to earn $ENERGY rewards.
    function stake(uint256 amount, uint256 lockDuration)
        external nonReentrant returns (uint256 posId)
    {
        if (lockDuration < LOCK_PERIOD_MIN) revert LockTooShort();
        if (lockDuration > LOCK_PERIOD_MAX) revert LockTooLong();

        axm.transferFrom(msg.sender, address(this), amount);

        uint256 boost = (lockDuration - LOCK_PERIOD_MIN) * MAX_BOOST_BPS
            / (LOCK_PERIOD_MAX - LOCK_PERIOD_MIN);
        uint256 multiplier = BASE_APY_BPS + boost;

        posId = positions[msg.sender].length;
        positions[msg.sender].push(Position({
            amount       : amount,
            lockedAt     : block.timestamp,
            unlockAt     : block.timestamp + lockDuration,
            multiplierBps: multiplier,
            lastClaimed  : block.timestamp
        }));

        emit Staked(msg.sender, posId, amount, block.timestamp + lockDuration);
    }

    /// @notice Claim accrued $ENERGY rewards without unstaking.
    function claim(uint256 posId) external nonReentrant {
        _claimReward(msg.sender, posId);
    }

    /// @notice Unstake after lock expires (auto-claims pending rewards).
    function unstake(uint256 posId) external nonReentrant {
        if (posId >= positions[msg.sender].length) revert InvalidPosition();
        Position storage pos = positions[msg.sender][posId];
        if (block.timestamp < pos.unlockAt) revert StillLocked(pos.unlockAt);

        _claimReward(msg.sender, posId);

        uint256 amount = pos.amount;
        pos.amount = 0;
        axm.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, posId, amount);
    }

    function pendingReward(address user, uint256 posId) external view returns (uint256) {
        if (posId >= positions[user].length) return 0;
        Position memory pos = positions[user][posId];
        if (pos.amount == 0) return 0;
        uint256 elapsed = block.timestamp - pos.lastClaimed;
        return pos.amount * pos.multiplierBps * elapsed / (10000 * 365 days);
    }

    function positionCount(address user) external view returns (uint256) {
        return positions[user].length;
    }

    function _claimReward(address user, uint256 posId) internal {
        Position storage pos = positions[user][posId];
        if (pos.amount == 0) revert NothingToClaim();

        uint256 elapsed = block.timestamp - pos.lastClaimed;
        uint256 reward  = pos.amount * pos.multiplierBps * elapsed / (10000 * 365 days);
        pos.lastClaimed = block.timestamp;

        if (reward > 0) {
            energy.mint(user, reward);
            emit Claimed(user, posId, reward);
        }
    }
}
