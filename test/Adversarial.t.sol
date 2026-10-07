// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OchreFixture} from "./Fixtures.sol";
import {MockCoin} from "../src/MockCoin.sol";
import {Ochre} from "../src/Ochre.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FailingCoin is MockCoin {
    uint256 public mode;

    constructor() MockCoin(address(1)) {}

    function setMode(uint256 mode_) external {
        mode = mode_;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (mode == 1) return false;
        if (mode == 2) revert("coin failure");
        return super.transferFrom(from, to, amount);
    }
}

contract NoReturnCoin {
    function transferFrom(address, address, uint256) external pure {}
}

contract ReenteringCoin is MockCoin {
    address public target;
    bool public attempted;
    bool public success;
    bytes public result;

    constructor() MockCoin(address(1)) {}

    function setTarget(address target_) external {
        target = target_;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (!attempted) {
            attempted = true;
            (success, result) = target.call(abi.encodeCall(Ochre.buy, (1)));
        }
        return super.transferFrom(from, to, amount);
    }
}

contract CallbackReceiver is IERC721Receiver {
    Ochre public target;
    bytes public attack;
    bool public reject;
    bool public attempted;
    bool public success;
    bytes public result;

    function configure(Ochre target_, bytes memory attack_, bool reject_) external {
        target = target_;
        attack = attack_;
        reject = reject_;
        attempted = false;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (attack.length != 0 && !attempted) {
            attempted = true;
            (success, result) = address(target).call(attack);
        }
        return reject ? bytes4(0) : IERC721Receiver.onERC721Received.selector;
    }
}

contract AdversarialTest is OchreFixture {
    function testFalseOrRevertingCoinRestoresSaleAndBalances() public {
        FailingCoin badCoin = new FailingCoin();
        Ochre target = _deploy(address(badCoin), bytes32(0));
        _fundAndApprove(target, ALICE);
        badCoin.setMode(1);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.PaymentFailed.selector);
        target.buy(1);
        assertEq(target.totalSupply(), 2);
        assertEq(target.saleMinted(1), 0);
        assertEq(badCoin.balanceOf(DEAD), 0);
        badCoin.setMode(2);
        vm.prank(ALICE);
        vm.expectRevert(bytes("coin failure"));
        target.buy(1);
        badCoin.setMode(0);
        vm.prank(ALICE);
        assertEq(target.buy(1), 5);
    }

    function testMissingCoinReturnIsRejected() public {
        Ochre target = _deploy(address(new NoReturnCoin()), bytes32(0));
        vm.expectRevert();
        target.buy(1);
        assertEq(target.totalSupply(), 2);
        assertEq(target.saleMinted(1), 0);
    }

    function testCoinCannotReenterBuy() public {
        ReenteringCoin badCoin = new ReenteringCoin();
        Ochre target = _deploy(address(badCoin), bytes32(0));
        badCoin.setTarget(address(target));
        _fundAndApprove(target, ALICE);
        vm.prank(ALICE);
        assertEq(target.buy(1), 5);
        assertTrue(badCoin.attempted());
        assertFalse(badCoin.success());
        assertEq(badCoin.result(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        assertEq(target.saleMinted(1), 1);
        assertEq(badCoin.balanceOf(DEAD), 400_000);
    }

    function testReceiverRejectRestoresPaymentAllowanceAndSale() public {
        CallbackReceiver receiver = new CallbackReceiver();
        receiver.configure(ochre, "", true);
        _fundAndApprove(ochre, address(receiver));
        vm.prank(address(receiver));
        vm.expectRevert();
        ochre.buy(1);
        assertEq(coin.balanceOf(address(receiver)), 1_000_000_000);
        assertEq(coin.allowance(address(receiver), address(ochre)), 1_000_000_000);
        assertEq(coin.balanceOf(DEAD), 0);
        assertEq(ochre.totalSupply(), 2);
        assertEq(ochre.saleMinted(1), 0);
        receiver.configure(ochre, "", false);
        vm.prank(address(receiver));
        assertEq(ochre.buy(1), 5);
    }

    function testReceiverCannotReenterBuyOrRelease() public {
        CallbackReceiver receiver = new CallbackReceiver();
        _fundAndApprove(ochre, address(receiver));
        receiver.configure(ochre, abi.encodeCall(ochre.buy, (1)), false);
        vm.prank(address(receiver));
        assertEq(ochre.buy(1), 5);
        assertTrue(receiver.attempted());
        assertFalse(receiver.success());
        assertEq(receiver.result(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        vm.warp(START + 8 days);
        receiver.configure(ochre, abi.encodeCall(ochre.releaseUnclaimed, ()), false);
        vm.prank(address(receiver));
        assertEq(ochre.buy(1), 10);
        assertFalse(receiver.success());
        assertFalse(ochre.unclaimedReleased());
        assertEq(ochre.saleMinted(1), 2);
    }

    function testClaimRejectionRollbackAndReentrancy() public {
        CallbackReceiver receiver = new CallbackReceiver();
        Ochre target = _deploy(address(coin), keccak256(abi.encodePacked(address(receiver))));
        bytes32[] memory proof = new bytes32[](0);
        receiver.configure(target, "", true);
        vm.prank(address(receiver));
        vm.expectRevert();
        target.claimSeat(proof);
        assertFalse(target.claimed(address(receiver)));
        assertEq(target.seatsMinted(), 0);
        assertEq(target.totalSupply(), 2);
        receiver.configure(target, abi.encodeCall(target.claimSeat, (proof)), false);
        vm.prank(address(receiver));
        assertEq(target.claimSeat(proof), 1);
        assertFalse(receiver.success());
        assertEq(receiver.result(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        assertTrue(target.claimed(address(receiver)));
        assertEq(target.seatsMinted(), 1);
    }

    function testReserveRecipientRejectsWithoutConsumingReserve() public {
        CallbackReceiver receiver = new CallbackReceiver();
        receiver.configure(ochre, "", true);
        vm.prank(ADMIN);
        vm.expectRevert();
        ochre.mintReserve(address(receiver));
        assertEq(ochre.reserveMinted(), 0);
        assertEq(ochre.totalSupply(), 2);
        receiver.configure(ochre, "", false);
        vm.prank(ADMIN);
        assertEq(ochre.mintReserve(address(receiver)), 631);
    }

    function testReleasedSeatPaymentFailureDoesNotSkipItsId() public {
        FailingCoin badCoin = new FailingCoin();
        Ochre target = _deploy(address(badCoin), bytes32(0));
        _fundAndApprove(target, ALICE);
        vm.warp(START + 8 days);
        target.releaseUnclaimed();
        vm.startPrank(ALICE);
        for (uint256 i; i < 21; ++i) {
            target.buy(1);
        }
        vm.stopPrank();
        badCoin.setMode(1);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.PaymentFailed.selector);
        target.buy(1);
        badCoin.setMode(0);
        vm.prank(ALICE);
        assertEq(target.buy(1), 1);
    }
}
