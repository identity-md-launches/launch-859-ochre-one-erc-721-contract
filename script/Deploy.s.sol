// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MockCoin} from "../src/MockCoin.sol";
import {Ochre} from "../src/Ochre.sol";

/// @notice Local rehearsal of launch.json. No keys, environment reads, or broadcasting.
contract Deploy {
    uint256 public constant CHAIN_ID = 11_155_111;
    address public constant ADMIN = 0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479;
    uint256 public constant START_TIME = 1_791_352_835;
    bytes32 public constant SEAT_ROOT = 0x1111111111111111111111111111111111111111111111111111111111111111;

    function run() external returns (MockCoin coin, Ochre ochre) {
        require(block.chainid == CHAIN_ID, "Sepolia only");
        coin = new MockCoin(ADMIN);
        ochre = new Ochre(
            address(coin),
            ADMIN,
            ADMIN,
            SEAT_ROOT,
            START_TIME,
            bytes32("zto-cave-test5"),
            bytes32("zto-cave-test4"),
            bytes32("zto-cave-test3"),
            bytes32("zto-cave-test2"),
            bytes32("zto-cave-test5"),
            bytes32("zto-cave-test4"),
            bytes32("zto-cave-test3")
        );
    }
}
