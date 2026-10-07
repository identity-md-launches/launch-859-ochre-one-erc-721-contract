// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OchreFixture} from "./Fixtures.sol";
import {Ochre} from "../src/Ochre.sol";

contract OchreTest is OchreFixture {
    event Bought(uint256 indexed id, address indexed buyer, uint256 price);
    event Claimed(uint256 indexed id, address indexed wallet);
    event ReserveMinted(uint256 indexed id, address indexed to);
    event UnclaimedReleased();

    function testInitialStateAndInterfaces() public view {
        assertEq(ochre.name(), "Ochre");
        assertEq(ochre.symbol(), "OCHRE");
        assertEq(ochre.ownerOf(0), ADAM);
        assertEq(ochre.ownerOf(736), ADMIN);
        assertEq(ochre.totalSupply(), 2);
        assertEq(ochre.admin(), ADMIN);
        assertEq(ochre.adam(), ADAM);
        assertEq(ochre.dead(), DEAD);
        assertEq(address(ochre.coin()), address(coin));
        assertEq(ochre.COIN_DECIMALS(), 18);
        assertTrue(ochre.supportsInterface(0x01ffc9a7));
        assertTrue(ochre.supportsInterface(0x80ac58cd));
        assertTrue(ochre.supportsInterface(0x5b5e139f));
        assertFalse(ochre.supportsInterface(0x2a55205a));
        assertFalse(ochre.supportsInterface(0xffffffff));
    }

    function testAllPieceArithmeticAndAllocationCounts() public view {
        uint256[7] memory expectedSale = [uint256(21), 21, 42, 63, 84, 84, 85];
        uint256 totalSales;
        uint256 seats;
        uint256 reserve;
        for (uint256 cave = 1; cave <= 7; ++cave) {
            uint256 sales;
            for (uint256 round = 1; round <= 21; ++round) {
                uint256 k = _expectedSlots(cave, round);
                assertEq(ochre.saleSlots(cave, round), k);
                for (uint256 slot = 1; slot <= 5; ++slot) {
                    uint256 id = (cave - 1) * 105 + (round - 1) * 5 + slot;
                    (uint256 c, uint256 r, uint256 s) = ochre.piece(id);
                    assertEq(c, cave);
                    assertEq(r, round);
                    assertEq(s, slot);
                    assertEq(ochre.pieceId(cave, round, slot), id);
                    assertEq(ochre.isSalePiece(id), slot > 5 - k);
                    if (slot > 5 - k) ++sales;
                    else if (cave < 7) ++seats;
                    else ++reserve;
                }
            }
            assertEq(sales, expectedSale[cave - 1]);
            assertEq(ochre.saleCount(cave), sales);
            totalSales += sales;
        }
        assertEq(totalSales, 400);
        assertEq(seats, 315);
        assertEq(reserve, 20);
        assertFalse(ochre.isSalePiece(0));
        assertFalse(ochre.isSalePiece(736));
    }

    function testPriceBoundariesEveryCave() public {
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 opens = START + (c - 1) * 1 days;
            assertEq(ochre.caveOpen(c), opens);
            assertEq(ochre.startPrice(c), 400_000);
            vm.warp(opens - 1);
            assertEq(ochre.priceNow(c), 400_000);
            vm.warp(opens);
            assertEq(ochre.priceNow(c), 400_000);
            vm.warp(opens + 1);
            assertEq(ochre.priceNow(c), 399_995);
            vm.warp(opens + 10 hours);
            assertEq(ochre.priceNow(c), 220_000);
            vm.warp(opens + 20 hours - 1);
            assertEq(ochre.priceNow(c), 40_005);
            vm.warp(opens + 20 hours);
            assertEq(ochre.priceNow(c), 40_000);
            vm.warp(opens + 100 days);
            assertEq(ochre.priceNow(c), 40_000);
        }
    }

    function testFuzzPriceLine(uint8 caveSeed, uint32 elapsedSeed) public {
        uint256 cave = uint256(caveSeed) % 7 + 1;
        uint256 elapsed = uint256(elapsedSeed) % 100 days;
        vm.warp(START + (cave - 1) * 1 days + elapsed);
        // The specified values decrease by exactly five base units per second.
        uint256 expected = elapsed >= 72_000 ? 40_000 : 400_000 - 5 * elapsed;
        assertEq(ochre.priceNow(cave), expected);
    }

    function testEveryCaveRejectsBeforeOpenAndAcceptsAtOpen() public {
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 opens = START + (c - 1) * 1 days;
            vm.warp(opens - 1);
            vm.expectRevert(Ochre.NotOpen.selector);
            ochre.buy(c);
            vm.warp(opens);
            assertEq(ochre.buy(c), (c - 1) * 105 + 6 - _expectedSlots(c, 1));
        }
    }

    function testBuyPaymentAndEventNoWalletLimit() public {
        uint256 balance = coin.balanceOf(ALICE);
        uint256 supply = coin.totalSupply();
        vm.expectEmit(true, true, false, true, address(ochre));
        emit Bought(5, ALICE, 400_000);
        vm.prank(ALICE);
        assertEq(ochre.buy(1), 5);
        vm.warp(START + 10 hours);
        vm.prank(ALICE);
        assertEq(ochre.buy(1), 10);
        assertEq(coin.balanceOf(ALICE), balance - 620_000);
        assertEq(coin.balanceOf(DEAD), 620_000);
        assertEq(coin.balanceOf(address(ochre)), 0);
        assertEq(coin.balanceOf(ADMIN), 1_000_000_000 ether);
        assertEq(coin.totalSupply(), supply, "dead transfer does not reduce ERC20 supply");
        assertEq(coin.allowance(ALICE, address(ochre)), 1_000_000_000 - 620_000);
        assertEq(ochre.balanceOf(ALICE), 2);
    }

    function testBuyMissingAllowanceRollsBack() public {
        coin.mint(BOB, 400_000);
        vm.prank(BOB);
        vm.expectRevert();
        ochre.buy(1);
        assertEq(ochre.saleMinted(1), 0);
        assertEq(ochre.totalSupply(), 2);
        assertEq(coin.balanceOf(DEAD), 0);
        vm.startPrank(BOB);
        coin.approve(address(ochre), 400_000);
        assertEq(ochre.buy(1), 5);
        vm.stopPrank();
    }

    function testBuyMissingBalanceRollsBack() public {
        vm.prank(BOB);
        coin.approve(address(ochre), 400_000);
        vm.prank(BOB);
        vm.expectRevert();
        ochre.buy(1);
        assertEq(ochre.saleMinted(1), 0);
        assertEq(coin.allowance(BOB, address(ochre)), 400_000);
        assertEq(ochre.buy(1), 5);
    }

    function testExactSaleSequenceAndExhaustionAllCaves() public {
        vm.warp(START + 7 days);
        _buyOriginalSales(ochre);
        assertEq(ochre.totalSupply(), 402);
        assertEq(coin.balanceOf(DEAD), 400 * 40_000);
        for (uint256 c = 1; c <= 7; ++c) {
            assertEq(ochre.saleMinted(c), ochre.saleCount(c));
            vm.expectRevert(Ochre.SoldOut.selector);
            ochre.buy(c);
        }
    }

    function testClaimOpeningProofReplayAndEvent() public {
        bytes32[] memory empty = new bytes32[](0);
        vm.warp(START - 1);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.NotOpen.selector);
        ochre.claimSeat(empty);
        vm.warp(START);
        vm.prank(BOB);
        vm.expectRevert(Ochre.InvalidProof.selector);
        ochre.claimSeat(empty);
        bytes32[] memory bad = new bytes32[](1);
        bad[0] = bytes32(uint256(1));
        vm.prank(ALICE);
        vm.expectRevert(Ochre.InvalidProof.selector);
        ochre.claimSeat(bad);
        uint256 beforeBalance = coin.balanceOf(ALICE);
        vm.expectEmit(true, true, false, true, address(ochre));
        emit Claimed(1, ALICE);
        vm.prank(ALICE);
        assertEq(ochre.claimSeat(empty), 1);
        assertEq(coin.balanceOf(ALICE), beforeBalance);
        assertEq(ochre.ownerOf(1), ALICE);
        assertTrue(ochre.claimed(ALICE));
        vm.prank(ALICE);
        ochre.transferFrom(ALICE, BOB, 1);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.AlreadyClaimed.selector);
        ochre.claimSeat(empty);
    }

    function testSortedMerkleTreeAll315SeatsAndCap() public {
        bytes32[] memory tree = _seatTree();
        Ochre target = _deploy(address(coin), tree[1]);
        uint256 index;
        // All caves' seats are claimable at startTime, without waiting for sale openings.
        for (uint256 cave = 1; cave <= 6; ++cave) {
            for (uint256 round = 1; round <= 21; ++round) {
                for (uint256 slot = 1; slot <= 5 - _expectedSlots(cave, round); ++slot) {
                    bytes32[] memory proof = _proof(tree, index);
                    address wallet = _seatWallet(index);
                    vm.prank(wallet);
                    uint256 id = target.claimSeat(proof);
                    assertEq(id, (cave - 1) * 105 + (round - 1) * 5 + slot);
                    assertEq(target.ownerOf(id), wallet);
                    ++index;
                }
            }
        }
        assertEq(index, 315);
        assertEq(target.seatsMinted(), 315);
        bytes32[] memory extraProof = _proof(tree, 315);
        vm.prank(_seatWallet(315));
        vm.expectRevert(Ochre.SeatsClosed.selector);
        target.claimSeat(extraProof);
        _fundAndApprove(target, address(this));
        vm.warp(START + 8 days);
        target.releaseUnclaimed();
        _buyOriginalSales(target);
        _mintReserve(target);
        assertEq(target.totalSupply(), 737);
        for (uint256 c = 1; c <= 7; ++c) {
            vm.expectRevert(Ochre.SoldOut.selector);
            target.buy(c);
        }
    }

    function testProofIsBoundToCallerAndSiblingOrdering() public {
        bytes32[] memory tree = _seatTree();
        Ochre target = _deploy(address(coin), tree[1]);
        bytes32[] memory proof = _proof(tree, 22);
        vm.prank(_seatWallet(23));
        vm.expectRevert(Ochre.InvalidProof.selector);
        target.claimSeat(proof);
        vm.prank(_seatWallet(22));
        assertEq(target.claimSeat(proof), 1);
    }

    function testReserveAuthorizationEventCapAndNoOpeningRestriction() public {
        vm.warp(START - 1);
        vm.expectRevert(Ochre.OnlyAdmin.selector);
        ochre.mintReserve(ALICE);
        vm.expectEmit(true, true, false, true, address(ochre));
        emit ReserveMinted(631, ALICE);
        vm.prank(ADMIN);
        assertEq(ochre.mintReserve(ALICE), 631);
        vm.startPrank(ADMIN);
        for (uint256 i = 1; i < 20; ++i) {
            assertEq(ochre.mintReserve(ALICE), 631 + 5 * i);
        }
        vm.expectRevert(Ochre.ReserveExhausted.selector);
        ochre.mintReserve(ALICE);
        vm.stopPrank();
        assertEq(ochre.reserveMinted(), 20);
        assertEq(ochre.balanceOf(ALICE), 20);
    }

    function testReserveZeroRecipientRollsBack() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        ochre.mintReserve(address(0));
        assertEq(ochre.reserveMinted(), 0);
        vm.prank(ADMIN);
        assertEq(ochre.mintReserve(ALICE), 631);
    }

    function testReleaseBoundaryEventAndRepeat() public {
        vm.warp(START + 8 days - 1);
        vm.expectRevert(Ochre.TooEarly.selector);
        ochre.releaseUnclaimed();
        vm.warp(START + 8 days);
        vm.expectEmit(false, false, false, true, address(ochre));
        emit UnclaimedReleased();
        vm.prank(BOB);
        ochre.releaseUnclaimed();
        assertTrue(ochre.unclaimedReleased());
        vm.expectRevert(Ochre.AlreadyReleased.selector);
        ochre.releaseUnclaimed();
        vm.prank(ALICE);
        vm.expectRevert(Ochre.SeatsClosed.selector);
        ochre.claimSeat(new bytes32[](0));
    }

    function testReleaseIsExplicitAndSkipsClaimedEvenAfterTransfer() public {
        vm.warp(START + 9 days);
        vm.prank(ALICE);
        ochre.claimSeat(new bytes32[](0));
        vm.prank(ALICE);
        ochre.transferFrom(ALICE, BOB, 1);
        for (uint256 i; i < 21; ++i) {
            assertEq(ochre.buy(1), 5 * (i + 1));
        }
        vm.expectRevert(Ochre.SoldOut.selector);
        ochre.buy(1);
        ochre.releaseUnclaimed();
        vm.expectEmit(true, true, false, true, address(ochre));
        emit Bought(2, address(this), 40_000);
        assertEq(ochre.buy(1), 2);
        assertEq(ochre.ownerOf(1), BOB);
        assertEq(ochre.saleMinted(1), 21);
    }

    function testReleasedSeatsFollowRemainingSales() public {
        vm.warp(START + 8 days);
        ochre.releaseUnclaimed();
        for (uint256 i; i < 21; ++i) {
            assertEq(ochre.buy(1), 5 * (i + 1));
        }
        assertEq(ochre.buy(1), 1);
        assertEq(ochre.buy(1), 2);
        assertEq(ochre.buy(1), 3);
        assertEq(ochre.buy(1), 4);
        assertEq(ochre.buy(1), 6);
    }

    function testReleaseNeverSellsCaveSevenReserve() public {
        vm.warp(START + 8 days);
        ochre.releaseUnclaimed();
        for (uint256 i; i < 85; ++i) {
            ochre.buy(7);
        }
        vm.expectRevert(Ochre.SoldOut.selector);
        ochre.buy(7);
        assertEq(ochre.reserveMinted(), 0);
        _mintReserve(ochre);
    }

    function testAll737UniquePiecesAndNoFurtherMinting() public {
        _mintEverything();
        assertEq(ochre.totalSupply(), 737);
        assertEq(ochre.balanceOf(address(this)), 735);
        assertEq(coin.balanceOf(DEAD), 715 * 40_000);
        assertEq(coin.balanceOf(address(ochre)), 0);
        for (uint256 id; id < 737; ++id) {
            assertTrue(ochre.ownerOf(id) != address(0));
        }
        for (uint256 cave = 1; cave <= 7; ++cave) {
            vm.expectRevert(Ochre.SoldOut.selector);
            ochre.buy(cave);
        }
        vm.prank(ADMIN);
        vm.expectRevert(Ochre.ReserveExhausted.selector);
        ochre.mintReserve(ALICE);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.SeatsClosed.selector);
        ochre.claimSeat(new bytes32[](0));
        vm.expectRevert();
        ochre.ownerOf(737);
    }

    function testInvalidCaveAndPieceInputs() public {
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.buy(0);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.buy(8);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.priceNow(type(uint256).max);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.piece(737);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.pieceId(1, 0, 1);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.pieceId(1, 22, 1);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.pieceId(1, 1, 0);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.pieceId(1, 1, 6);
    }

    function testCannotSendEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(ochre).call{value: 1}("");
        assertFalse(ok);
        (ok,) = address(ochre).call{value: 1}(abi.encodeCall(ochre.buy, (1)));
        assertFalse(ok);
        assertEq(address(ochre).balance, 0);
    }
}
