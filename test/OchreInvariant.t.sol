// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ochre} from "src/Ochre.sol";
import {MockCoin} from "src/MockCoin.sol";

/// @dev The model builds the allocation from slot masks, independently of Ochre's
/// piece helpers and cursors. Ghost state advances only after a successful call.
contract OchreSequenceHandler is Test {
    address public constant ADMIN = 0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479;
    address public constant DEAD = address(0xdEaD);
    uint256 public constant START = 1_791_352_835;
    uint256 internal constant FUNDING = 1_000_000_000;
    MockCoin public coin;
    Ochre public ochre;

    address[8] public actors;
    bytes32[16] private tree;
    uint256[][8] private saleIds;
    uint256[][8] private freeIds;
    uint256[] private seatIds;
    uint256[] private issuedIds;
    mapping(uint256 => address) private owners;
    mapping(address => uint256) private nftBalances;
    mapping(address => uint256) private spent;
    mapping(address => bool) private didClaim;
    uint256[8] private sales;
    uint256[8] private releasedSales;
    string[8] private bases;
    uint256 public paid;
    uint256 public claims;
    uint256 public reserves;
    uint256 public releasedPurchases;
    bool public released;

    constructor() {
        vm.chainId(11_155_111);
        for (uint256 i; i < 8; ++i) {
            actors[i] = address(uint160(0x11000 + i));
            tree[8 + i] = keccak256(abi.encodePacked(actors[i]));
        }
        for (uint256 i = 7; i > 0; --i) {
            bytes32 a = tree[2 * i];
            bytes32 b = tree[2 * i + 1];
            tree[i] = keccak256(a < b ? abi.encodePacked(a, b) : abi.encodePacked(b, a));
        }
        coin = new MockCoin(ADMIN);
        ochre = new Ochre(
            address(coin),
            ADMIN,
            ADMIN,
            tree[1],
            START,
            bytes32("zto-cave-test5"),
            bytes32("zto-cave-test4"),
            bytes32("zto-cave-test3"),
            bytes32("zto-cave-test2"),
            bytes32("zto-cave-test5"),
            bytes32("zto-cave-test4"),
            bytes32("zto-cave-test3")
        );
        for (uint256 i; i < 8; ++i) {
            coin.mint(actors[i], FUNDING);
            vm.prank(actors[i]);
            coin.approve(address(ochre), FUNDING);
        }

        // Bit zero denotes slot 1. The final round sells all five slots.
        uint256[7] memory masks = [uint256(16), 16, 24, 28, 30, 30, 30];
        for (uint256 id = 1; id <= 735; ++id) {
            uint256 cave = (id - 1) / 105 + 1;
            uint256 mask = id >= 731 ? 31 : masks[cave - 1];
            if ((mask & (1 << ((id - 1) % 5))) != 0) {
                saleIds[cave].push(id);
            } else {
                freeIds[cave].push(id);
                if (cave < 7) seatIds.push(id);
            }
        }
        _recordMint(0, ADMIN);
        _recordMint(736, ADMIN);
        vm.warp(START - 1);
    }

    function advanceTime(uint256 secondsSeed) external {
        vm.warp(vm.getBlockTimestamp() + bound(secondsSeed, 0, 1 days));
    }

    function buyBatch(uint256 actorSeed, uint256 caveSeed, uint256 countSeed) external {
        address buyer = actors[bound(actorSeed, 0, 7)];
        uint256 cave = bound(caveSeed, 1, 7);
        uint256 count = bound(countSeed, 1, 8);
        for (uint256 i; i < count; ++i) {
            if (!_buy(buyer, cave)) break;
        }
    }

    function claim(uint256 actorSeed, bool corruptProof) external {
        uint256 index = bound(actorSeed, 0, 7);
        address wallet = actors[index];
        bytes32[] memory proof = new bytes32[](3);
        uint256 node = 8 + index;
        for (uint256 i; i < 3; ++i) {
            proof[i] = tree[node ^ 1];
            node /= 2;
        }
        if (corruptProof) proof[0] = bytes32(uint256(proof[0]) ^ 1);
        bytes4 error;
        if (vm.getBlockTimestamp() < START) error = Ochre.NotOpen.selector;
        else if (released) error = Ochre.SeatsClosed.selector;
        else if (didClaim[wallet]) error = Ochre.AlreadyClaimed.selector;
        else if (corruptProof) error = Ochre.InvalidProof.selector;
        if (error != bytes4(0)) {
            _reject(wallet, abi.encodeCall(ochre.claimSeat, (proof)), error);
            return;
        }
        vm.prank(wallet);
        uint256 id = ochre.claimSeat(proof);
        assertEq(id, seatIds[claims], "claim consumed the wrong free piece");
        ++claims;
        didClaim[wallet] = true;
        _recordMint(id, wallet);
    }

    function reserve(uint256 actorSeed, uint256 countSeed, bool authorized) external {
        address recipient = actors[bound(actorSeed, 0, 7)];
        uint256 count = bound(countSeed, 1, 4);
        if (!authorized) {
            _reject(recipient, abi.encodeCall(ochre.mintReserve, (recipient)), Ochre.OnlyAdmin.selector);
            return;
        }
        for (uint256 i; i < count; ++i) {
            if (reserves == 20) {
                _reject(ADMIN, abi.encodeCall(ochre.mintReserve, (recipient)), Ochre.ReserveExhausted.selector);
                break;
            }
            vm.prank(ADMIN);
            uint256 id = ochre.mintReserve(recipient);
            assertEq(id, freeIds[7][reserves], "reserve allocation");
            ++reserves;
            _recordMint(id, recipient);
        }
    }

    function release(uint256 actorSeed) external {
        address caller = actors[bound(actorSeed, 0, 7)];
        if (vm.getBlockTimestamp() < START + 8 days) {
            _reject(caller, abi.encodeCall(ochre.releaseUnclaimed, ()), Ochre.TooEarly.selector);
        } else if (released) {
            _reject(caller, abi.encodeCall(ochre.releaseUnclaimed, ()), Ochre.AlreadyReleased.selector);
        } else {
            vm.prank(caller);
            ochre.releaseUnclaimed();
            released = true;
        }
    }

    function freeze(uint256 caveSeed, uint256 salt, bool authorized) external {
        uint256 cave = bound(caveSeed, 1, 7);
        string memory base = string.concat("ipfs://", vm.toString(salt), "/");
        if (!authorized) {
            _reject(actors[0], abi.encodeCall(ochre.freeze, (cave, base)), Ochre.OnlyAdmin.selector);
        } else if (bytes(bases[cave]).length > 0) {
            _reject(ADMIN, abi.encodeCall(ochre.freeze, (cave, base)), Ochre.AlreadyFrozen.selector);
        } else {
            vm.prank(ADMIN);
            ochre.freeze(cave, base);
            bases[cave] = base;
        }
    }

    function transferPiece(uint256 idSeed, uint256 recipientSeed, uint256 modeSeed) external {
        uint256 id = issuedIds[bound(idSeed, 0, issuedIds.length - 1)];
        address from = owners[id];
        address to = actors[bound(recipientSeed, 0, 7)];
        // This address is never an owner and never retains operator approval.
        address operator = address(0x0B0B);
        uint256 mode = bound(modeSeed, 0, 3);
        if (mode == 3) {
            vm.prank(operator);
            (bool ok,) = address(ochre).call(abi.encodeCall(ochre.transferFrom, (from, to, id)));
            assertFalse(ok, "unapproved transfer succeeded");
            assertEq(ochre.ownerOf(id), from);
            return;
        }
        if (mode == 1) {
            vm.prank(from);
            ochre.approve(operator, id);
        } else if (mode == 2) {
            vm.prank(from);
            ochre.setApprovalForAll(operator, true);
        }
        vm.prank(mode == 0 ? from : operator);
        ochre.safeTransferFrom(from, to, id);
        if (mode == 2) {
            vm.prank(from);
            ochre.setApprovalForAll(operator, false);
        }
        owners[id] = to;
        --nftBalances[from];
        ++nftBalances[to];
        assertEq(ochre.ownerOf(id), to);
        assertEq(ochre.getApproved(id), address(0), "transfer retained token approval");
    }

    /// @dev Exact allowance shortfall, followed by a retry, also tests cursor rollback.
    function shortPayment(uint256 actorSeed, uint256 caveSeed) external {
        address buyer = actors[bound(actorSeed, 0, 7)];
        uint256 cave = bound(caveSeed, 1, 7);
        if (vm.getBlockTimestamp() < START + (cave - 1) * 1 days || _nextId(cave) == 737) return;
        uint256 price = _price(cave);
        vm.prank(buyer);
        coin.approve(address(ochre), price - 1);
        vm.prank(buyer);
        (bool ok,) = address(ochre).call(abi.encodeCall(ochre.buy, (cave)));
        assertFalse(ok, "purchase accepted insufficient allowance");
        assertEq(coin.allowance(buyer, address(ochre)), price - 1);
        vm.prank(buyer);
        coin.approve(address(ochre), FUNDING - spent[buyer]);
        assertTrue(_buy(buyer, cave));
    }

    function assertAccounting() external view {
        uint256 original;
        uint256 freePurchases;
        for (uint256 c = 1; c <= 7; ++c) {
            original += sales[c];
            freePurchases += releasedSales[c];
            assertEq(ochre.saleMinted(c), sales[c], "original-sale counter");
            assertLe(sales[c], saleIds[c].length);
            assertEq(ochre.frozen(c), bytes(bases[c]).length != 0);
            assertEq(ochre.frozenBase(c), bases[c], "frozen base changed");
        }
        assertEq(releasedPurchases, freePurchases);
        assertEq(ochre.totalSupply(), 2 + original + claims + reserves + freePurchases);
        assertEq(ochre.totalSupply(), issuedIds.length);
        assertLe(ochre.totalSupply(), 737);
        assertEq(ochre.seatsMinted(), claims);
        assertLe(claims, 315);
        assertEq(ochre.reserveMinted(), reserves);
        assertLe(reserves, 20);
        assertEq(ochre.unclaimedReleased(), released);
        assertEq(releasedSales[7], 0);

        uint256 balances = ochre.balanceOf(ADMIN);
        uint256 actorPayments;
        assertEq(balances, nftBalances[ADMIN]);
        for (uint256 i; i < 8; ++i) {
            address actor = actors[i];
            assertEq(ochre.balanceOf(actor), nftBalances[actor], "NFT ledger");
            balances += ochre.balanceOf(actor);
            actorPayments += spent[actor];
            assertEq(ochre.claimed(actor), didClaim[actor]);
            assertEq(coin.balanceOf(actor), FUNDING - spent[actor], "buyer debit");
            assertEq(coin.allowance(actor, address(ochre)), FUNDING - spent[actor], "allowance debit");
        }
        assertEq(balances, issuedIds.length, "NFT balance conservation");
        assertEq(actorPayments, paid);
        assertEq(coin.balanceOf(DEAD), paid, "every payment reaches dead");
        assertEq(coin.balanceOf(address(ochre)), 0, "Ochre retained payment");
        assertEq(address(ochre).balance, 0);
        assertEq(coin.balanceOf(ADMIN), 1_000_000_000 ether, "admin received payment");
        assertEq(coin.totalSupply(), 1_000_000_000 ether + 8 * FUNDING, "transfer burned ERC20 supply");
    }

    /// @dev Full enumeration once per campaign avoids 737 calls after every step.
    function assertAllOwners() external view {
        for (uint256 id; id <= 737; ++id) {
            (bool ok, bytes memory result) = address(ochre).staticcall(abi.encodeCall(ochre.ownerOf, (id)));
            if (owners[id] == address(0)) {
                assertFalse(ok, "unexpected minted id");
            } else {
                assertTrue(ok, "issued token disappeared");
                assertEq(abi.decode(result, (address)), owners[id], "owner diverged from ledger");
            }
        }
    }

    function _buy(address buyer, uint256 cave) private returns (bool) {
        if (vm.getBlockTimestamp() < START + (cave - 1) * 1 days) {
            _reject(buyer, abi.encodeCall(ochre.buy, (cave)), Ochre.NotOpen.selector);
            return false;
        }
        uint256 expectedId = _nextId(cave);
        if (expectedId == 737) {
            _reject(buyer, abi.encodeCall(ochre.buy, (cave)), Ochre.SoldOut.selector);
            return false;
        }
        uint256 price = _price(cave);
        vm.prank(buyer);
        uint256 id = ochre.buy(cave);
        assertEq(id, expectedId, "purchase allocation/order");
        if (sales[cave] < saleIds[cave].length) {
            ++sales[cave];
        } else {
            ++releasedSales[cave];
            ++releasedPurchases;
        }
        paid += price;
        spent[buyer] += price;
        _recordMint(id, buyer);
        return true;
    }

    function _nextId(uint256 cave) private view returns (uint256) {
        if (sales[cave] < saleIds[cave].length) return saleIds[cave][sales[cave]];
        if (released && cave < 7) {
            for (uint256 i; i < freeIds[cave].length; ++i) {
                if (owners[freeIds[cave][i]] == address(0)) return freeIds[cave][i];
            }
        }
        return 737;
    }

    function _price(uint256 cave) private view returns (uint256) {
        uint256 elapsed = vm.getBlockTimestamp() - (START + (cave - 1) * 1 days);
        return elapsed >= 20 hours ? 40_000 : 400_000 - 5 * elapsed;
    }

    function _recordMint(uint256 id, address to) private {
        assertLt(id, 737);
        assertEq(owners[id], address(0), "duplicate mint");
        owners[id] = to;
        ++nftBalances[to];
        issuedIds.push(id);
        assertEq(ochre.ownerOf(id), to);
    }

    function _reject(address caller, bytes memory data, bytes4 error) private {
        vm.prank(caller);
        (bool ok, bytes memory result) = address(ochre).call(data);
        assertFalse(ok, "invalid state transition succeeded");
        assertEq(result, abi.encodeWithSelector(error), "unexpected rejection reason");
    }
}

abstract contract OchreInvariantSetup is Test {
    OchreSequenceHandler internal handler;

    function setUp() public virtual {
        handler = new OchreSequenceHandler();
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.advanceTime.selector;
        selectors[1] = handler.buyBatch.selector;
        selectors[2] = handler.claim.selector;
        selectors[3] = handler.reserve.selector;
        selectors[4] = handler.release.selector;
        selectors[5] = handler.freeze.selector;
        selectors[6] = handler.transferPiece.selector;
        selectors[7] = handler.shortPayment.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function afterInvariant() public view {
        handler.assertAccounting();
        handler.assertAllOwners();
    }
}

contract OchreOpeningInvariantTest is OchreInvariantSetup {
    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allocationOwnershipAndPaymentConservation() public view {
        handler.assertAccounting();
    }

    /// @dev Pins meaningful handler coverage; random success is not a prerequisite.
    function testHandlerTransitionsReachClaimsSalesReleaseAndExhaustion() public {
        handler.buyBatch(0, 1, 1); // before opening
        handler.claim(0, false); // before opening
        handler.advanceTime(1);
        handler.claim(0, true);
        handler.claim(0, false);
        handler.claim(0, false); // replay
        handler.shortPayment(1, 1);
        handler.transferPiece(2, 2, 1); // move the seat, preserve claimed status
        handler.claim(0, false);
        handler.freeze(1, 123, false);
        handler.freeze(1, 123, true);
        handler.freeze(1, 456, true);
        handler.release(0); // too early
        vm.warp(handler.START() + 8 days);
        handler.release(7);
        handler.release(1); // duplicate release
        handler.claim(1, false); // closed
        for (uint256 c = 1; c <= 7; ++c) {
            for (uint256 i; i < 14; ++i) {
                handler.buyBatch(i % 8, c, 8);
            }
        }
        for (uint256 i; i < 6; ++i) {
            handler.reserve(i, 4, true);
        }
        handler.reserve(0, 1, false);
        handler.transferPiece(0, 4, 2);
        handler.transferPiece(1, 4, 3);
        assertEq(handler.ochre().totalSupply(), 737);
        assertEq(handler.releasedPurchases(), 314);
        afterInvariant();
    }
}

contract OchreReleasedInvariantTest is OchreInvariantSetup {
    function setUp() public override {
        super.setUp();
        vm.warp(handler.START());
        handler.claim(0, false);
        handler.claim(1, false);
        handler.transferPiece(2, 7, 0);
        vm.warp(handler.START() + 8 days);
        // Seed every sale cursor at exhaustion using real purchases and the same
        // independently checked handler; randomized calls now reach released seats.
        uint256[7] memory counts = [uint256(21), 21, 42, 63, 84, 84, 85];
        for (uint256 c = 1; c <= 7; ++c) {
            for (uint256 i; i < counts[c - 1]; ++i) {
                handler.buyBatch(i % 8, c, 1);
            }
        }
        handler.release(0);
        assertEq(handler.ochre().totalSupply(), 404);
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_releasedSeatsStayDisjointAndPaymentsConserved() public view {
        handler.assertAccounting();
    }
}
