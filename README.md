# Pontes — Executive Summary

> **Unofficial summary.** This document is an independent, plain-language overview of the
> Eurosystem's **Pontes** initiative, written for orientation purposes. It is **not** an
> official European Central Bank (ECB) publication and is not affiliated with or endorsed by
> the ECB or the Eurosystem. Always rely on the official documentation (see
> [References](#references)) for binding information. Figures, dates and eligibility rules
> reflect the Pilot-phase documents available at the time of writing and are subject to change.

---

## 1. What is Pontes?

**Pontes** is a Eurosystem (ECB) initiative that lets transactions executed on **Distributed
Ledger Technology (DLT)** platforms be settled in **central bank money (CeBM)** in euro. It
answers a concrete market need: DLT-based markets have lacked a safe, central-bank-money cash
leg, which has held back their adoption at scale.

Pontes provides exactly that **cash leg**. The securities or other assets stay on the market's
own DLT platform; Pontes settles the **payment** side in euro central bank money, linking the
two so that delivery and payment can happen together.

The current stage is a **Pilot Phase** (targeting go-live in Q3 2026), deliberately built to
require **no changes to the existing legal, regulatory and operational framework of the TARGET
Services**, and operated *outside* the technical perimeter of TARGET for now. The longer-term
ambition is for Pontes to become a fully integrated TARGET Service.

### How settlement works

At the centre is the **ESY DLT platform** (the Eurosystem-operated infrastructure that manages
the cash leg). It offers **two settlement models**:

| Model | What happens | When you'd use it |
|-------|--------------|-------------------|
| **Cash Token** | A *cash token* — a proxy for euro central bank money, redeemable 1:1 against funds in T2 RTGS — is issued onto the ESY DLT and moved between wallets to settle. | DLT-native settlement, wallet-to-wallet, DvP/PvP fully on-ledger. |
| **Direct RTGS** | The instruction on the ESY DLT *triggers* a real-time settlement directly in **T2 RTGS** (via standard ISO 20022 messages, e.g. `pacs.010`/`pacs.009`). | Settling straight in RTGS without holding tokens. |

Cash tokens are created (**funding**) by debiting a participant's T2 RTGS account and issuing
the equivalent tokens, and destroyed (**defunding**) by the reverse. No token balances remain
overnight — the ledger is swept at end of day so tokens always mirror real CeBM held in
dedicated ECB-owned T2 accounts (the *Token Issuance Account* and *Technical Interim Account*).

---

## 2. Who is Pontes for?

Pontes is a **wholesale**, permissioned system for regulated financial-market actors. The
defined roles are:

- **National Central Banks (NCBs)** — each Eurosystem NCB that has participating clients runs
  its own **node** on the ESY DLT and admits/manages its community of market participants.
- **European Central Bank (ECB)** — issues and redeems cash tokens (the *issuer node*) and is
  the legal owner of the technical T2 accounts that back the tokens.
- **Service Providers (4CB)** — the national central banks that **develop, host and operate**
  the platform on behalf of the Eurosystem.
- **Market Participants** — entities with access to TARGET (within the meaning of the TARGET
  Guideline). They own **Dedicated Cash Wallets (DCWs)** and instruct payments, funding and
  settlement.
- **Market DLT Operators** — operators of the market-side DLT platforms, acting *on behalf of*
  market participants. Eligible types include CSDs (CSDR), DSS/DTSS operators (DLT Pilot
  Regime), overseen payment-system operators, CCPs (EMIR), and authorised credit
  institutions / investment firms / market operators under CRD / MiFID II.

> **Access is gated.** Pontes is not an open or public network. Every endpoint is protected by
> per-NCB OAuth2 + JWT, and participation requires meeting Eurosystem eligibility criteria and
> being **onboarded and registered through a specific NCB**. Independent advisors or technical
> providers do not have a standalone access role; they typically operate *under* an eligible
> client's onboarding (e.g. via designated indirect access to a participant's DCWs, or
> "instruct-on-behalf" arrangements).

---

## 3. How the Pontes network is used (functional view)

Interaction follows a participant's **lifecycle**: first onboarding, then reference-data
set-up, then day-to-day operations.

### 3.1 Onboarding & reference data
- Onboarding of **market participants** and **market DLT operators** (admitted by their NCB).
- Set-up of **T2 Account References**, **Dedicated Cash Wallets**, **whitelists** (which
  counterparties/wallets may interact), and **powers of attorney / instruct-on-behalf**
  mandates.
- Querying business calendar data: business date, business windows, closed days, the list of
  participating NCBs and market DLT platforms.

### 3.2 Cash operations
- **Funding** — convert T2 RTGS balances into cash tokens on the ESY DLT.
- **Defunding** — redeem cash tokens back into T2 RTGS balances.

### 3.3 Settlement & payments
- **Payments** — in either model: *Cash Token* or *Direct RTGS*.
- **Transfers** — wallet-to-wallet cash-token movements.
- **XvP (DvP / PvP)** — Delivery-versus-Payment and Payment-versus-Payment, coordinated with the
  market DLT platform so the asset and cash legs settle conditionally together. Available for
  both Cash Token and Direct RTGS.
- **Payment Free of Delivery (PFoD)** — payment leg without a coupled delivery.
- **Instruct on behalf** — an operator or another participant instructs on behalf of the DCW
  owner.
- **Contingency operations** — issuance/redemption fallbacks for exceptional situations.

### 3.4 Information & monitoring
- **Queries and extracts** across participants, accounts, wallets, transactions, funding/
  defunding and balances, plus operational statistics and platform health.

### 3.5 Two cross-cutting concepts
- **Validation Workflow — "2-Step" vs "1-Step".** Most sensitive operations follow a *4-eyes*
  model: they are created as a **draft** (first action) and then **approved or rejected**
  (second action). 1-Step variants book immediately.
- **Transaction Type — "Cash Token" vs "Direct RTGS".** Many flows exist in both flavours; the
  choice determines whether settlement is token-based on the ledger or triggered directly in
  RTGS.

### 3.6 Interfaces
- **A2A (Application-to-Application)** — a REST API (the *EII API*, specified in OpenAPI),
  secured per NCB with OAuth2 (`OAuth2_A2A_<NCB>`) and JWT. It interoperates with existing
  TARGET / T2 RTGS interfaces using standard ISO 20022 messages.
- **U2A (User-to-Application)** — a Graphical User Interface for manual operation and monitoring.

---

## 4. Access, testing & timeline

- **Test environment:** a single shared environment ("L2 Test Environment") hosts Eurosystem
  Acceptance Testing (EAT), Central Bank Testing (CBT) and User Testing (UT), interconnected
  with the T2 UTEST environment.
- **To get in:** complete registration for User Testing **with your NCB**, pass connectivity
  testing, and execute the mandatory test cases for certification.
- **Indicative timeline:** Pilot go-live targeted for **Q3 2026**; onboarding of new actors
  open until **31 December 2027** (dates per Pilot documents, subject to change).

---

## 5. References

Official ECB Pontes documentation (professional-use document links on ecb.europa.eu web):

- **Business Description Document (BDD)** — business model, actors and scope.
- **Service Description (SDD)** — the functional specification (each API feature maps to a
  chapter of this document).
- **User Requirements Document (URD)**.
- **User Handbook (UHB)** — operational guidance.
- **Testing and Onboarding Strategy**, **Testing Terms of Reference (ToR)**, and the
  **Mandatory Test Cases**.

Official portal: <https://www.ecb.europa.eu/paym/target/> → TARGET professional-use documents → Pontes.

---

*This summary was prepared independently for orientation and does not reproduce any ECB
document. For authoritative detail and current eligibility/onboarding rules, consult the
official documents above and the relevant National Central Bank.*
