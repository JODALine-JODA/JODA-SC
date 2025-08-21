// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title JODA (Jodaline)
 * @notice ERC20 with a hard cap and owner-only minting.
 * - Decimals: 18
 * - Cap is fixed at deployment (in token wei)
 * - Initial supply minted to a treasury address at deployment
 */
contract JODA is ERC20, ERC20Capped, Ownable {
    constructor(
        uint256 cap_,              // max total supply in wei (e.g. 200_000_000e18)
        uint256 initialSupply_,    // initial mint in wei (e.g. 40_000_000e18)
        address treasury_          // receives initial mint
    )
        ERC20("Jodaline", "JODA")
        ERC20Capped(cap_)
        Ownable(msg.sender)
    {
        require(treasury_ != address(0), "treasury=0");
        require(initialSupply_ <= cap_, "initial > cap");
        _mint(treasury_, initialSupply_);
    }

    /// @notice Owner can mint more, but never above the cap.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount); // ERC20Capped enforces cap in _mint
    }

    /// @notice Any holder can burn their tokens.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // --- required override because of multiple inheritance (ERC20 + ERC20Capped) ---
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Capped)
    {
        super._update(from, to, value);
    }
}
