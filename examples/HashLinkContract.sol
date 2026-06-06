// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =============================================================================
//  ⚠️  ILLUSTRATIVE REFERENCE ONLY — NOT AUDITED, NOT FOR PRODUCTION  ⚠️
// -----------------------------------------------------------------------------
//  This is a *reference* Hash-Link Contract (HLC) showing how the ASSET leg of a
//  Pontes DvP/PvP could be escrowed on an external (EVM) market DLT so that it
//  interoperates with the Pontes Hash-Link protocol. It is a teaching aid that
//  accompanies the Pontes executive summary; it has NOT been audited and MUST
//  NOT be deployed as-is. As the summary's Conclusions note, the Eurosystem
//  neither writes nor audits this contract — its correctness is entirely the
//  responsibility of the (regulated) Market DLT Operator. Treat this file
//  accordingly.
//
//  WHAT PONTES GIVES YOU (see the DvP flow, README §4):
//   - On `Initialise`, Pontes returns `executionHash` and `cancellationHash`,
//     each defined by the OpenAPI as the SHA-256 of a secret it keeps:
//        executionHash    = SHA256(executionKey)
//        cancellationHash = SHA256(cancellationKey)
//   - Pontes acts as the trusted oracle: it discloses EXACTLY ONE secret,
//     gated on the cash-leg outcome —
//        SETTLED              -> executionKey   to the Buyer
//        UNSETTLED / BURNED   -> cancellationKey to the Seller
//
//  DESIGN NOTE — why this is a Hash-LINK contract, not a classic HTLC:
//   The TIME arbitration lives in Pontes (the "oracle of time"), NOT here.
//   This contract therefore has NO timestamp-based unilateral reclaim. Adding
//   one would reintroduce the classic HTLC "free option" race: after the Buyer
//   pays (SETTLED) but before it calls forcedExecute(), a timeout-reclaim would
//   let the Seller pull the asset back even though the cash already settled.
//   Cancellation here REQUIRES the cancellationKey, which Pontes only releases
//   when the cash leg did NOT settle. The trade-off is explicit: if the oracle
//   never releases a key, the asset stays escrowed (trust-in-oracle, by design).
//   `deadline` is stored for traceability only and is NOT enforced on-chain.
//
//  CRITICAL ASSUMPTION TO CONFIRM — preimage encoding:
//   `forcedExecute`/`forcedCancel` check `sha256(key) == storedHash`. Solidity's
//   sha256() hashes the exact bytes passed in. You MUST pass the key as the SAME
//   byte sequence Pontes hashed to produce the hash. The OpenAPI shows the key
//   as a hex string (64–128 hex chars) and the hash as 32 bytes; whether Pontes
//   hashes the ASCII hex string or the decoded bytes is NOT spelled out — confirm
//   against the API/Swagger before relying on this. Get it wrong and forced
//   execution will revert.
// =============================================================================

/// @dev Minimal ERC-20 surface. For tokens that don't return a bool, wrap calls
///      with a SafeERC20-style helper in a real implementation.
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title  HashLinkContract (reference)
/// @notice Escrows an ERC-20 asset (e.g. tokenised bond units) for one Pontes
///         DvP/PvP and releases it to the Buyer or the Seller depending on which
///         Pontes-issued secret is revealed.
contract HashLinkContract {
    enum State { AWAITING_LOCK, LOCKED, EXECUTED, CANCELLED }

    // --- Parties -------------------------------------------------------------
    address public immutable seller; // delivers the asset, receives the cash
    address public immutable buyer;  // receives the asset, pays the cash

    // --- Asset leg (this ledger) --------------------------------------------
    IERC20  public immutable asset;  // ERC-20 representing the bond units
    uint256 public immutable units;  // amount of bond-unit tokens escrowed

    // --- Hash-Link parameters (from Pontes Initialise response) --------------
    bytes32 public immutable executionHash;    // = SHA256(executionKey)
    bytes32 public immutable cancellationHash; // = SHA256(cancellationKey)

    // --- Traceability / informational ----------------------------------------
    string  public dvpId;            // Pontes xvpTransactionId (UUID)
    uint256 public immutable deadline; // Pontes `timeout` (UTC, unix). NOT enforced on-chain.

    State public state;

    event Locked(address indexed seller, address indexed asset, uint256 units, string dvpId);
    event Executed(address indexed to, bool forced);   // asset delivered to Buyer
    event Cancelled(address indexed to, bool forced);  // asset returned to Seller

    modifier inState(State s) {
        require(state == s, "HLC: bad state");
        _;
    }

    constructor(
        address _seller,
        address _buyer,
        IERC20  _asset,
        uint256 _units,
        bytes32 _executionHash,
        bytes32 _cancellationHash,
        string memory _dvpId,
        uint256 _deadline
    ) {
        require(_seller != address(0) && _buyer != address(0), "HLC: zero party");
        seller = _seller;
        buyer = _buyer;
        asset = _asset;
        units = _units;
        executionHash = _executionHash;
        cancellationHash = _cancellationHash;
        dvpId = _dvpId;
        deadline = _deadline;
        state = State.AWAITING_LOCK;
    }

    /// @notice Step 3 — the Seller escrows the asset. Seller must have approved
    ///         this contract for `units` of `asset` beforehand.
    function lock() external inState(State.AWAITING_LOCK) {
        require(msg.sender == seller, "HLC: only seller");
        state = State.LOCKED;
        require(asset.transferFrom(seller, address(this), units), "HLC: lock transfer failed");
        emit Locked(seller, address(asset), units, dvpId);
    }

    // -------------------------------------------------------------------------
    //  Release to the BUYER  (cash settled)
    // -------------------------------------------------------------------------

    /// @notice Step 9a — Cooperative Execution: the Seller, having seen the cash
    ///         leg SETTLED, hands the asset to the Buyer by proving identity.
    function cooperativeExecute() external inState(State.LOCKED) {
        require(msg.sender == seller, "HLC: only seller");
        _release(buyer, State.EXECUTED);
        emit Executed(buyer, false);
    }

    /// @notice Step 9b — Forced Execution: anyone holding the Execution Key
    ///         (the Buyer, who received it from Pontes on SETTLED) claims the
    ///         asset for the Buyer, without needing the Seller's cooperation.
    function forcedExecute(bytes calldata executionKey) external inState(State.LOCKED) {
        require(sha256(executionKey) == executionHash, "HLC: bad execution key");
        _release(buyer, State.EXECUTED);
        emit Executed(buyer, true);
    }

    // -------------------------------------------------------------------------
    //  Return to the SELLER  (cash did NOT settle)
    // -------------------------------------------------------------------------

    /// @notice Cooperative Cancellation: the Buyer returns the asset to the
    ///         Seller by proving identity (no key needed).
    function cooperativeCancel() external inState(State.LOCKED) {
        require(msg.sender == buyer, "HLC: only buyer");
        _release(seller, State.CANCELLED);
        emit Cancelled(seller, false);
    }

    /// @notice Forced Cancellation: the Seller, having obtained the Cancellation
    ///         Key from Pontes (released only on UNSETTLED/BURNED), reclaims the
    ///         asset without needing the Buyer.
    function forcedCancel(bytes calldata cancellationKey) external inState(State.LOCKED) {
        require(sha256(cancellationKey) == cancellationHash, "HLC: bad cancellation key");
        _release(seller, State.CANCELLED);
        emit Cancelled(seller, true);
    }

    function _release(address to, State newState) private {
        state = newState; // set before transfer (reentrancy-safe ordering)
        require(asset.transfer(to, units), "HLC: release transfer failed");
    }
}
