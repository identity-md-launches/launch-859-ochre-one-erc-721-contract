# Local review record

Scope: `src/MockCoin.sol`, `src/Ochre.sol`, the static deployment configuration, and delivered tests. The supplied pinned security reference was read as background; the task's explicit currency and constructor requirements control.

| Area | Implementation and evidence |
| --- | --- |
| Token standards | Vendored OpenZeppelin ERC-20/ERC-721 5.0.2, including metadata, approvals, and receiver checks. Interface, transfer, and rejection tests pass. See the [ERC-721 specification](https://eips.ethereum.org/EIPS/eip-721) and [OpenZeppelin API](https://docs.openzeppelin.com/contracts/5.x/api/token/erc721). |
| Constructor calls | Fixed decimals and ordinary `_mint` for endpoints. A test deploys with an address containing no coin code and non-receiver endpoint recipients. Deployment parameters, recipients, and dependency code must be checked by the deployment service. |
| Permissions | Fixed explicit admin grants only reserve minting and one freeze per cave. Unauthorized cases tested. No inherited ownership, pause, upgrade, withdrawal, or configurable sink. |
| Supply/allocation | Disjoint original sale, seat, reserve, and endpoint domains. Bounded cursors, no NFT burn, guarded issuance. Complete sale/claim/reserve and sale/release/reserve routes both reach exactly 737. |
| Payments | Strict returned bool is intentional for the specified MockCoin. Only buyer-to-dead `transferFrom`. No payment approval or outbound transfer method in Ochre. Balances, allowance rollback, dead receipts, and unchanged ERC-20 supply tested. |
| Reentrancy | OpenZeppelin storage guard covers all allocation entry points and release. Counters are committed before calls; failed calls revert them. Malicious coin and receiver callbacks are tested. Standard NFT transfers remain composable. |
| Merkle seats | Caller-bound packed-address leaves, sorted pairs, wallet claim flags independent of token ownership. Multi-level proofs, 315 claims, excess claims, transferred claims, and failures tested. No claims after explicit release. |
| Time/price | Timestamp-based opening and monotonic price are intentional mechanics, not randomness. Price line, endpoints, long delays, cave-specific openings, and release threshold tested. No oracle dependency. |
| Metadata | ASCII zero-padded labels and valid cave indices checked. One-time freeze authorization and trailing slash checked. Every numbered URI tested. Admin content selection and external availability remain trust assumptions. |
| Deployment | Static manifest words, explicit beneficiaries rather than factory caller, chain-checked dry-run helper. Tests check EIP-170 runtime and EIP-3860 init-code sizes and disassemble runtime to reject DELEGATECALL, CALLCODE, SELFDESTRUCT, matching the supplied protected probe's checks. |

Tools run locally: pinned-solc Foundry build, unit/fuzz tests, formatting check, and runtime opcode scan in tests. Slither and Mythril were not run. No independent audit, RPC deployment, explorer verification, hosting verification, or seat-root provenance verification was performed.

Foundry's heuristic linter flags ordinary `_mint` in the constructor, timestamp comparisons, external coin/receiver calls, and event emissions after those calls. The constructor exception is required to avoid external calls; the time comparisons implement the schedule; allocation callbacks are guarded and tested. These patterns are reviewed limitations, not a claim that automated warnings establish exploitability or safety.

MockCoin is permissionlessly inflationary and unsuitable as a scarce payment asset. The rehearsal seat root is a placeholder and prices are tiny literal base-unit amounts. There is no upgrade or recovery path: incorrect deployment configuration needs a new deployment. Direct token donations/forced ETH can be stranded. Losing admin control prevents remaining reserve/freeze operations. Users depend on off-chain content availability and separate arrangements for any physical-world rights.
