// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// ─────────────────────────────────────────────────────────────
//  AXMToken — Governance token (mainnet, capped supply)
// ─────────────────────────────────────────────────────────────

contract AXMToken is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1 billion AXM

    error ExceedsMaxSupply(uint256 requested, uint256 available);

    constructor(address dao) ERC20("AXIOM Token", "AXM") {
        _grantRole(DEFAULT_ADMIN_ROLE, dao);
        _grantRole(MINTER_ROLE, dao);
        // Initial allocation: 10% to treasury, locked by Vesting
        _mint(dao, MAX_SUPPLY / 10);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > MAX_SUPPLY)
            revert ExceedsMaxSupply(amount, MAX_SUPPLY - totalSupply());
        _mint(to, amount);
    }
}

// ─────────────────────────────────────────────────────────────
//  EnergyToken — Uncapped in-game resource (L3 only)
// ─────────────────────────────────────────────────────────────

contract EnergyToken is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE  = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE  = keccak256("BURNER_ROLE");

    constructor(address world) ERC20("AXIOM Energy", "ENERGY") {
        _grantRole(DEFAULT_ADMIN_ROLE, world);
        _grantRole(MINTER_ROLE, world);
        _grantRole(BURNER_ROLE, world);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyRole(BURNER_ROLE) {
        _burn(account, amount);
    }
}

// ─────────────────────────────────────────────────────────────
//  WorldTreasury — DAO-controlled vault
// ─────────────────────────────────────────────────────────────

contract WorldTreasury is ReentrancyGuard, AccessControl {
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");

    event Received(address indexed token, address indexed from, uint256 amount);
    event Spent(address indexed token, address indexed to, uint256 amount);

    constructor(address dao) {
        _grantRole(DEFAULT_ADMIN_ROLE, dao);
        _grantRole(SPENDER_ROLE, dao);
    }

    receive() external payable {}

    function spend(address token, address to, uint256 amount) external onlyRole(SPENDER_ROLE) nonReentrant {
        IERC20(token).transfer(to, amount);
        emit Spent(token, to, amount);
    }

    function balance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// ─────────────────────────────────────────────────────────────
//  Staking — Lock $AXM to earn $ENERGY multiplier boosts
// ─────────────────────────────────────────────────────────────

contract Staking is ReentrancyGuard {
    IERC20 public immutable axm;
    IERC20 public immutable energy;
    address public immutable treasury;

    uint256 public constant LOCK_PERIOD_MIN = 7 days;
    uint256 public constant LOCK_PERIOD_MAX = 365 days;
    uint256 public constant BASE_APY_BPS    = 1000; // 10% base APY
    uint256 public constant MAX_BOOST_BPS   = 4000; // up to 40% APY for max lock

    struct Position {
        uint256 amount;
        uint256 lockedAt;
        uint256 unlockAt;
        uint256 multiplierBps; // APY in basis points
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

    constructor(address _axm, address _energy, address _treasury) {
        axm      = IERC20(_axm);
        energy   = IERC20(_energy);
        treasury = _treasury;
    }

    function stake(uint256 amount, uint256 lockDuration) external nonReentrant returns (uint256 posId) {
        if (lockDuration < LOCK_PERIOD_MIN) revert LockTooShort();
        if (lockDuration > LOCK_PERIOD_MAX) revert LockTooLong();

        axm.transferFrom(msg.sender, address(this), amount);

        // Linear boost: more lock time = higher APY
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

    function unstake(uint256 posId) external nonReentrant {
        Position storage pos = positions[msg.sender][posId];
        if (block.timestamp < pos.unlockAt) revert StillLocked(pos.unlockAt);
        _claimReward(msg.sender, posId);
        uint256 amount = pos.amount;
        pos.amount = 0;
        axm.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, posId, amount);
    }

    function claim(uint256 posId) external nonReentrant {
        _claimReward(msg.sender, posId);
    }

    function _claimReward(address user, uint256 posId) internal {
        Position storage pos = positions[user][posId];
        if (pos.amount == 0) revert NothingToClaim();

        uint256 elapsed  = block.timestamp - pos.lastClaimed;
        uint256 reward   = pos.amount * pos.multiplierBps * elapsed / (10000 * 365 days);
        pos.lastClaimed  = block.timestamp;

        if (reward > 0) {
            // WorldTreasury funds the $ENERGY rewards
            IEnergyMinter(address(energy)).mint(user, reward);
            emit Claimed(user, posId, reward);
        }
    }

    function pendingReward(address user, uint256 posId) external view returns (uint256) {
        Position memory pos = positions[user][posId];
        if (pos.amount == 0) return 0;
        uint256 elapsed = block.timestamp - pos.lastClaimed;
        return pos.amount * pos.multiplierBps * elapsed / (10000 * 365 days);
    }
}

interface IEnergyMinter {
    function mint(address to, uint256 amount) external;
}

// ─────────────────────────────────────────────────────────────
//  Marketplace — NFT buy/sell with ERC-2981 royalties
// ─────────────────────────────────────────────────────────────

contract Marketplace is ReentrancyGuard {
    IERC20  public immutable axm;
    address public immutable treasury;
    uint256 public constant  FEE_BPS = 250; // 2.5% protocol fee

    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;      // in $AXM
        bool    active;
    }

    uint256 public listingCount;
    mapping(uint256 => Listing) public listings;

    event Listed(uint256 indexed listingId, address indexed seller, address nft, uint256 tokenId, uint256 price);
    event Sold(uint256 indexed listingId, address indexed buyer, uint256 price);
    event Cancelled(uint256 indexed listingId);

    error NotSeller();
    error NotActive();
    error InvalidPrice();

    constructor(address _axm, address _treasury) {
        axm      = IERC20(_axm);
        treasury = _treasury;
    }

    function list(address nftContract, uint256 tokenId, uint256 price) external returns (uint256 listingId) {
        if (price == 0) revert InvalidPrice();
        INFT(nftContract).transferFrom(msg.sender, address(this), tokenId);
        listingId = ++listingCount;
        listings[listingId] = Listing(msg.sender, nftContract, tokenId, price, true);
        emit Listed(listingId, msg.sender, nftContract, tokenId, price);
    }

    function buy(uint256 listingId) external nonReentrant {
        Listing storage l = listings[listingId];
        if (!l.active) revert NotActive();
        l.active = false;

        uint256 fee     = l.price * FEE_BPS / 10000;
        uint256 payout  = l.price - fee;

        axm.transferFrom(msg.sender, treasury, fee);
        axm.transferFrom(msg.sender, l.seller, payout);
        INFT(l.nftContract).transferFrom(address(this), msg.sender, l.tokenId);
        emit Sold(listingId, msg.sender, l.price);
    }

    function cancel(uint256 listingId) external nonReentrant {
        Listing storage l = listings[listingId];
        if (l.seller != msg.sender) revert NotSeller();
        if (!l.active) revert NotActive();
        l.active = false;
        INFT(l.nftContract).transferFrom(address(this), msg.sender, l.tokenId);
        emit Cancelled(listingId);
    }
}

interface INFT {
    function transferFrom(address from, address to, uint256 tokenId) external;
}
