// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice 737 pieces of a live wall, with fixed auctions, seats, and an admin reserve.
contract Ochre is ERC721, ReentrancyGuard {
    uint256 public constant MAX_SUPPLY = 737;
    uint8 public constant COIN_DECIMALS = 18;
    uint256 public constant START_PRICE = 400_000;
    uint256 public constant floorPrice = 40_000;
    uint256 public constant PRICE_DURATION = 20 hours;
    address public constant dead = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable coin;
    address public immutable admin;
    address public immutable adam;
    bytes32 public immutable seatRoot;
    uint256 public immutable startTime;

    // Cave-indexed storage is 1-based, matching the public interface.
    mapping(uint256 => bytes32) public labels;
    mapping(uint256 => bool) public frozen;
    mapping(uint256 => string) public frozenBase;
    mapping(address => bool) public claimed;
    mapping(uint256 => uint256) public saleMinted;
    uint256 public seatsMinted;
    uint256 public reserveMinted;
    uint256 public totalSupply;
    bool public unclaimedReleased;

    mapping(uint256 => uint256) private saleCursor;
    mapping(uint256 => uint256) private releasedCursor;
    uint256 private seatCursor = 1;

    event Bought(uint256 indexed id, address indexed buyer, uint256 price);
    event Claimed(uint256 indexed id, address indexed wallet);
    event ReserveMinted(uint256 indexed id, address indexed to);
    event UnclaimedReleased();
    event Frozen(uint256 indexed cave, string base);

    error InvalidConfiguration();
    error InvalidCave();
    error InvalidPiece();
    error NotOpen();
    error SoldOut();
    error PaymentFailed();
    error OnlyAdmin();
    error InvalidProof();
    error AlreadyClaimed();
    error SeatsClosed();
    error ReserveExhausted();
    error TooEarly();
    error AlreadyReleased();
    error AlreadyFrozen();
    error InvalidBase();

    /// @dev Static constructor arguments only. No coin reads or receiver callbacks occur here.
    constructor(
        address coin_,
        address admin_,
        address adam_,
        bytes32 seatRoot_,
        uint256 startTime_,
        bytes32 label1,
        bytes32 label2,
        bytes32 label3,
        bytes32 label4,
        bytes32 label5,
        bytes32 label6,
        bytes32 label7
    ) ERC721("Ochre", "OCHRE") {
        if (
            coin_ == address(0) || admin_ == address(0) || adam_ == address(0)
                || startTime_ > type(uint256).max - 8 days
        ) revert InvalidConfiguration();
        coin = IERC20(coin_);
        admin = admin_;
        adam = adam_;
        seatRoot = seatRoot_;
        startTime = startTime_;
        bytes32[7] memory initialLabels = [label1, label2, label3, label4, label5, label6, label7];
        for (uint256 i; i < 7; ++i) {
            _validateLabel(initialLabels[i]);
            labels[i + 1] = initialLabels[i];
        }
        _mint(adam_, 0);
        _mint(admin_, 736);
        totalSupply = 2;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    function caveOpen(uint256 cave) public view returns (uint256) {
        _validateCave(cave);
        return startTime + (cave - 1) * 1 days;
    }

    function startPrice(uint256 cave) public pure returns (uint256) {
        _validateCave(cave);
        return START_PRICE;
    }

    /// @notice Before a cave opens, quotes its starting price; buying is still disabled.
    function priceNow(uint256 cave) public view returns (uint256) {
        uint256 opens = caveOpen(cave);
        if (block.timestamp <= opens) return START_PRICE;
        uint256 elapsed = block.timestamp - opens;
        if (elapsed >= PRICE_DURATION) return floorPrice;
        return START_PRICE - (START_PRICE - floorPrice) * elapsed / PRICE_DURATION;
    }

    /// @notice Endpoint pieces use round = slot = 0, and belong to caves 1 and 7.
    function piece(uint256 id) public pure returns (uint256 cave, uint256 round, uint256 slot) {
        if (id >= MAX_SUPPLY) revert InvalidPiece();
        if (id == 0) return (1, 0, 0);
        if (id == 736) return (7, 0, 0);
        uint256 offset = id - 1;
        return (offset / 105 + 1, (offset % 105) / 5 + 1, offset % 5 + 1);
    }

    function pieceId(uint256 cave, uint256 round, uint256 slot) public pure returns (uint256) {
        _validateCave(cave);
        if (round == 0 || round > 21 || slot == 0 || slot > 5) revert InvalidPiece();
        return (cave - 1) * 105 + (round - 1) * 5 + slot;
    }

    function saleSlots(uint256 cave, uint256 round) public pure returns (uint256) {
        _validateCave(cave);
        if (round == 0 || round > 21) revert InvalidPiece();
        if (cave <= 2) return 1;
        if (cave == 3) return 2;
        if (cave == 4) return 3;
        if (cave == 7 && round == 21) return 5;
        return 4;
    }

    function saleCount(uint256 cave) public pure returns (uint256) {
        return 20 * saleSlots(cave, 1) + saleSlots(cave, 21);
    }

    /// @notice Original allocation; released seats are not reclassified as original sale pieces.
    function isSalePiece(uint256 id) public pure returns (bool) {
        (uint256 cave, uint256 round, uint256 slot) = piece(id);
        return slot != 0 && slot > 5 - saleSlots(cave, round);
    }

    function buy(uint256 cave) external nonReentrant returns (uint256 id) {
        if (block.timestamp < caveOpen(cave)) revert NotOpen();
        uint256 price;
        uint256 offset = saleCursor[cave];
        uint256 first = (cave - 1) * 105 + 1;
        while (offset < 105 && !isSalePiece(first + offset)) ++offset;
        if (offset < 105) {
            id = first + offset;
            saleCursor[cave] = offset + 1;
            ++saleMinted[cave];
            price = priceNow(cave);
        } else {
            if (!unclaimedReleased || cave == 7) revert SoldOut();
            offset = releasedCursor[cave];
            while (offset < 105 && (isSalePiece(first + offset) || _ownerOf(first + offset) != address(0))) {
                ++offset;
            }
            if (offset == 105) revert SoldOut();
            id = first + offset;
            releasedCursor[cave] = offset + 1;
            price = floorPrice;
        }
        // Deliberately require a bool: the configured rehearsal currency is a plain ERC-20.
        if (!coin.transferFrom(msg.sender, dead, price)) revert PaymentFailed();
        _issue(msg.sender, id);
        emit Bought(id, msg.sender, price);
    }

    function claimSeat(bytes32[] calldata proof) external nonReentrant returns (uint256 id) {
        if (block.timestamp < startTime) revert NotOpen();
        if (unclaimedReleased || seatsMinted == 315) revert SeatsClosed();
        if (claimed[msg.sender]) revert AlreadyClaimed();
        if (!MerkleProof.verifyCalldata(proof, seatRoot, keccak256(abi.encodePacked(msg.sender)))) {
            revert InvalidProof();
        }
        id = seatCursor;
        while (id <= 630 && isSalePiece(id)) ++id;
        if (id > 630) revert SeatsClosed();
        seatCursor = id + 1;
        claimed[msg.sender] = true;
        ++seatsMinted;
        _issue(msg.sender, id);
        emit Claimed(id, msg.sender);
    }

    /// @notice Reserve has no opening-time restriction and is never released to the sale.
    function mintReserve(address to) external onlyAdmin nonReentrant returns (uint256 id) {
        if (reserveMinted == 20) revert ReserveExhausted();
        id = 631 + 5 * reserveMinted;
        ++reserveMinted;
        _issue(to, id);
        emit ReserveMinted(id, to);
    }

    /// @notice Closes seat claims and makes the remaining seats purchasable, once explicitly called.
    function releaseUnclaimed() external nonReentrant {
        if (block.timestamp < startTime + 8 days) revert TooEarly();
        if (unclaimedReleased) revert AlreadyReleased();
        unclaimedReleased = true;
        emit UnclaimedReleased();
    }

    /// @param base Complete URI prefix including its trailing slash.
    function freeze(uint256 cave, string calldata base) external onlyAdmin {
        _validateCave(cave);
        if (frozen[cave]) revert AlreadyFrozen();
        bytes memory raw = bytes(base);
        if (raw.length == 0 || raw[raw.length - 1] != bytes1("/")) revert InvalidBase();
        frozen[cave] = true;
        frozenBase[cave] = base;
        emit Frozen(cave, base);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        (uint256 cave, uint256 round, uint256 slot) = piece(id);
        string memory base =
            frozen[cave] ? frozenBase[cave] : string.concat("https://", _labelString(labels[cave]), ".sites.imd.fun/");
        if (id == 0) return string.concat(base, "zero.json");
        if (id == 736) return string.concat(base, "one.json");
        string memory path = slot == 5 ? "gathering/" : string.concat("line-", Strings.toString(slot), "/");
        string memory roundString = round < 10 ? string.concat("0", Strings.toString(round)) : Strings.toString(round);
        return string.concat(base, path, roundString, ".json");
    }

    function _issue(address to, uint256 id) private {
        // Defense in depth: all issue paths must remain within the fixed collection.
        if (id == 0 || id >= 736 || totalSupply >= MAX_SUPPLY) revert InvalidPiece();
        ++totalSupply;
        _safeMint(to, id);
    }

    function _validateCave(uint256 cave) private pure {
        if (cave == 0 || cave > 7) revert InvalidCave();
    }

    function _validateLabel(bytes32 label) private pure {
        if (label == bytes32(0)) revert InvalidConfiguration();
        bool ended;
        for (uint256 i; i < 32; ++i) {
            bytes1 char = label[i];
            if (char == 0) ended = true;
            else if (ended || uint8(char) > 127) revert InvalidConfiguration();
        }
    }

    function _labelString(bytes32 label) private pure returns (string memory) {
        uint256 length;
        while (length < 32 && label[length] != 0) ++length;
        bytes memory value = new bytes(length);
        for (uint256 i; i < length; ++i) {
            value[i] = label[i];
        }
        return string(value);
    }
}
