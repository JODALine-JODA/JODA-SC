// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title JODAStaking
 * @notice Users approve & stake JODA into this contract.
 *         On withdrawal after the chosen term, they receive principal + reward.
 *         Rewards are paid from this contract's JODA balance (owner must fund).
 */
contract JODAStaking is Ownable {
    IERC20 public immutable token;

    struct Stake {
        uint256 amount;       // staked principal (token wei)
        uint256 startTime;    // unix time
        uint32  durationDays; // term in days
        bool    claimed;      // withdrawn?
    }

    // user => list of stakes
    mapping(address => Stake[]) public stakes;

    // allowed terms (months) -> true
    mapping(uint32 => bool) public isValidTerm;

    // reward rates in basis points per allowed term (months)
    // e.g. 2000 bps = 20%
    mapping(uint32 => uint32) public rateBpsByMonths;

    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint32 months, uint256 startTime);
    event Withdrawn(address indexed user, uint256 indexed stakeId, uint256 principal, uint256 reward);
    event TermSet(uint32 months, bool enabled, uint32 bps);
    event OwnerFunded(uint256 amount);
    event OwnerSwept(uint256 amount);

    constructor(address token_) Ownable(msg.sender) {
        require(token_ != address(0), "token=0");
        token = IERC20(token_);

        // defaults (you can change later via setTerm)
        _setTerm(6,  true,  300);  // 3%
        _setTerm(12, true,  600);  // 6%
        _setTerm(24, true, 1200);  // 12%
        _setTerm(36, true, 1600);  // 16%
        _setTerm(48, true, 1800);  // 18%
        _setTerm(60, true, 2000);  // 20% (max)
    }

    // --- owner config ---
    function setTerm(uint32 months_, bool enabled, uint32 bps) external onlyOwner {
        _setTerm(months_, enabled, bps);
    }

    function _setTerm(uint32 months_, bool enabled, uint32 bps) internal {
        require(months_ > 0, "months=0");
        if (enabled) require(bps <= 2000, "bps>2000"); // cap 20%
        isValidTerm[months_] = enabled;
        rateBpsByMonths[months_] = bps;
        emit TermSet(months_, enabled, bps);
    }

    // --- staking ---
    function stake(uint256 amount, uint32 months_) external {
        require(amount > 0, "amount=0");
        require(isValidTerm[months_], "invalid term");

        // pull tokens from user
        require(token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        uint256 id = stakes[msg.sender].length;
        stakes[msg.sender].push(Stake({
            amount: amount,
            startTime: block.timestamp,
            durationDays: months_ * 30, // simple 30-day months
            claimed: false
        }));

        emit Staked(msg.sender, id, amount, months_, block.timestamp);
    }

    function stakeCount(address user) external view returns (uint256) {
        return stakes[user].length;
    }

    function previewReward(uint256 amount, uint32 months_) public view returns (uint256) {
        require(isValidTerm[months_], "invalid term");
        uint256 bps = rateBpsByMonths[months_];
        return amount * bps / 10_000;
    }

    function canWithdraw(address user, uint256 stakeId) public view returns (bool) {
        Stake memory s = stakes[user][stakeId];
        return !s.claimed && block.timestamp >= s.startTime + uint256(s.durationDays) * 1 days;
    }

    function withdraw(uint256 stakeId) external {
        Stake storage s = stakes[msg.sender][stakeId];
        require(!s.claimed, "already claimed");
        require(block.timestamp >= s.startTime + uint256(s.durationDays) * 1 days, "too early");

        s.claimed = true;
        uint32 months_ = s.durationDays / 30;
        uint256 reward = previewReward(s.amount, months_);

        // ensure contract has enough tokens to pay principal + reward
        require(token.balanceOf(address(this)) >= s.amount + reward, "insufficient pool");

        require(token.transfer(msg.sender, s.amount + reward), "transfer failed");
        emit Withdrawn(msg.sender, stakeId, s.amount, reward);
    }

    // --- owner funding / sweeping ---
    function ownerFund(uint256 amount) external onlyOwner {
        require(token.transferFrom(msg.sender, address(this), amount), "fund transferFrom failed");
        emit OwnerFunded(amount);
    }

    function ownerSweep(uint256 amount) external onlyOwner {
        require(token.transfer(msg.sender, amount), "sweep transfer failed");
        emit OwnerSwept(amount);
    }
}
