// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title JODAQuotaSale
 * @notice Direct sale of JODA for BNB at an owner-settable rate.
 *         - tokensPerBNB = JODA per 1 BNB (in token-wei, 18 decimals).
 *         - Contract must be funded with JODA (or approved to pull) to deliver.
 *         - BNB is forwarded to treasury immediately.
 */
contract JODAQuotaSale is Ownable {
    IERC20 public immutable token;
    address payable public treasury;

    // JODA per 1 BNB (token wei)
    uint256 public tokensPerBNB;

    // per-user cap in BNB-wei over a rolling window
    uint256 public perUserCapWei = 1 ether;
    uint256 public windowSeconds = 30 days;
    bool    public saleActive = true;

    struct Window { uint256 start; uint256 spentWei; }
    mapping(address => Window) public windows;

    event Bought(address indexed buyer, uint256 bnbIn, uint256 tokensOut);
    event TokensPerBNBUpdated(uint256 newRate);
    event TreasuryUpdated(address newTreasury);
    event CapUpdated(uint256 capWei, uint256 windowSecs);
    event SaleActiveSet(bool active);
    event SweptTokens(address to, uint256 amount);
    event SweptBNB(address to, uint256 amount);

    constructor(address token_, address payable treasury_, uint256 tokensPerBNB_)
        Ownable(msg.sender)
    {
        require(token_ != address(0) && treasury_ != address(0), "zero addr");
        require(tokensPerBNB_ > 0, "rate=0");
        token = IERC20(token_);
        treasury = treasury_;
        tokensPerBNB = tokensPerBNB_;
    }

    // views
    function availableTokens() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // owner controls
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

    function setSaleActive(bool active) external onlyOwner {
        saleActive = active;
        emit SaleActiveSet(active);
    }

    // buying
    receive() external payable { buy(); }

    function buy() public payable {
        require(saleActive, "sale inactive");
        require(msg.value > 0, "no bnb");

        Window storage w = windows[msg.sender];
        if (block.timestamp > w.start + windowSeconds) {
            w.start = block.timestamp;
            w.spentWei = 0;
        }
        require(w.spentWei + msg.value <= perUserCapWei, "over cap");
        w.spentWei += msg.value;

        // token-wei out = bnb-wei in * (tokens per 1 BNB)
        uint256 tokensOut = msg.value * tokensPerBNB;
        require(token.transfer(msg.sender, tokensOut), "token xfer failed");

        (bool ok, ) = treasury.call{value: msg.value}("");
        require(ok, "treasury xfer failed");

        emit Bought(msg.sender, msg.value, tokensOut);
    }

    // recover
    function sweepTokens(address to, uint256 amount) external onlyOwner {
        require(token.transfer(to, amount), "sweep tokens failed");
        emit SweptTokens(to, amount);
    }

    function sweepBNB(address payable to, uint256 amount) external onlyOwner {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "sweep bnb failed");
        emit SweptBNB(to, amount);
    }
}
