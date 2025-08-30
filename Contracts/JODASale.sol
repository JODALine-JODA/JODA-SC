// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title JODASale
 * @notice Direct sale of JODA for BNB with min/tx limits, rolling per-user cap, and pause control.
 * - tokensPerBNB: JODA per 1 BNB, in token-wei (18 decimals)
 * - minBuyWei: minimum BNB per transaction (owner-settable; defaults to ~0.075 BNB ≈ $30 if BNB≈$400)
 * - perTxMaxWei: optional max BNB per transaction (0 disables)
 * - perUserCapWei + windowSeconds: anti-whale rolling limit per wallet
 * - saleActive: master switch
 * - Contract must hold enough JODA to fulfill buys (fund by transferring JODA to this contract)
 */
contract JODASale is Ownable {
    IERC20 public immutable token;
    address payable public treasury;

    // Pricing & limits
    uint256 public tokensPerBNB;   // JODA per 1 BNB, in token-wei
    uint256 public minBuyWei;      // minimum per tx (wei)
    uint256 public perTxMaxWei;    // optional max per tx (wei), 0 = disabled

    // Pause
    bool public saleActive = true;

    // Rolling per-user cap
    uint256 public perUserCapWei = 1 ether; // default 1 BNB/month (change via setCap)
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

        // Default ~$30 minimum if BNB ≈ $400: 0.075 BNB = 0.075 * 1e18 wei
        // You can change this anytime with setMinBuyWei(...)
        minBuyWei = 75_000_000_000_000_000; // 0.075 BNB in wei
    }

    // -------- Views --------
    function availableTokens() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice Helper for UI: how many JODA would buyer receive for bnbWei?
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
        minBuyWei = newMin; // set 0 to disable the minimum
        emit MinBuyUpdated(newMin);
    }

    function setPerTxMaxWei(uint256 newMax) external onlyOwner {
        perTxMaxWei = newMax; // set 0 to disable per-tx ceiling
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

        // min / per-tx max
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

        // compute & deliver tokens
        uint256 tokensOut = msg.value * tokensPerBNB;
        require(token.transfer(msg.sender, tokensOut), "token transfer failed");

        // forward BNB to treasury
        (bool ok, ) = treasury.call{value: msg.value}("");
        require(ok, "treasury transfer failed");

        emit Bought(msg.sender, msg.value, tokensOut);
    }
}
