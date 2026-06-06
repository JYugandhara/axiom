// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20Market {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
interface INFTMarket {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title Marketplace
/// @notice Secondary marketplace for Civilization NFTs.
///         Charges a 2.5% protocol fee routed to WorldTreasury.
contract Marketplace is ReentrancyGuard {
    IERC20Market public immutable axm;
    address      public immutable treasury;
    uint256      public constant  FEE_BPS = 250; // 2.5%

    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;  // in $AXM
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
        axm      = IERC20Market(_axm);
        treasury = _treasury;
    }

    /// @notice List an NFT for sale. The NFT is escrowed by this contract.
    function list(address nftContract, uint256 tokenId, uint256 price)
        external returns (uint256 listingId)
    {
        if (price == 0) revert InvalidPrice();
        INFTMarket(nftContract).transferFrom(msg.sender, address(this), tokenId);

        listingId = ++listingCount;
        listings[listingId] = Listing(msg.sender, nftContract, tokenId, price, true);
        emit Listed(listingId, msg.sender, nftContract, tokenId, price);
    }

    /// @notice Buy a listed NFT. Buyer pays price in $AXM (fee → treasury).
    function buy(uint256 listingId) external nonReentrant {
        Listing storage l = listings[listingId];
        if (!l.active) revert NotActive();
        l.active = false;

        uint256 fee    = l.price * FEE_BPS / 10000;
        uint256 payout = l.price - fee;

        axm.transferFrom(msg.sender, treasury, fee);
        axm.transferFrom(msg.sender, l.seller, payout);
        INFTMarket(l.nftContract).transferFrom(address(this), msg.sender, l.tokenId);

        emit Sold(listingId, msg.sender, l.price);
    }

    /// @notice Cancel a listing and return the NFT to the seller.
    function cancel(uint256 listingId) external nonReentrant {
        Listing storage l = listings[listingId];
        if (l.seller != msg.sender) revert NotSeller();
        if (!l.active)              revert NotActive();
        l.active = false;
        INFTMarket(l.nftContract).transferFrom(address(this), msg.sender, l.tokenId);
        emit Cancelled(listingId);
    }
}
