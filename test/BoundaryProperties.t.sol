// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {OchreFixture} from "./Fixtures.sol";
import {Ochre} from "src/Ochre.sol";

contract BoundaryPropertiesTest is OchreFixture {
    /// forge-config: default.fuzz.runs = 512
    function testFuzzBuyDebitsExactPriceAndEmitsPaymentMintAndPurchase(uint256 caveSeed, uint256 elapsedSeed) public {
        uint256 cave = bound(caveSeed, 1, 7);
        uint256 elapsed = bound(elapsedSeed, 0, 30 days);
        uint256 price = elapsed >= 20 hours ? 40_000 : 400_000 - elapsed * 5;
        vm.warp(START + (cave - 1) * 1 days + elapsed);
        uint256 beforeBalance = coin.balanceOf(ALICE);
        vm.prank(ALICE);
        coin.approve(address(ochre), price);
        vm.recordLogs();
        vm.prank(ALICE);
        uint256 id = ochre.buy(cave);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool paymentEvent;
        bool mintEvent;
        bool boughtEvent;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory entry = logs[i];
            if (entry.emitter == address(coin) && entry.topics[0] == keccak256("Transfer(address,address,uint256)")) {
                assertEq(entry.topics.length, 3);
                assertEq(entry.topics[1], bytes32(uint256(uint160(ALICE))));
                assertEq(entry.topics[2], bytes32(uint256(uint160(DEAD))));
                assertEq(abi.decode(entry.data, (uint256)), price);
                assertFalse(paymentEvent, "duplicate payment event");
                paymentEvent = true;
            } else if (
                entry.emitter == address(ochre) && entry.topics[0] == keccak256("Transfer(address,address,uint256)")
            ) {
                assertEq(entry.topics.length, 4);
                assertEq(entry.topics[1], bytes32(0));
                assertEq(entry.topics[2], bytes32(uint256(uint160(ALICE))));
                assertEq(entry.topics[3], bytes32(id));
                assertEq(entry.data.length, 0);
                mintEvent = true;
            } else if (
                entry.emitter == address(ochre) && entry.topics[0] == keccak256("Bought(uint256,address,uint256)")
            ) {
                assertEq(entry.topics.length, 3);
                assertEq(entry.topics[1], bytes32(id));
                assertEq(entry.topics[2], bytes32(uint256(uint160(ALICE))));
                assertEq(abi.decode(entry.data, (uint256)), price);
                boughtEvent = true;
            }
        }
        assertTrue(paymentEvent && mintEvent && boughtEvent, "missing or mis-indexed event");
        assertEq(coin.balanceOf(ALICE), beforeBalance - price);
        assertEq(coin.balanceOf(DEAD), price);
        assertEq(coin.balanceOf(address(ochre)), 0);
        assertEq(coin.allowance(ALICE, address(ochre)), 0);
        assertEq(ochre.ownerOf(id), ALICE);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzPartialSeatClaimsAndReleaseReachExactly737(uint256 countSeed, uint256 walletSeed) public {
        _partialRelease(bound(countSeed, 0, 315), bound(walletSeed, 0, 511));
    }

    // Keep complete sellouts in separate tests to stay below the runner gas limit.
    function testPartialReleaseAcrossCaveOneSeatBoundary() public {
        _partialRelease(83, 511);
        _partialRelease(84, 511);
        _partialRelease(85, 511);
    }

    function testPartialReleaseAcrossCaveTwoSeatBoundary() public {
        _partialRelease(167, 511);
        _partialRelease(168, 511);
        _partialRelease(169, 511);
    }

    function testPartialReleaseAcrossCaveThreeSeatBoundary() public {
        _partialRelease(230, 511);
        _partialRelease(231, 511);
        _partialRelease(232, 511);
    }

    function testPartialReleaseAcrossCaveFourSeatBoundary() public {
        _partialRelease(272, 511);
        _partialRelease(273, 511);
        _partialRelease(274, 511);
    }

    function testPartialReleaseAcrossCaveFiveSeatBoundary() public {
        _partialRelease(293, 511);
        _partialRelease(294, 511);
        _partialRelease(295, 511);
    }

    function testPartialReleaseAtEmptyAndFullSeatBoundaries() public {
        _partialRelease(0, 511);
        _partialRelease(314, 511);
        _partialRelease(315, 511);
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzzInvalidCavesFailBeforeArithmetic(uint256 seed, bool zero) public {
        uint256 cave = zero ? 0 : bound(seed, 8, type(uint256).max);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.caveOpen(cave);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.startPrice(cave);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.priceNow(cave);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.saleCount(cave);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.saleSlots(cave, 1);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.pieceId(cave, 1, 1);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.buy(cave);
        vm.prank(ADMIN);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.freeze(cave, "ipfs://cid/");
        assertEq(ochre.totalSupply(), 2);
        assertEq(coin.balanceOf(DEAD), 0);
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzzInvalidIdsRoundsAndSlots(uint256 idSeed, uint256 roundSeed, uint256 slotSeed, bool zero) public {
        uint256 id = bound(idSeed, 737, type(uint256).max);
        uint256 round = zero ? 0 : bound(roundSeed, 22, type(uint256).max);
        uint256 slot = zero ? 0 : bound(slotSeed, 6, type(uint256).max);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.piece(id);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.isSalePiece(id);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.pieceId(7, round, 1);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.pieceId(7, 21, slot);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.saleSlots(7, round);
        vm.expectRevert();
        ochre.ownerOf(id);
        vm.expectRevert();
        ochre.tokenURI(id);
    }

    function testMaximumAcceptedStartHasSafeOpeningPriceAndReleaseArithmetic() public {
        uint256 start = type(uint256).max - 8 days;
        bytes32 label = bytes32("boundary");
        Ochre target =
            new Ochre(address(coin), ADMIN, ADAM, bytes32(0), start, label, label, label, label, label, label, label);
        _fundAndApprove(target, ALICE);
        for (uint256 cave = 1; cave <= 7; ++cave) {
            uint256 opens = start + (cave - 1) * 1 days;
            assertEq(target.caveOpen(cave), opens);
            vm.warp(opens);
            assertEq(target.priceNow(cave), 400_000);
            vm.warp(opens + 20 hours);
            assertEq(target.priceNow(cave), 40_000);
        }
        vm.warp(type(uint256).max - 1);
        vm.expectRevert(Ochre.TooEarly.selector);
        target.releaseUnclaimed();
        vm.warp(type(uint256).max);
        target.releaseUnclaimed();
        vm.prank(ALICE);
        assertEq(target.buy(7), 632);
        assertEq(coin.balanceOf(DEAD), 40_000);
        vm.expectRevert(Ochre.InvalidConfiguration.selector);
        new Ochre(address(coin), ADMIN, ADAM, bytes32(0), start + 1, label, label, label, label, label, label, label);
    }

    function _partialRelease(uint256 count, uint256 firstWallet) private {
        bytes32[] memory tree = _seatTree();
        Ochre target = _deploy(address(coin), tree[1]);
        _fundAndApprove(target, address(this));
        address[737] memory claimedOwner;
        uint256[7] memory claimedPerCave;
        vm.warp(START);
        for (uint256 i; i < count; ++i) {
            uint256 index = (firstWallet + i) % 512;
            address wallet = _seatWallet(index);
            bytes32[] memory proof = _proof(tree, index);
            vm.prank(wallet);
            uint256 id = target.claimSeat(proof);
            assertLe(id, 630);
            assertEq(claimedOwner[id], address(0), "duplicate seat");
            claimedOwner[id] = wallet;
            ++claimedPerCave[(id - 1) / 105];
            // Ownership transfers must not make claimed inventory purchasable.
            if (i % 3 == 0) {
                vm.prank(wallet);
                target.transferFrom(wallet, BOB, id);
                claimedOwner[id] = BOB;
            }
        }
        vm.warp(START + 8 days);
        vm.prank(BOB);
        target.releaseUnclaimed();
        uint256 deadBefore = coin.balanceOf(DEAD);
        _buyOriginalSales(target);
        uint256[6] memory freeCounts = [uint256(84), 84, 63, 42, 21, 21];
        for (uint256 cave = 1; cave <= 6; ++cave) {
            uint256 previous;
            uint256 remaining = freeCounts[cave - 1] - claimedPerCave[cave - 1];
            for (uint256 i; i < remaining; ++i) {
                uint256 id = target.buy(cave);
                assertGt(id, previous, "released pieces must be in ascending order");
                assertEq((id - 1) / 105 + 1, cave, "released piece came from another cave");
                assertEq(claimedOwner[id], address(0), "released an already claimed piece");
                assertEq(target.ownerOf(id), address(this));
                previous = id;
            }
        }
        _mintReserve(target);
        assertEq(target.totalSupply(), 737);
        assertEq(target.seatsMinted(), count);
        assertEq(coin.balanceOf(DEAD) - deadBefore, (715 - count) * 40_000);
        assertEq(coin.balanceOf(address(target)), 0);
        for (uint256 id; id < 737; ++id) {
            assertTrue(target.ownerOf(id) != address(0));
            if (claimedOwner[id] != address(0)) assertEq(target.ownerOf(id), claimedOwner[id]);
        }
        for (uint256 cave = 1; cave <= 7; ++cave) {
            vm.expectRevert(Ochre.SoldOut.selector);
            target.buy(cave);
        }
    }
}
