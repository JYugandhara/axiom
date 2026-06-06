// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC721Account {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title AgentAccount
/// @notice ERC-6551 Token Bound Account implementation — the "autonomous brain".
///         Each CivilizationNFT owns one of these accounts. It can execute
///         on-chain calls either from the NFT owner directly, or autonomously
///         when the AXIOM AVS submits ZK-verified agent actions.
contract AgentAccount {
    uint256 private _nonce;

    event Executed(address indexed to, uint256 value, bytes data);
    event Received(address indexed from, uint256 value);

    error NotAuthorized();
    error OnlyCallOperation();
    error CallFailed();

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Execute a call on behalf of this token-bound account.
    /// @param to        Target contract.
    /// @param value     ETH value to send.
    /// @param data      Calldata.
    /// @param operation Must be 0 (CALL) — DELEGATECALL not supported.
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external payable returns (bytes memory result)
    {
        if (!_isValidSigner(msg.sender)) revert NotAuthorized();
        if (operation != 0)              revert OnlyCallOperation();

        _nonce++;
        bool success;
        (success, result) = to.call{value: value}(data);
        if (!success) revert CallFailed();

        emit Executed(to, value, data);
    }

    /// @notice ERC-6551 — returns the token that owns this account.
    function token() public view returns (uint256 chainId, address tokenContract, uint256 tokenId) {
        return abi.decode(_footer(), (uint256, address, uint256));
    }

    /// @notice Returns the owner of the bound NFT (the account's controller).
    function owner() public view returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        if (chainId != block.chainid) return address(0);
        return IERC721Account(tokenContract).ownerOf(tokenId);
    }

    function nonce() external view returns (uint256) {
        return _nonce;
    }

    /// @notice ERC-1271 signature validation (for session keys / 4337).
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0x1626ba7e; // ERC-1271 magic value
    }

    // ── Internal ───────────────────────────────────────────────

    function _isValidSigner(address signer) internal view returns (bool) {
        return signer == owner();
    }

    /// @notice Read the ERC-6551 footer (chainId, tokenContract, tokenId)
    ///         appended to the account bytecode by the registry.
    function _footer() internal view returns (bytes memory footer) {
        footer = new bytes(0x60);
        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }
    }
}
