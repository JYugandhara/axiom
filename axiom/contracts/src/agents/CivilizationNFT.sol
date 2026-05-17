// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IERC6551Registry {
    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address);

    function account(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external view returns (address);
}

interface IAXMToken {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title CivilizationNFT
/// @notice ERC-721 NFT representing a player's civilization.
///         Each token gets an ERC-6551 Token Bound Account (TBA)
///         that can autonomously execute strategy calls on-chain.
contract CivilizationNFT is ERC721Enumerable, AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant MINTER_ROLE  = keccak256("MINTER_ROLE");
    bytes32 public constant SYSTEM_ROLE  = keccak256("SYSTEM_ROLE");

    // ── ERC-6551 ───────────────────────────────────────────────
    IERC6551Registry public immutable erc6551Registry;
    address          public immutable agentAccountImpl;

    // ── Token state ────────────────────────────────────────────
    Counters.Counter private _tokenIds;

    struct CivMetadata {
        string  name;
        bytes32 agentModelHash; // EZKL model hash (0 = no AI)
        bool    isAutonomous;
        uint256 mintedAtBlock;
    }
    mapping(uint256 => CivMetadata) public metadata;

    // ── Economy ────────────────────────────────────────────────
    IAXMToken public immutable axmToken;
    uint256   public mintFee; // in $AXM (18 decimals)
    address   public treasury;

    // ── Events ─────────────────────────────────────────────────
    event CivilizationMinted(uint256 indexed tokenId, address indexed owner, address tba);
    event AgentModelSet(uint256 indexed tokenId, bytes32 modelHash);
    event AutonomyToggled(uint256 indexed tokenId, bool autonomous);

    // ── Errors ─────────────────────────────────────────────────
    error NameTooLong();
    error InsufficientFee();

    constructor(
        address _registry,
        address _agentImpl,
        address _axm,
        address _treasury,
        uint256 _mintFee
    ) ERC721("AXIOM Civilization", "CIV") {
        erc6551Registry  = IERC6551Registry(_registry);
        agentAccountImpl = _agentImpl;
        axmToken         = IAXMToken(_axm);
        treasury         = _treasury;
        mintFee          = _mintFee;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /// @notice Mint a new civilization. Player pays $AXM mint fee.
    function mint(string calldata civName) external returns (uint256 tokenId) {
        if (bytes(civName).length > 32) revert NameTooLong();

        // Collect mint fee
        if (mintFee > 0) {
            bool ok = axmToken.transferFrom(msg.sender, treasury, mintFee);
            if (!ok) revert InsufficientFee();
        }

        _tokenIds.increment();
        tokenId = _tokenIds.current();
        _safeMint(msg.sender, tokenId);

        metadata[tokenId] = CivMetadata(civName, bytes32(0), false, block.number);

        // Deploy ERC-6551 Token Bound Account for this NFT
        address tba = erc6551Registry.createAccount(
            agentAccountImpl,
            bytes32(tokenId), // salt
            block.chainid,
            address(this),
            tokenId
        );

        emit CivilizationMinted(tokenId, msg.sender, tba);
    }

    /// @notice Update the AI strategy model for autonomous gameplay.
    function setAgentModel(uint256 tokenId, bytes32 modelHash) external {
        require(ownerOf(tokenId) == msg.sender, "CivilizationNFT: not owner");
        metadata[tokenId].agentModelHash = modelHash;
        emit AgentModelSet(tokenId, modelHash);
    }

    /// @notice Toggle autonomous mode — civ acts without player input.
    function setAutonomous(uint256 tokenId, bool autonomous) external {
        require(ownerOf(tokenId) == msg.sender, "CivilizationNFT: not owner");
        metadata[tokenId].isAutonomous = autonomous;
        emit AutonomyToggled(tokenId, autonomous);
    }

    /// @notice Get the ERC-6551 TBA address for a token.
    function agentAccountOf(uint256 tokenId) external view returns (address) {
        return erc6551Registry.account(
            agentAccountImpl,
            bytes32(tokenId),
            block.chainid,
            address(this),
            tokenId
        );
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721Enumerable, AccessControl) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

// ─────────────────────────────────────────────────────────────
//  AgentAccount — ERC-6551 Token Bound Account
//  The "autonomous brain" — executes strategy calls on-chain
// ─────────────────────────────────────────────────────────────

/// @title AgentAccount
/// @notice ERC-6551 Token Bound Account implementation.
///         Owned by the CivilizationNFT, controlled by its owner
///         or autonomously by the AXIOM AVS when isAutonomous=true.
contract AgentAccount {
    // ── ERC-6551 state ─────────────────────────────────────────
    uint256 private _nonce;

    receive() external payable {}

    /// @notice Execute a call on behalf of this agent account.
    ///         Only callable by the NFT owner or the authorized game systems.
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external payable returns (bytes memory result)
    {
        require(_isValidSigner(msg.sender), "AgentAccount: not authorized");
        require(operation == 0, "AgentAccount: only call supported");
        _nonce++;
        bool success;
        (success, result) = to.call{value: value}(data);
        require(success, "AgentAccount: call failed");
    }

    /// @notice ERC-6551 token info for this account.
    function token() external view returns (uint256 chainId, address tokenContract, uint256 tokenId) {
        bytes memory footer = new bytes(0x60);
        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }
        return abi.decode(footer, (uint256, address, uint256));
    }

    function owner() public view returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) =
            abi.decode(_tokenInfo(), (uint256, address, uint256));
        if (chainId != block.chainid) return address(0);
        return IERC721(tokenContract).ownerOf(tokenId);
    }

    function nonce() external view returns (uint256) { return _nonce; }

    function _isValidSigner(address signer) internal view returns (bool) {
        return signer == owner();
    }

    function _tokenInfo() internal view returns (bytes memory) {
        bytes memory footer = new bytes(0x60);
        assembly { extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60) }
        return footer;
    }
}

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
}
