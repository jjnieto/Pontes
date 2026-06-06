# Examples

Hands-on reference material for the Pontes DvP/PvP flow described in the
[main summary](../README.md). **Illustrative only — not audited, not affiliated with the ECB, not
for production use.**

- **[`HashLinkContract.sol`](./HashLinkContract.sol)** — a reference Hash-Link Contract (HLC) in
  Solidity for the *asset leg* on an external (EVM) market DLT: escrows an ERC-20 (e.g. tokenised
  bond units) and releases it to the Buyer or Seller on the secret Pontes discloses. Includes the
  design notes and the assumptions you must confirm against the API (notably the key-hashing
  encoding).
- **[`dvp-walkthrough.md`](./dvp-walkthrough.md)** — an end-to-end **Direct RTGS** DvP, step by
  step, interleaving the Pontes A2A API calls (`curl`) with the contract calls (`cast`). Uses the
  OpenAPI's own example values so the payment signature is verifiable.

These accompany — and deliberately echo — the [Conclusions](../README.md#7-conclusions--strengths-and-weaknesses):
the cash leg and the oracle are the Eurosystem's; the HLC on the external chain is the (regulated)
Market DLT Operator's responsibility, and its correctness is exactly the residual risk to watch.
