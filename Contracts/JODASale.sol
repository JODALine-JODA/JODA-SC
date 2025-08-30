// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title JODASale
 * @notice Direct sale of JODA for BNB with min/max buy, anti-whale cap, and pause controls.
 */
contract JODASale is Ownable {
    IERC20 public immutable token;
    address payable public treasury;

    uint256 public tokensPerBNB;      // JODA per 1 BNB (token wei per BNB wei)
    uint256 public minBuyWei;         // Minimum per transaction in wei (set by owner)
    uint256 public perTxMaxWei;       // Optional max per transaction in wei

    bool public saleActive = true;

    // Anti-whale limiter
    uint256 public perUserCapWei = 1 ether; 
    uint256 public windowSeconds = 30 days;

    struct Window {
        uint256 start;
        uint256 spentWei;
    }
    mapping(address => Window) public windows;

    // Events
    event Bought(address indexed buyer, uint256 bnbIn, uint256 tokensOut);
    event TokensPerBNBUpdated(uint256 newRate);
    event TreasuryUpdated(address newTreasury);
    event CapUpdated(uint256 capWei, uint256 windowSecs);
    event MinBuyUpdated(uint256 minWei);
    event PerTxMaxUpdated(uint256 maxWei);
    event SaleActiveSet(bool active);

    constructor(
        address token_,
        address payable treasury_,
        uint256 tokensPerBNB_
    ) Ownable(msg.sender) {
        require(token_ != address(0) && treasury_ != address(0), "zero addr");
        require(tokensPerBNB_ > 0, "rate=0");
        token = IERC20(token_);
        treasury = treasury_;
        tokensPerBNB = tokensPerBNB_;
        minBuyWei = 75000000000000000; // default ~0.075 BNB (≈ $30 at $400/BNB)
    }

    // -------- Views --------
    function availableTokens() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function previewTokensForWei(uint256 bnbWei) external view returns (uint256) {
        return bnbWei * tokensPerBNB;
    }

    // -------- Owner controls --------
    function setTokensPerBNB(uint256 newRate) external onlyOwner {
        require(newRate > 0, "rate=0");
        tokensPerBNB = newRate;
        emit TokensPerBNBUpdated(newRate);
    }

    function setTreasury(address payable newTreasury) external onlyOwner {
        require(newTreasury != address(0), "zero addr");
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function setCap(uint256 capWei, uint256 windowSecs) external onlyOwner {
        require(capWei > 0 && windowSecs > 0, "invalid");
        perUserCapWei = capWei;
        windowSeconds = windowSecs;
        emit CapUpdated(capWei, windowSecs);
    }

    function setMinBuyWei(uint256 newMin) external onlyOwner {
        minBuyWei = newMin;
        emit MinBuyUpdated(newMin);
    }

    function setPerTxMaxWei(uint256 newMax) external onlyOwner {
        perTxMaxWei = newMax;
        emit PerTxMaxUpdated(newMax);
    }

    function setSaleActive(bool active) external onlyOwner {
        saleActive = active;
        emit SaleActiveSet(active);
    }

    // -------- Buying --------
    receive() external payable { buy(); }

    function buy() public payable {
        require(saleActive, "sale inactive");
        require(msg.value > 0, "no bnb sent");

        // enforce min/max
        require(msg.value >= minBuyWei, "below minimum buy");
        if (perTxMaxWei > 0) {
            require(msg.value <= perTxMaxWei, "over per-tx max");
        }

        // rolling per-user cap
        Window storage w = windows[msg.sender];
        if (block.timestamp > w.start + windowSeconds) {
            w.start = block.timestamp;
            w.spentWei = 0;
        }
        require(w.spentWei + msg.value <= perUserCapWei, "over per-user cap");
        w.spentWei += msg.value;

        // compute tokens
        uint256 tokensOut = msg.value * tokensPerBNB;
        require(token.transfer(msg.sender, tokensOut), "token transfer failed");

        // forward BNB
        (bool ok, ) = treasury.call{value: msg.value}("");
        require(ok, "treasury transfer failed");

        emit Bought(msg.sender, msg.value, tokensOut);
    }
}
