# Ochre — Sepolia rehearsal

Ochre is an immutable ERC-721 collection of 737 pieces of a wall painted live by workers. MockCoin is the deliberately unrestricted rehearsal currency, Pigment (`PGMT`). The project deploys exactly these two application contracts, in that order.

## Build and check

```sh
forge build
forge test
forge fmt --check
```

Foundry pins Solidity **0.8.26**, Cancun, optimization at 200 runs, and `bytecode_hash = "none"`. There is no FFI or filesystem permission configuration. OpenZeppelin Contracts 5.0.2 and forge-std 1.9.7 are vendored as ordinary source files with licenses and archive hashes in [lib/README.md](lib/README.md). With Foundry and the pinned compiler installed, building and testing need no network, installation step, environment variables, or submodules.

## Deployment parameters

[launch.json](launch.json) is the factory handoff. Its constructor arguments are static ABI words; `$contract:MockCoin` references the first deployed contract. It has no predicted or invented deployment addresses.

| Parameter | Rehearsal value |
| --- | --- |
| Network | Sepolia, chain id **11155111** |
| Deployment order | `MockCoin(address admin)`, then `Ochre(...)` |
| Coin | Address of that deployed MockCoin |
| Admin and Adam | `0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479` |
| Dead address | `0x000000000000000000000000000000000000dEaD` |
| Coin decimals | 18, statically known; Ochre never queries them |
| MockCoin initial supply | 1,000,000,000 PGMT = `1000000000000000000000000000` base units, all to admin |
| Seat root | `0x1111111111111111111111111111111111111111111111111111111111111111` |
| Start | `1791352835` = **2026-10-07 06:00:35 UTC** |
| Start price, every cave | **400000 base units** |
| Floor price, every cave | **40000 base units** |
| Price descent | 20 hours from that cave's opening |
| Release eligibility | `1792044035` = **2026-10-15 06:00:35 UTC** |
| Labels, caves 1–7 | `zto-cave-test5`, `zto-cave-test4`, `zto-cave-test3`, `zto-cave-test2`, `zto-cave-test5`, `zto-cave-test4`, `zto-cave-test3` |

Prices follow the brief's **base-unit** wording literally: 400000 units means 0.0000000000004 PGMT; 40000 means 0.00000000000004 PGMT. They are not multiplied by `10**18`. Initial MockCoin supply is expressed in whole PGMT and is multiplied by `10**18`.

Ochre's constructor argument order is `coin, admin, adam, seatRoot, startTime, label1, label2, label3, label4, label5, label6, label7`. Each label is a nonempty ASCII `bytes32`, right-padded with zero bytes, up to 32 bytes. Coin/admin/Adam must be nonzero. The dead address, prices, supply, and durations are compiled constants. The constructor makes no external calls, does not inspect coin code or decimals, and uses ordinary ERC-721 minting for Zero and One, without receiver callbacks. Consequently the deployer must check dependency addresses and recipient capabilities.

[script/Deploy.s.sol](script/Deploy.s.sol) duplicates the exact manifest configuration for local simulation. `run()` accepts only Sepolia's chain id, reads no environment, and never starts broadcasting. The tests invoke it directly from an unrelated caller to verify that a factory or script caller receives no control or initial tokens. For a local dry run:

```sh
forge script script/Deploy.s.sol:Deploy --chain-id 11155111
```

No on-chain transaction has been submitted by this assignment. The authorized deployment service must select Sepolia, resolve the manifest reference, deploy with zero ETH, and publish the confirmed addresses and receipts. Ochre itself is chain-independent to support empty-EVM verification; the deployment service must enforce the target network.

## Pieces and allocation

The constructor mints **id 0 (Zero) to Adam** and **id 736 (One) to admin**. For ids 1–735:

```text
cave  = (id - 1) / 105 + 1
round = ((id - 1) % 105) / 5 + 1
slot  = (id - 1) % 5 + 1
```

There are seven caves, 21 rounds per cave, and five slots per round. Slots 1–4 are lines; slot 5 is the gathering. `piece(id)` and `pieceId(cave, round, slot)` expose this arithmetic. `piece(0)` is `(1,0,0)` and `piece(736)` is `(7,0,0)`; endpoints have no round or slot. No NFT burn or general-purpose mint function exists.

| Cave | Sale slots in a normal round | Original sale pieces | Seat pieces | Admin reserve |
| --- | --- | ---: | ---: | ---: |
| 1 | 5 | 21 | 84 | 0 |
| 2 | 5 | 21 | 84 | 0 |
| 3 | 4, 5 | 42 | 63 | 0 |
| 4 | 3, 4, 5 | 63 | 42 | 0 |
| 5 | 2, 3, 4, 5 | 84 | 21 | 0 |
| 6 | 2, 3, 4, 5 | 84 | 21 | 0 |
| 7 | 2, 3, 4, 5; all five in round 21 | 85 | 0 | 20 |
| Total | | **400** | **315** | **20** |

**Ordering interpretation:** the priority `5,4,3,2,1` selects which slots are sale pieces. `buy` then allocates those selected pieces in ascending token-id order, consistent with “in id order” in the brief. Cave 3 therefore starts `214,215,219,220`; cave 7's last round sells `731,732,733,734,735`. Cave 7's reserve is `631,636,…,726`.

## Buying, seats, and release

`buy(cave)` opens at `startTime + (cave - 1) * 1 day`, inclusive, and remains available while pieces remain. There is no wallet limit, chosen token id, randomness, or owner-controlled price. The price is:

```text
before/opening: startPrice
0 < elapsed < 72000: startPrice - (startPrice - floorPrice) * elapsed / 72000
elapsed >= 72000: floorPrice
```

`priceNow(cave)` quotes the starting price before opening, but buying reverts then. The rehearsal prices decline by exactly five base units each second, so there is no fractional rounding error. Buyers first call `MockCoin.approve(ochre, amount)`; approving the current price is sufficient for one purchase since the price cannot increase. MockCoin's public `mint(to, amount)` lets any rehearsal wallet obtain currency.

Payment is exactly `coin.transferFrom(buyer, dead, price)`, requiring a returned `true`, followed by safe minting to the buyer and `Bought(id,buyer,price)`. Ochre never pulls payment into itself and never approves another spender. Transferring PGMT to the dead address does **not** reduce ERC-20 `totalSupply`. No-return, false-return, or reverting coins fail; arbitrary fee-on-transfer/rebasing currencies are outside this fixed MockCoin deployment's assumptions.

`claimSeat(proof)` is free from `startTime`, inclusive. Leaves are **single** `keccak256(abi.encodePacked(wallet))` hashes of exactly 20 address bytes, with sorted hash pairs at every proof step. They are not double-hashed ABI-encoded leaves. A valid wallet can claim once, even if it later transfers its NFT. Claims take free pieces across caves 1–6 in ascending id order, without waiting for those caves' sale openings, and emit `Claimed(id,wallet)`.

The rehearsal root is a placeholder: **no valid seat list or proofs have been supplied for it**. Tests deploy separate instances with actual Merkle roots to exercise claims. The immutable root cannot be replaced after deployment; rehearsing successful claims on a publicly deployed instance requires an explicitly revised root and deployment configuration before launching that instance. A real seat list must deduplicate wallets, use the specified leaf and pair encoding, and publish proofs.

`mintReserve(to)` is restricted to the fixed admin, has no opening-time restriction, and safely mints the next of the 20 cave-7 free pieces. It emits `ReserveMinted(id,to)`. Zero recipients and contracts that reject ERC-721 receipt revert without consuming inventory.

Anyone may call `releaseUnclaimed()` at or after `startTime + 8 days`; it is a one-time explicit transition and emits `UnclaimedReleased()`. **Release closes seat claims.** Passing the timestamp alone does not close them or release inventory. After release, `buy(c)` exhausts that cave's remaining original sale pieces first, then sells its still-unclaimed seats in ascending id order at the floor. Already claimed pieces remain excluded even if transferred. Cave 7's reserve is never released. This resolves the brief's unspecified post-release claim policy by treating release as the end of the seat allocation period.

Minting uses checks and inventory updates before external interactions, plus a reentrancy guard on purchase, claim, reserve, and release. Payment or receiver failures revert the entire operation, including coin balances, allowances, counters, and claim status. Contract recipients of post-deployment mints must implement `onERC721Received`.

## Metadata and admin responsibilities

Before freezing, a piece's URI is:

```text
https://<cave-label>.sites.imd.fun/line-<slot>/<two-digit-round>.json
https://<cave-label>.sites.imd.fun/gathering/<two-digit-round>.json
https://<cave-1-label>.sites.imd.fun/zero.json
https://<cave-7-label>.sites.imd.fun/one.json
```

For example, id 214 uses `https://zto-cave-test3.sites.imd.fun/line-4/01.json`. `tokenURI` rejects unminted/nonexistent ids.

The fixed admin can call `freeze(cave, base)` once per cave, before or after minting, to replace the HTTP prefix permanently. A base must be nonempty and end with `/`, e.g. `ipfs://<cid>/`; the contract concatenates the same path suffix. It emits `Frozen(cave,base)`. Freezing cave 1 also affects Zero, and freezing cave 7 affects One. Freeze changes the prefix for future tokens too.

The admin must validate and publish all JSON and media, check the exact suffix layout, arrange persistent storage/pinning, and verify each base before freezing. A fixed HTTP base does not freeze the server's contents; only a content-addressed base with available content gives the intended content permanence. The contract cannot verify hosting, content correctness, CID availability, or the physical wall's creation, custody, delivery, or ownership rights.

Admin has only the reserve and one-time metadata powers. These privileges cannot be transferred or renounced; loss of that key leaves remaining reserve/freeze actions inaccessible. There is no Ownable API, proxy, upgrade, pause, royalty/ERC-2981 interface, withdrawal, or rescue function. Standard ERC-721 approvals and transfers are supported; ERC-721 enumeration is not advertised, although `totalSupply()` is available.

Normal operations hold no payment funds or ETH. Unsolicited ERC-20 transfers or forced ETH cannot generally be prevented by a recipient; assets sent directly to Ochre are unrecoverable. This limitation does not create any coin-moving function beyond the specified buyer-to-dead transfer. Transaction ordering can change which next piece a buyer or claimant receives; the API does not promise a caller-selected id.

## Validation and release responsibilities

The delivered tests exhaustively cover arithmetic and allocation, both complete 737-piece issuance routes, sale exhaustion and ordering, all 315 valid seat claims, proof failures and replay, payment accounting, timestamps and fuzzed prices, reserve limits, release, every URI before/after freeze, ERC-721 transfers and receiver behavior, events, constructor configuration, runtime limits, and forbidden runtime opcodes. Adversarial tests exercise false/reverting/missing-return coins, reentrancy, and transaction rollback. The deployment test calls the static rehearsal configuration directly without environment access.

[SECURITY.md](SECURITY.md) records the local review and trust limits. Tests and a local review do not constitute an independent security audit. Before release, an independent reviewer should assess the final sources and manifest, and the deployer should verify chain, timestamps, the intended price units, constructor recipients, root, labels, and confirmed bytecode. Explorer verification and publication of deployed addresses remain deployment-service responsibilities. No keys or funded wallet are included or accessed.
