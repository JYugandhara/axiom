// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AXMOApp
/// @notice LayerZero v2 OApp enabling $AXM to bridge between:
///         Ethereum mainnet ↔ Arbitrum One ↔ AXIOM L3 game chain.
///         Uses lock-on-source / mint-on-destination model.

interface ILayerZeroEndpointV2 {
    function send(
        uint32 dstEid,
        bytes calldata message,
        bytes calldata options
    ) external payable;

    function quote(
        uint32 dstEid,
        bytes calldata message,
        bytes calldata options,
        bool payInLzToken
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee);
}

interface IAXMBridgeable {
    function mint(address to, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract AXMOApp {
    // ── LayerZero endpoint IDs ─────────────────────────────────
    uint32 public constant MAINNET_EID  = 30101;
    uint32 public constant ARBITRUM_EID = 30110;
    uint32 public constant L3_EID       = 40999; // AXIOM L3 custom EID

    // ── LZ gas options (60,000 gas on destination) ─────────────
    bytes private constant LZ_OPTIONS =
        hex"0003010011010000000000000000000000000000ea60";

    ILayerZeroEndpointV2 public immutable endpoint;
    IAXMBridgeable       public immutable axm;
    address              public           owner;

    mapping(uint32 => address) public peers;          // dstEid → peer OApp
    mapping(uint32 => bool)    public approvedEid;    // whitelisted chains

    // ── Events ─────────────────────────────────────────────────
    event TokensSent(
        address indexed from,
        uint32          dstEid,
        address indexed to,
        uint256         amount,
        uint256         nativeFee
    );
    event TokensReceived(uint32 indexed srcEid, address indexed to, uint256 amount);
    event PeerSet(uint32 indexed eid, address peer);
    event ChainApproved(uint32 indexed eid, bool approved);

    // ── Errors ─────────────────────────────────────────────────
    error NotApprovedChain(uint32 eid);
    error InsufficientFee(uint256 required, uint256 provided);
    error ZeroAmount();
    error ZeroAddress();
    error NotEndpoint();
    error NotOwner();
    error NoPeer(uint32 eid);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _endpoint, address _axm) {
        if (_endpoint == address(0) || _axm == address(0)) revert ZeroAddress();
        endpoint = ILayerZeroEndpointV2(_endpoint);
        axm      = IAXMBridgeable(_axm);
        owner    = msg.sender;

        // Approve all three chains by default
        approvedEid[MAINNET_EID]  = true;
        approvedEid[ARBITRUM_EID] = true;
        approvedEid[L3_EID]       = true;
    }

    // ── Send ───────────────────────────────────────────────────

    /// @notice Bridge $AXM to another chain.
    /// @param dstEid   LayerZero destination endpoint ID.
    /// @param to       Recipient address on destination chain.
    /// @param amount   Amount of $AXM to bridge (18 decimals).
    function send(
        uint32 dstEid,
        address to,
        uint256 amount
    ) external payable {
        if (amount == 0)            revert ZeroAmount();
        if (to == address(0))       revert ZeroAddress();
        if (!approvedEid[dstEid])   revert NotApprovedChain(dstEid);
        if (peers[dstEid] == address(0)) revert NoPeer(dstEid);

        // Quote fee
        bytes memory message = abi.encode(to, amount);
        (uint256 fee,) = endpoint.quote(dstEid, message, LZ_OPTIONS, false);
        if (msg.value < fee) revert InsufficientFee(fee, msg.value);

        // Lock on source
        axm.transferFrom(msg.sender, address(this), amount);

        // Send cross-chain message
        endpoint.send{value: msg.value}(dstEid, message, LZ_OPTIONS);

        emit TokensSent(msg.sender, dstEid, to, amount, msg.value);
    }

    // ── Receive ────────────────────────────────────────────────

    /// @notice Called by LayerZero Executor when message arrives.
    function lzReceive(
        uint32       srcEid,
        bytes32      /*guid*/,
        bytes calldata message,
        address      /*executor*/,
        bytes calldata /*extraData*/
    ) external {
        if (msg.sender != address(endpoint)) revert NotEndpoint();

        (address to, uint256 amount) = abi.decode(message, (address, uint256));

        // Mint on destination (bridge contract must have MINTER_ROLE)
        axm.mint(to, amount);

        emit TokensReceived(srcEid, to, amount);
    }

    // ── Quote ──────────────────────────────────────────────────

    /// @notice Get the native fee required to bridge.
    function quoteSend(
        uint32 dstEid,
        address to,
        uint256 amount
    ) external view returns (uint256 nativeFee) {
        bytes memory message = abi.encode(to, amount);
        (nativeFee,) = endpoint.quote(dstEid, message, LZ_OPTIONS, false);
    }

    // ── Admin ──────────────────────────────────────────────────

    function setPeer(uint32 eid, address peer) external onlyOwner {
        peers[eid] = peer;
        emit PeerSet(eid, peer);
    }

    function setApprovedEid(uint32 eid, bool approved) external onlyOwner {
        approvedEid[eid] = approved;
        emit ChainApproved(eid, approved);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    /// @notice Rescue stuck ETH (only owner).
    function rescueETH() external onlyOwner {
        (bool ok,) = owner.call{value: address(this).balance}("");
        require(ok, "AXMOApp: ETH rescue failed");
    }

    receive() external payable {}
}
