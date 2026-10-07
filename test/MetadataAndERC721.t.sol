// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OchreFixture} from "./Fixtures.sol";
import {Ochre} from "../src/Ochre.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract RejectingReceiver {}

contract MetadataAndERC721Test is OchreFixture {
    event Frozen(uint256 indexed cave, string base);
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    function testEndpointAndSampleURIs() public {
        assertEq(ochre.tokenURI(0), "https://zto-cave-test5.sites.imd.fun/zero.json");
        assertEq(ochre.tokenURI(736), "https://zto-cave-test3.sites.imd.fun/one.json");
        vm.prank(ALICE);
        ochre.claimSeat(new bytes32[](0));
        assertEq(ochre.tokenURI(1), "https://zto-cave-test5.sites.imd.fun/line-1/01.json");
        ochre.buy(1);
        assertEq(ochre.tokenURI(5), "https://zto-cave-test5.sites.imd.fun/gathering/01.json");
        vm.warp(START + 7 days);
        assertEq(ochre.buy(3), 214);
        assertEq(ochre.tokenURI(214), "https://zto-cave-test3.sites.imd.fun/line-4/01.json");
        vm.prank(ADMIN);
        ochre.mintReserve(ALICE);
        assertEq(ochre.tokenURI(631), "https://zto-cave-test3.sites.imd.fun/line-1/01.json");
    }

    function testAllURIsBeforeAndAfterIndependentCaveFreezes() public {
        _mintEverything();
        string[7] memory labels = [
            "zto-cave-test5",
            "zto-cave-test4",
            "zto-cave-test3",
            "zto-cave-test2",
            "zto-cave-test5",
            "zto-cave-test4",
            "zto-cave-test3"
        ];
        for (uint256 c = 1; c <= 7; ++c) {
            string memory initialBase = string.concat("https://", labels[c - 1], ".sites.imd.fun/");
            for (uint256 r = 1; r <= 21; ++r) {
                for (uint256 s = 1; s <= 5; ++s) {
                    uint256 id = (c - 1) * 105 + (r - 1) * 5 + s;
                    assertEq(ochre.tokenURI(id), string.concat(initialBase, _suffix(r, s)));
                }
            }
            string memory base = string.concat("ipfs://cave-", Strings.toString(c), "/");
            vm.expectEmit(true, false, false, true, address(ochre));
            emit Frozen(c, base);
            vm.prank(ADMIN);
            ochre.freeze(c, base);
            assertTrue(ochre.frozen(c));
            assertEq(ochre.frozenBase(c), base);
            for (uint256 r = 1; r <= 21; ++r) {
                for (uint256 s = 1; s <= 5; ++s) {
                    assertEq(ochre.tokenURI((c - 1) * 105 + (r - 1) * 5 + s), string.concat(base, _suffix(r, s)));
                }
            }
            vm.prank(ADMIN);
            vm.expectRevert(Ochre.AlreadyFrozen.selector);
            ochre.freeze(c, "ipfs://replacement/");
        }
        assertEq(ochre.tokenURI(0), "ipfs://cave-1/zero.json");
        assertEq(ochre.tokenURI(736), "ipfs://cave-7/one.json");
        assertEq(ochre.tokenURI(731), "ipfs://cave-7/line-1/21.json");
        assertEq(ochre.tokenURI(735), "ipfs://cave-7/gathering/21.json");
    }

    function testFreezeAuthorizationInputAndFutureTokens() public {
        vm.expectRevert(Ochre.OnlyAdmin.selector);
        ochre.freeze(1, "ipfs://cid/");
        vm.startPrank(ADMIN);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.freeze(0, "ipfs://cid/");
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.freeze(8, "ipfs://cid/");
        vm.expectRevert(Ochre.InvalidBase.selector);
        ochre.freeze(1, "");
        vm.expectRevert(Ochre.InvalidBase.selector);
        ochre.freeze(1, "ipfs://cid");
        ochre.freeze(1, "ipfs://cid/");
        vm.stopPrank();
        assertEq(ochre.tokenURI(0), "ipfs://cid/zero.json");
        assertEq(ochre.tokenURI(736), "https://zto-cave-test3.sites.imd.fun/one.json");
        ochre.buy(1);
        assertEq(ochre.tokenURI(5), "ipfs://cid/gathering/01.json");
    }

    function testUnmintedMetadataAndOwnerQueriesRevert() public {
        vm.expectRevert();
        ochre.tokenURI(1);
        vm.expectRevert();
        ochre.tokenURI(737);
        vm.expectRevert();
        ochre.ownerOf(1);
        vm.expectRevert();
        ochre.getApproved(1);
        vm.expectRevert();
        ochre.balanceOf(address(0));
    }

    function testTransfersApprovalsAndApprovalClearing() public {
        vm.prank(ALICE);
        ochre.buy(1);
        vm.prank(BOB);
        vm.expectRevert();
        ochre.approve(BOB, 5);
        vm.prank(BOB);
        vm.expectRevert();
        ochre.transferFrom(ALICE, BOB, 5);
        vm.prank(ALICE);
        ochre.approve(BOB, 5);
        assertEq(ochre.getApproved(5), BOB);
        vm.expectEmit(true, true, true, true, address(ochre));
        emit Transfer(ALICE, BOB, 5);
        vm.prank(BOB);
        ochre.transferFrom(ALICE, BOB, 5);
        assertEq(ochre.ownerOf(5), BOB);
        assertEq(ochre.balanceOf(ALICE), 0);
        assertEq(ochre.getApproved(5), address(0));
        vm.prank(BOB);
        ochre.setApprovalForAll(ALICE, true);
        assertTrue(ochre.isApprovedForAll(BOB, ALICE));
        vm.prank(ALICE);
        ochre.safeTransferFrom(BOB, address(this), 5, hex"cafe");
        assertEq(ochre.ownerOf(5), address(this));
        ochre.safeTransferFrom(address(this), ALICE, 5);
        assertEq(ochre.ownerOf(5), ALICE);
        assertEq(ochre.totalSupply(), 3);
    }

    function testBadTransferRecipientsAndWrongOwnerRollback() public {
        ochre.buy(1);
        vm.expectRevert();
        ochre.transferFrom(address(this), address(0), 5);
        vm.expectRevert();
        ochre.transferFrom(ALICE, BOB, 5);
        RejectingReceiver receiver = new RejectingReceiver();
        vm.expectRevert();
        ochre.safeTransferFrom(address(this), address(receiver), 5);
        assertEq(ochre.ownerOf(5), address(this));
    }

    function _suffix(uint256 round, uint256 slot) private pure returns (string memory) {
        bytes memory twoDigits = new bytes(2);
        twoDigits[0] = bytes1(uint8(48 + round / 10));
        twoDigits[1] = bytes1(uint8(48 + round % 10));
        string memory dir = slot == 5 ? "gathering/" : string.concat("line-", Strings.toString(slot), "/");
        return string.concat(dir, string(twoDigits), ".json");
    }
}
