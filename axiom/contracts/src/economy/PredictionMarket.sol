// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface IAXM {
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/// @title PredictionMarket
/// @notice On-chain AMM prediction market for AXIOM season outcomes.
///         Constant-product (x*y=k) pricing for YES/NO shares.
contract PredictionMarket is ReentrancyGuard, AccessControl {
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    struct Market {
        uint256 season;
        uint256 civId;
        uint256 yesPool;
        uint256 noPool;
        bool    resolved;
        bool    outcome;
        uint256 closesAtBlock;
    }
    struct Bet {
        uint256 marketId;
        bool    isYes;
        uint256 shares;
        uint256 axmIn;
        bool    claimed;
    }

    uint256 public marketCount;
    uint256 public constant FEE_BPS  = 200;    // 2% rake
    uint256 public constant SEED_AXM = 100e18; // seed liquidity per side

    mapping(uint256 => Market) public markets;
    mapping(address => Bet[])  public userBets;

    IAXM    public immutable axm;
    address public immutable treasury;

    event MarketCreated(uint256 indexed id, uint256 civId, uint256 season, uint256 closesAt);
    event BetPlaced(uint256 indexed marketId, address indexed user, bool isYes, uint256 axmIn, uint256 shares);
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event WinningsClaimed(uint256 indexed marketId, address indexed user, uint256 axmOut);

    error MarketClosed();
    error AlreadyResolved();
    error NotResolved();
    error AlreadyClaimed();
    error ZeroAmount();

    constructor(address _axm, address _treasury, address _admin) {
        axm      = IAXM(_axm);
        treasury = _treasury;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(RESOLVER_ROLE, _admin);
    }

    function createMarket(uint256 civId, uint256 season, uint256 durationBlocks)
        external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 id)
    {
        id = ++marketCount;
        markets[id] = Market(season, civId, SEED_AXM, SEED_AXM, false, false, block.number + durationBlocks);
        axm.transferFrom(treasury, address(this), SEED_AXM * 2);
        emit MarketCreated(id, civId, season, block.number + durationBlocks);
    }

    function bet(uint256 marketId, bool isYes, uint256 axmIn) external nonReentrant {
        if (axmIn == 0) revert ZeroAmount();
        Market storage m = markets[marketId];
        if (block.number >= m.closesAtBlock) revert MarketClosed();
        if (m.resolved) revert AlreadyResolved();

        uint256 fee   = axmIn * FEE_BPS / 10000;
        uint256 netIn = axmIn - fee;
        axm.transferFrom(msg.sender, treasury, fee);
        axm.transferFrom(msg.sender, address(this), netIn);

        uint256 shares;
        if (isYes) {
            shares    = netIn * m.noPool / (m.yesPool + netIn);
            m.yesPool += netIn;
        } else {
            shares    = netIn * m.yesPool / (m.noPool + netIn);
            m.noPool  += netIn;
        }
        userBets[msg.sender].push(Bet(marketId, isYes, shares, axmIn, false));
        emit BetPlaced(marketId, msg.sender, isYes, axmIn, shares);
    }

    function impliedProbabilityYes(uint256 marketId) external view returns (uint256) {
        Market memory m = markets[marketId];
        uint256 total = m.yesPool + m.noPool;
        return total == 0 ? 5000 : m.noPool * 10000 / total;
    }

    function resolve(uint256 marketId, bool outcome) external onlyRole(RESOLVER_ROLE) {
        Market storage m = markets[marketId];
        if (m.resolved) revert AlreadyResolved();
        m.resolved = true;
        m.outcome  = outcome;
        emit MarketResolved(marketId, outcome);
    }

    function claim(uint256 betIdx) external nonReentrant {
        Bet storage b = userBets[msg.sender][betIdx];
        if (b.claimed) revert AlreadyClaimed();
        Market memory m = markets[b.marketId];
        if (!m.resolved) revert NotResolved();
        b.claimed = true;
        if (b.isYes != m.outcome) return; // loser

        uint256 losingPool  = m.outcome ? m.noPool  : m.yesPool;
        uint256 winningPool = m.outcome ? m.yesPool : m.noPool;
        uint256 payout      = b.axmIn + (b.shares * losingPool / winningPool);
        axm.transfer(msg.sender, payout);
        emit WinningsClaimed(b.marketId, msg.sender, payout);
    }

    function betCount(address user) external view returns (uint256) {
        return userBets[user].length;
    }
}
