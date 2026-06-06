# DvP walk-through — Direct RTGS settlement, end to end

A concrete, copy-pasteable example of settling a **Delivery-versus-Payment** through Pontes using
the **Direct RTGS** model (the trigger into T2 — no cash tokens). It interleaves the **Pontes A2A
API calls** (`curl`) with the **asset-leg smart-contract calls** (`cast`, from
[Foundry](https://book.getfoundry.sh/)) against the reference
[`HashLinkContract.sol`](./HashLinkContract.sol).

Step numbers match the sequence diagram in the main [README §4](../README.md#4-how-cross-ledger-dvppvp-works-the-hash-link-protocol).

> **Illustrative only.** Field names and the signing recipe are taken from the official OpenAPI
> (`EII API`, Direct RTGS XvP). Hosts, credentials, keys, addresses and the bond token are made up.
> Values marked *(example)* are reproduced verbatim from the spec so the signature below is
> verifiable; everything else is a placeholder.

## Scenario

| Thing | Value |
|------|-------|
| NCB realm (`{ncb}`) | `BDE` |
| Seller (delivers the bond, receives the cash) | BIC `BEUMFXB1XX2` |
| Buyer (receives the bond, pays the cash) | BIC `BEUMFXB1XXX` |
| Market DLT Operator (responsible for the asset leg) | `MDLTO-EXAMPLE-01` (whitelisted with both) |
| Asset | `ACME 4.00% 2030` bond units — an ERC-20 on an external market DLT |
| Units delivered | `10000` bond-unit tokens |
| Cash leg | `10000.50 EUR` |

Shell variables used below:

```bash
PONTES="https://<eii-host>"          # $URL_PLACEHOLDER$ in the spec
NCB="BDE"
RPC="https://<market-dlt-rpc>"       # the external chain's JSON-RPC (can be public, e.g. Ethereum)
```

---

## Step 0 — Authenticate (OAuth2, per-NCB realm)

Every endpoint needs a JWT from the NCB's realm (OAuth2 *password* / A2A flow).

```bash
ACCESS_TOKEN=$(curl -s -X POST \
  "$PONTES/iam/realms/$NCB/protocol/openid-connect/token" \
  -d grant_type=password \
  -d client_id="<a2a-client-id-for-your-profile>" \
  -d username="<a2a-user>" \
  -d password="<a2a-secret>" \
  -d scope=openid | jq -r .access_token)
```

---

## Step 1 — Seller initialises the DvP on Pontes

`POST /igw/{ncb}/v1/direct-rtgs/xvps` (one-step). The Seller declares the counterpart and the
Market DLT Operator responsible for the asset leg.

```bash
curl -s -X POST "$PONTES/igw/$NCB/v1/direct-rtgs/xvps" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "seller": { "bic": "BEUMFXB1XX2", "marketDLTOperator": "MDLTO-EXAMPLE-01" },
    "buyer":  { "bic": "BEUMFXB1XXX" },
    "amount": "10000.50",
    "currency": "EUR",
    "type": "DVP"
  }'
```

### Step 2 — Pontes responds with the Hash-Link parameters

```json
{
  "xvpTransactionId": "517ae232-29e7-4efb-8743-0177bbe6d577",
  "executionHash":    "c5a626829fca9b1a4dfb1495966cafaf6894f937bc32e5536c1e64318951f2bb",
  "cancellationHash": "a1b2c3d4e5f6079889aabbccddeeff00112233445566778899aabbccddeeff00",
  "timeout":          "2025-12-04T09:51:41Z",
  "seller": { "bic": "BEUMFXB1XX2", "marketDLTOperator": "MDLTO-EXAMPLE-01" },
  "buyer":  { "bic": "BEUMFXB1XXX" },
  "amount": "10000.50",
  "currency": "EUR",
  "type": "DVP"
}
```

`executionHash = SHA256(executionKey)` and `cancellationHash = SHA256(cancellationKey)`. Pontes
keeps both secrets and will reveal exactly one later. `timeout` is creation time + 30 min.

---

## Step 3 — Seller deploys the HLC and locks the bond (on the market DLT)

The Seller now escrows the asset on the external chain, parameterising the
[`HashLinkContract`](./HashLinkContract.sol) with the two hashes from step 2. `deadline` is the
`timeout` as a unix timestamp (`2025-12-04T09:51:41Z` → `1764841901`).

```bash
# Deploy (constructor: seller, buyer, asset, units, executionHash, cancellationHash, dvpId, deadline)
HLC=$(cast send --rpc-url $RPC --private-key $SELLER_PK --json \
  --create "$(forge inspect HashLinkContract bytecode)" \
  "constructor(address,address,address,uint256,bytes32,bytes32,string,uint256)" \
  $SELLER_ADDR $BUYER_ADDR $BOND_TOKEN 10000 \
  0xc5a626829fca9b1a4dfb1495966cafaf6894f937bc32e5536c1e64318951f2bb \
  0xa1b2c3d4e5f6079889aabbccddeeff00112233445566778899aabbccddeeff00 \
  "517ae232-29e7-4efb-8743-0177bbe6d577" 1764841901 | jq -r .contractAddress)

# Approve and lock the 10000 bond units into the HLC
cast send --rpc-url $RPC --private-key $SELLER_PK $BOND_TOKEN "approve(address,uint256)" $HLC 10000
cast send --rpc-url $RPC --private-key $SELLER_PK $HLC "lock()"
```

### Step 4 — Seller notifies the Buyer (off-chain)

The Seller tells the Buyer the `xvpTransactionId` and the HLC address (email, message bus, a chain
event — outside Pontes).

---

## Step 5 — Buyer verifies, then pays

First the Buyer reads the DvP back from Pontes and checks it against the on-chain HLC (same hashes,
amount, parties) — `GET /igw/{ncb}/v1/direct-rtgs/xvps/{id}`:

```bash
curl -s "$PONTES/igw/$NCB/v1/direct-rtgs/xvps/517ae232-29e7-4efb-8743-0177bbe6d577" \
  -H "Authorization: Bearer $ACCESS_TOKEN"   # returns the same object as step 2
```

### Step 6 — Buyer pays the cash leg (signed)

The Direct RTGS payment must be **signed** (non-repudiation). Per the spec, the signed string is
`xvpTransactionId`(transformed) + `amount` + `buyer bic` + `seller bic`, concatenated with no
separators, then SHA-256, then signed with **SHA256withECDSA**, base64-encoded.

```bash
# 1) transform the id: drop the dashes, prefix "xvp"
#    517ae232-29e7-4efb-8743-0177bbe6d577 -> xvp517ae23229e74efb87430177bbe6d577
PAYLOAD='xvp517ae23229e74efb87430177bbe6d57710000.50BEUMFXB1XXXBEUMFXB1XX2'

# 2) SHA-256 of that string (example value from the spec):
#    a7e717ea9fae0d970d60b47397858084e7659dc29a426b53eb04ef35c40a399c

# 3) sign (sha256 + ECDSA in one step) with the user's EC private key, base64 the DER signature
SIGNATURE=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -sign buyer_privkey.pem | openssl base64 -A)

# 4) the signer certificate, base64-encoded
SIGNER_PEM=$(openssl base64 -A -in buyer_cert.pem)
```

`POST /igw/{ncb}/v1/direct-rtgs/xvps/{id}/payment` — note the Buyer now declares the
`marketDLTOperator`:

```bash
curl -s -X POST \
  "$PONTES/igw/$NCB/v1/direct-rtgs/xvps/517ae232-29e7-4efb-8743-0177bbe6d577/payment" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"buyer\":  { \"bic\": \"BEUMFXB1XXX\", \"marketDLTOperator\": \"MDLTO-EXAMPLE-01\" },
    \"seller\": { \"bic\": \"BEUMFXB1XX2\" },
    \"amount\": \"10000.50\",
    \"currency\": \"EUR\",
    \"signature\": \"$SIGNATURE\",
    \"signerPEM\": \"$SIGNER_PEM\"
  }"
```

### Step 7 — Pontes settles in T2 and returns the Execution Key

Pontes triggers the real-time gross settlement in T2 (`pacs.010` debit Buyer → `pacs.009` credit
Seller). On success the payment is `SETTLED` and the response carries the **Execution Key**:

```json
{
  "xvpTransactionId": "517ae232-29e7-4efb-8743-0177bbe6d577",
  "payment": { "id": "9d1f...", "status": "SETTLED", "reason": null },
  "executionKey": "f9cb6cdb6ce24ee3a5fd5e698bd895eb2f8ec312448b4f0d85865dfc72e32186",
  "cancellationKey": null
}
```

The cash is now final in central bank money. The Seller has the euro; the Buyer holds the key to
the bond.

---

## Step 9 — Buyer claims the bond on the market DLT

With the Execution Key, the Buyer calls `forcedExecute` on the HLC (no need to trust the Seller):

```bash
# ⚠️ encoding caveat (see HashLinkContract.sol): pass the key as the EXACT bytes Pontes hashed.
# If Pontes hashed the ASCII hex string:
cast send --rpc-url $RPC --private-key $BUYER_PK $HLC "forcedExecute(bytes)" \
  $(cast from-utf8 f9cb6cdb6ce24ee3a5fd5e698bd895eb2f8ec312448b4f0d85865dfc72e32186)
# If Pontes hashed the decoded bytes instead, pass: 0xf9cb6cdb...e32186
```

The HLC checks `sha256(key) == executionHash` and transfers the 10000 bond units to the Buyer.
**Done:** Buyer has the bond, Seller has the cash. (Alternatively the Seller could have called
`cooperativeExecute()` once it saw `SETTLED`.)

---

## Unhappy path — no payment or no funds → asset returned to the Seller

If the Buyer never pays before `timeout`, Pontes marks the payment `BURNED`; if it pays without
funds, `UNSETTLED`. Either way Pontes now releases the **Cancellation Key** to the Seller via the
Get-Key endpoint (`?key=CANCELLATION`):

```bash
curl -s "$PONTES/igw/$NCB/v1/direct-rtgs/xvps/517ae232-29e7-4efb-8743-0177bbe6d577/payment?key=CANCELLATION" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
# -> { "payment": { "status": "BURNED" }, "executionKey": null,
#      "cancellationKey": "e3a5...c312" }
```

```bash
# Step 9 (mirror): Seller reclaims the bond with the Cancellation Key
cast send --rpc-url $RPC --private-key $SELLER_PK $HLC "forcedCancel(bytes)" \
  $(cast from-utf8 e3a5fd5e698bd895eb2f8ec312448b4f0d85865dfc72e32186f9cb6cdb6ce24ee3)
```

The Buyer never received an Execution Key (the cash never settled), so it can never take the bond —
and the Seller gets it back. All-or-none holds, arbitrated by Pontes as the oracle.

---

## Endpoint ↔ step cheat-sheet

| Step | Who | Pontes endpoint | Contract call |
|:----:|-----|-----------------|---------------|
| 1 | Seller | `POST /igw/{ncb}/v1/direct-rtgs/xvps` | — |
| 3 | Seller | — | `lock()` |
| 5 | Buyer | `GET /igw/{ncb}/v1/direct-rtgs/xvps/{id}` | (verify) |
| 6 | Buyer | `POST /igw/{ncb}/v1/direct-rtgs/xvps/{id}/payment` | — |
| 8 | Seller/Buyer | `GET /igw/{ncb}/v1/direct-rtgs/xvps/{id}/payment?key={EXECUTION\|CANCELLATION}` | — |
| 9 | Buyer / Seller | — | `forcedExecute(bytes)` / `forcedCancel(bytes)` (or `cooperative*`) |
