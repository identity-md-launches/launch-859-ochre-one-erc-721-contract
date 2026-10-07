// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Unrestricted rehearsal currency. It has no scarcity or production monetary value.
contract MockCoin is ERC20 {
    constructor(address admin) ERC20("Pigment", "PGMT") {
        _mint(admin, 1_000_000_000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
