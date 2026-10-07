// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockCoin} from "../src/MockCoin.sol";
import {Ochre} from "../src/Ochre.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

abstract contract OchreFixture is Test, IERC721Receiver {
    address internal constant ADMIN = 0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479;
    address internal constant ADAM = address(0xADAD);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant START = 1_791_352_835;
    MockCoin internal coin;
    Ochre internal ochre;

    function setUp() public virtual {
        coin = new MockCoin(ADMIN);
        ochre = _deploy(address(coin), keccak256(abi.encodePacked(ALICE)));
        _fundAndApprove(ochre, ALICE);
        _fundAndApprove(ochre, address(this));
        vm.warp(START);
    }

    function _deploy(address currency, bytes32 root) internal returns (Ochre) {
        return new Ochre(
            currency,
            ADMIN,
            ADAM,
            root,
            START,
            bytes32("zto-cave-test5"),
            bytes32("zto-cave-test4"),
            bytes32("zto-cave-test3"),
            bytes32("zto-cave-test2"),
            bytes32("zto-cave-test5"),
            bytes32("zto-cave-test4"),
            bytes32("zto-cave-test3")
        );
    }

    function _fundAndApprove(Ochre target, address wallet) internal {
        MockCoin currency = MockCoin(address(target.coin()));
        currency.mint(wallet, 1_000_000_000);
        vm.prank(wallet);
        currency.approve(address(target), 1_000_000_000);
    }

    function _expectedSlots(uint256 cave, uint256 round) internal pure returns (uint256) {
        uint256[7] memory slots = [uint256(1), 1, 2, 3, 4, 4, 4];
        return cave == 7 && round == 21 ? 5 : slots[cave - 1];
    }

    function _buyOriginalSales(Ochre target) internal {
        for (uint256 cave = 1; cave <= 7; ++cave) {
            for (uint256 round = 1; round <= 21; ++round) {
                for (uint256 slot = 6 - _expectedSlots(cave, round); slot <= 5; ++slot) {
                    uint256 expected = (cave - 1) * 105 + (round - 1) * 5 + slot;
                    assertEq(target.buy(cave), expected, "sale order");
                    assertEq(target.ownerOf(expected), address(this));
                }
            }
        }
    }

    function _mintReserve(Ochre target) internal {
        vm.startPrank(ADMIN);
        for (uint256 i; i < 20; ++i) {
            assertEq(target.mintReserve(address(this)), 631 + 5 * i);
        }
        vm.stopPrank();
    }

    function _mintEverything() internal {
        vm.warp(START + 8 days);
        _buyOriginalSales(ochre);
        ochre.releaseUnclaimed();
        for (uint256 cave = 1; cave <= 6; ++cave) {
            for (uint256 round = 1; round <= 21; ++round) {
                for (uint256 slot = 1; slot <= 5 - _expectedSlots(cave, round); ++slot) {
                    assertEq(ochre.buy(cave), (cave - 1) * 105 + (round - 1) * 5 + slot);
                }
            }
        }
        _mintReserve(ochre);
    }

    function _seatTree() internal pure returns (bytes32[] memory tree) {
        tree = new bytes32[](1024);
        for (uint256 i; i < 512; ++i) {
            tree[512 + i] = keccak256(abi.encodePacked(_seatWallet(i)));
        }
        for (uint256 i = 511; i > 0; --i) {
            tree[i] = _pair(tree[2 * i], tree[2 * i + 1]);
        }
    }

    function _proof(bytes32[] memory tree, uint256 index) internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](9);
        uint256 position = 512 + index;
        for (uint256 i; i < 9; ++i) {
            proof[i] = tree[position ^ 1];
            position /= 2;
        }
    }

    function _pair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _seatWallet(uint256 index) internal pure returns (address) {
        return address(uint160(0x10000 + index));
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
