// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockCoin} from "src/MockCoin.sol";

contract PigmentSequenceHandler is Test {
    MockCoin public coin;
    address[5] private accounts;
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    uint256 private supply;

    constructor() {
        accounts = [
            0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479,
            address(0x22001),
            address(0x22002),
            address(0x22003),
            address(0xdEaD)
        ];
        coin = new MockCoin(accounts[0]);
        supply = 1_000_000_000 ether;
        balances[accounts[0]] = supply;
    }

    function mint(uint256 callerSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address to = accounts[bound(recipientSeed, 0, 4)];
        uint256 amount = bound(amountSeed, 0, 1e30);
        vm.prank(accounts[bound(callerSeed, 0, 3)]);
        coin.mint(to, amount);
        balances[to] += amount;
        supply += amount;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = accounts[bound(fromSeed, 0, 3)];
        address to = accounts[bound(toSeed, 0, 4)];
        uint256 amount = bound(amountSeed, 0, balances[from]);
        vm.prank(from);
        assertTrue(coin.transfer(to, amount));
        balances[from] -= amount;
        balances[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool infinite) external {
        address owner = accounts[bound(ownerSeed, 0, 3)];
        address spender = accounts[bound(spenderSeed, 0, 3)];
        uint256 amount = infinite ? type(uint256).max : amountSeed;
        vm.prank(owner);
        assertTrue(coin.approve(spender, amount));
        allowances[owner][spender] = amount;
    }

    /// @dev Preparing authorization keeps this action useful even in short sequences.
    function spend(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed, bool infinite) external {
        address from = accounts[bound(fromSeed, 0, 3)];
        address to = accounts[bound(toSeed, 0, 4)];
        address spender = accounts[bound(spenderSeed, 0, 3)];
        uint256 amount = bound(amountSeed, 0, balances[from]);
        uint256 allowance = infinite ? type(uint256).max : amount;
        vm.prank(from);
        coin.approve(spender, allowance);
        vm.prank(spender);
        assertTrue(coin.transferFrom(from, to, amount));
        allowances[from][spender] = infinite ? type(uint256).max : 0;
        balances[from] -= amount;
        balances[to] += amount;
    }

    /// @dev Also consumes approvals left by earlier unrelated handler calls.
    function spendExisting(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = accounts[bound(fromSeed, 0, 3)];
        address to = accounts[bound(toSeed, 0, 4)];
        address spender = accounts[bound(spenderSeed, 0, 3)];
        uint256 limit = balances[from];
        uint256 allowance = allowances[from][spender];
        if (allowance < limit) limit = allowance;
        uint256 amount = bound(amountSeed, 0, limit);
        vm.prank(spender);
        assertTrue(coin.transferFrom(from, to, amount));
        if (allowance != type(uint256).max) allowances[from][spender] -= amount;
        balances[from] -= amount;
        balances[to] += amount;
    }

    function invalidOperation(uint256 actorSeed, uint256 modeSeed) external {
        uint256 index = bound(actorSeed, 0, 3);
        address actor = accounts[index];
        address other = accounts[(index + 1) % 4];
        uint256 mode = bound(modeSeed, 0, 4);
        bytes memory data;
        if (mode == 0) {
            data = abi.encodeCall(coin.mint, (address(0), 1));
        } else if (mode == 1) {
            data = abi.encodeCall(coin.transfer, (address(0), 0));
        } else if (mode == 2) {
            data = abi.encodeCall(coin.transfer, (other, balances[actor] + 1));
        } else if (mode == 3) {
            vm.prank(other);
            coin.approve(actor, 0);
            allowances[other][actor] = 0;
            data = abi.encodeCall(coin.transferFrom, (other, actor, 1));
        } else {
            data = abi.encodeCall(coin.approve, (address(0), 1));
        }
        vm.prank(actor);
        (bool ok,) = address(coin).call(data);
        assertFalse(ok, "invalid ERC20 operation succeeded");
    }

    function assertLedger() external view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            address account = accounts[i];
            assertEq(coin.balanceOf(account), balances[account], "ERC20 balance ledger");
            sum += coin.balanceOf(account);
            for (uint256 j; j < 4; ++j) {
                assertEq(coin.allowance(account, accounts[j]), allowances[account][accounts[j]], "allowance ledger");
            }
        }
        assertEq(coin.totalSupply(), supply, "only mint changes supply");
        assertEq(sum, supply, "sum of balances equals total supply, including dead");
        assertEq(coin.balanceOf(address(0)), 0);
        assertEq(coin.balanceOf(address(coin)), 0);
    }
}

contract MockCoinInvariantTest is Test {
    PigmentSequenceHandler internal handler;

    function setUp() public {
        handler = new PigmentSequenceHandler();
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.mint.selector;
        selectors[1] = handler.transfer.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.spend.selector;
        selectors[4] = handler.spendExisting.selector;
        selectors[5] = handler.invalidOperation.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_supplyBalancesAndAllowancesMatchIndependentLedger() public view {
        handler.assertLedger();
    }

    function testHandlerReachesFiniteInfiniteSelfAndDeadTransfers() public {
        handler.mint(3, 1, 100);
        handler.transfer(1, 1, 100); // self-transfer
        handler.approve(1, 2, 40, false);
        handler.spendExisting(1, 3, 2, 40);
        handler.spend(1, 4, 2, 30, true); // dead receives; infinite allowance remains
        handler.spendExisting(1, 3, 2, 30);
        for (uint256 i; i < 5; ++i) {
            handler.invalidOperation(1, i);
        }
        handler.assertLedger();
    }

    function testMaximumSupplyAndMintOverflowAreAtomic() public {
        address admin = address(0xA11CE);
        address wallet = address(0xB0B);
        MockCoin currency = new MockCoin(admin);
        uint256 initial = 1_000_000_000 ether;
        currency.mint(wallet, type(uint256).max - initial);
        assertEq(currency.totalSupply(), type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        currency.mint(wallet, 1);
        assertEq(currency.balanceOf(wallet), type(uint256).max - initial);
        assertEq(currency.totalSupply(), type(uint256).max);
        currency.mint(wallet, 0);
        vm.prank(admin);
        currency.transfer(wallet, initial);
        assertEq(currency.balanceOf(wallet), type(uint256).max);
        vm.prank(wallet);
        currency.transfer(address(0xdEaD), type(uint256).max);
        assertEq(currency.balanceOf(wallet), 0);
        assertEq(currency.balanceOf(address(0xdEaD)), type(uint256).max);
        assertEq(currency.totalSupply(), type(uint256).max);
    }
}
