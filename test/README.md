# Ochre test coverage

Run `forge build` and `forge test`. All dependencies are already vendored in `lib/`;
these additions need no network, RPC, environment changes, or extra configuration.
The existing unit and adversarial suites remain intact.

## Rules checked

- Exactly 737 NFTs: two constructor endpoints, 400 original sales, 315 seats, and
  20 cave-7 reserve pieces. Cave sales total 21, 21, 42, 63, 84, 84, and 85.
- Seven daily openings; prices decrease by five base units per second for 20 hours,
  from 400000 to 40000. The prices are literal base units of the 18-decimal coin.
- Purchases debit the buyer and send the same amount directly to dead. Failed
  payments preserve allocation and allowance. Dead transfers do not burn ERC-20 supply.
- Seats require caller-bound sorted Merkle proofs and are claimable once per wallet.
  Transferring a claimed NFT does not reset eligibility or release that NFT for sale.
- Explicit release is available at `startTime + 8 days`, closes claims, and sells
  remaining seats only after original sales. Cave-7 reserves stay with the admin.
- Reserve and freeze permissions stay with the configured admin. Freeze is permanent
  per cave. ERC-721 transfers preserve supply and clear token approvals.
- Existing tests exhaustively check piece arithmetic, allocation, URI construction,
  interfaces, event examples, reentrancy, rejected receivers, and static deployment.

## Added campaigns

| File | What it adds |
| --- | --- |
| `OchreInvariant.t.sol` | Two random-sequence campaigns: before opening, and after all 400 original sales. Each runs 128 sequences of 128 calls, using eight seat wallets and the rehearsal admin. |
| `MockCoinInvariant.t.sol` | 256 sequences of 128 calls mixing permissionless mint, transfer, approval, allowance spending, and invalid calls. Also pins full-width supply, overflow rollback, self-transfer, and finite/infinite allowances. |
| `BoundaryProperties.t.sol` | Random partial claims followed by complete release/sellout; pinned cave seat boundaries; exact purchase payments/events at randomized times; invalid full-width inputs; maximum accepted start timestamp. |

Ochre's handler keeps an independent ownership ledger and builds allocation lists
from the specified slot masks, without reading the contract's allocation helpers.
After every random action it checks supply, balances, claim flags, allocation counters,
freeze/release state, allowances, and all payments. Each mint/transfer checks the
affected owner; a full ownership scan also runs after every sequence. The second
campaign purchases all original inventory during setup so released-seat paths are
reachable immediately. Deterministic handler tests also reach every main lifecycle
transition and full collection exhaustion.

The coin handler independently tracks every balance, approval, and minted unit.
The dead address receives coins but is never impersonated as a spender. Expected
rejections are checked inside the handlers; `fail-on-revert = true` makes unexpected
handler failures fail the campaign. Run counts are inline in the test source.

## Limits and interpretations

The rehearsal root is a placeholder with no supplied proofs. Successful claim tests
therefore deploy separate instances with real sorted Merkle trees; they do not modify
the configured root or contract storage. The random Ochre handlers use eight seat
wallets; exhaustive existing tests and new partial-release tests cover all 315 seats.

Sale-slot priority selects membership; purchases follow ascending token ids, matching
the brief's “in id order.” Release is treated as closing seat claims, as in the existing
implementation. These tests do not settle alternate interpretations of those rules.

The zero-custody invariant applies to protocol operations with the specified MockCoin.
It does not claim to prevent unsolicited ERC-20 donations or forced ETH. Permissionless
MockCoin minting is intentional, so its supply is compared with modeled mints rather
than asserted constant. Stateful amounts are bounded for throughput; explicit tests
exercise `uint256` supply and timestamp limits.

This is local EVM testing, with no Sepolia broadcast, live metadata/content verification,
seat-list provenance check, or guarantee about the physical wall. The supplied Pashov
fizz and Trail of Bits property-testing references informed the conservation, state
transition, and anti-vacuity checks; no framework templates or external code were added.
