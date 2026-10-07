// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OchreFixture} from "./Fixtures.sol";
import {MockCoin} from "../src/MockCoin.sol";
import {Ochre} from "../src/Ochre.sol";
import {Deploy} from "../script/Deploy.s.sol";

contract MockCoinAndDeploymentTest is OchreFixture {
    function testMockCoinInitialSupplyAndPermissionlessMint() public {
        MockCoin currency = new MockCoin(ADMIN);
        assertEq(currency.name(), "Pigment");
        assertEq(currency.symbol(), "PGMT");
        assertEq(currency.decimals(), 18);
        assertEq(currency.totalSupply(), 1_000_000_000 ether);
        assertEq(currency.balanceOf(ADMIN), currency.totalSupply());
        vm.prank(BOB);
        currency.mint(ALICE, 2 ether);
        assertEq(currency.balanceOf(ALICE), 2 ether);
        assertEq(currency.totalSupply(), 1_000_000_002 ether);
        vm.expectRevert();
        currency.mint(address(0), 1);
        vm.expectRevert();
        new MockCoin(address(0));
    }

    function testMockCoinTransferAndAllowance() public {
        vm.prank(ALICE);
        coin.transfer(BOB, 100);
        vm.prank(BOB);
        coin.approve(ALICE, 60);
        vm.prank(ALICE);
        assertTrue(coin.transferFrom(BOB, DEAD, 60));
        assertEq(coin.balanceOf(BOB), 40);
        assertEq(coin.allowance(BOB, ALICE), 0);
        vm.prank(ALICE);
        vm.expectRevert();
        coin.transferFrom(BOB, DEAD, 1);
    }

    function testExactSepoliaRehearsalDeployment() public {
        vm.chainId(11_155_111);
        Deploy deployer = new Deploy();
        vm.prank(BOB);
        (MockCoin currency, Ochre target) = deployer.run();
        assertEq(address(target.coin()), address(currency));
        assertEq(currency.balanceOf(ADMIN), 1_000_000_000 ether);
        assertEq(target.admin(), ADMIN);
        assertEq(target.adam(), ADMIN);
        assertEq(target.ownerOf(0), ADMIN);
        assertEq(target.ownerOf(736), ADMIN);
        assertEq(target.balanceOf(ADMIN), 2);
        assertEq(target.startTime(), START);
        assertEq(target.seatRoot(), bytes32(0x1111111111111111111111111111111111111111111111111111111111111111));
        assertEq(target.labels(1), bytes32("zto-cave-test5"));
        assertEq(target.labels(2), bytes32("zto-cave-test4"));
        assertEq(target.labels(3), bytes32("zto-cave-test3"));
        assertEq(target.labels(4), bytes32("zto-cave-test2"));
        assertEq(target.labels(5), bytes32("zto-cave-test5"));
        assertEq(target.labels(6), bytes32("zto-cave-test4"));
        assertEq(target.labels(7), bytes32("zto-cave-test3"));
        vm.prank(ALICE);
        vm.expectRevert(Ochre.InvalidProof.selector);
        target.claimSeat(new bytes32[](0));
        _checkRuntime(address(currency).code);
        _checkRuntime(address(target).code);
        assertLe(type(MockCoin).creationCode.length + 32, 49_152);
        assertLe(type(Ochre).creationCode.length + 12 * 32, 49_152);
    }

    function testDeploymentHelperRejectsOtherChains() public {
        vm.chainId(1);
        Deploy deployer = new Deploy();
        vm.expectRevert(bytes("Sepolia only"));
        deployer.run();
    }

    function testConstructorAcceptsCoinWithNoCodeAndSkipsReceiverCallbacks() public {
        address noCode = address(0xCAFE);
        assertEq(noCode.code.length, 0);
        Ochre target = new Ochre(
            noCode,
            address(coin),
            address(coin),
            bytes32(0),
            START,
            bytes32("a"),
            bytes32("b"),
            bytes32("c"),
            bytes32("d"),
            bytes32("e"),
            bytes32("f"),
            bytes32("g")
        );
        assertEq(target.ownerOf(0), address(coin));
        assertEq(target.ownerOf(736), address(coin));
        vm.expectRevert();
        target.buy(1);
        assertEq(target.totalSupply(), 2);
    }

    function testLabelLengthsAndInvalidPadding() public {
        Ochre target = _deployWithLabel(bytes32("abcdefghijklmnopqrstuvwxyz123456"));
        assertEq(target.tokenURI(0), "https://abcdefghijklmnopqrstuvwxyz123456.sites.imd.fun/zero.json");
        target = _deployWithLabel(bytes32("a"));
        assertEq(target.tokenURI(0), "https://a.sites.imd.fun/zero.json");
        vm.expectRevert(Ochre.InvalidConfiguration.selector);
        _deployWithLabel(bytes32(0));
        vm.expectRevert(Ochre.InvalidConfiguration.selector);
        _deployWithLabel(bytes32(hex"610062"));
        vm.expectRevert(Ochre.InvalidConfiguration.selector);
        _deployWithLabel(bytes32(hex"ff"));
    }

    function testConstructorRejectsZeroAddressesAndTimestampOverflow() public {
        vm.expectRevert(Ochre.InvalidConfiguration.selector);
        _deploy(address(0), bytes32(0));
        vm.expectRevert(Ochre.InvalidConfiguration.selector);
        _deployWithPrincipals(address(0), ADAM, START);
        vm.expectRevert(Ochre.InvalidConfiguration.selector);
        _deployWithPrincipals(ADMIN, address(0), START);
        vm.expectRevert(Ochre.InvalidConfiguration.selector);
        _deployWithPrincipals(ADMIN, ADAM, type(uint256).max);
    }

    function _deployWithLabel(bytes32 label) private returns (Ochre) {
        return new Ochre(address(coin), ADMIN, ADAM, bytes32(0), START, label, label, label, label, label, label, label);
    }

    function _deployWithPrincipals(address admin, address adam, uint256 start) private returns (Ochre) {
        bytes32 label = bytes32("test");
        return new Ochre(address(coin), admin, adam, bytes32(0), start, label, label, label, label, label, label, label);
    }

    function _checkRuntime(bytes memory code) private pure {
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
