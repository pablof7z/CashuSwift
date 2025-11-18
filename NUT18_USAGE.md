# NUT-18 Payment Requests Usage Guide

This guide demonstrates how to use the NUT-18 payment request functionality in CashuSwift.

## Overview

NUT-18 enables payment requests where receivers can specify requirements for incoming payments, such as:
- Amount and unit
- Accepted mints
- P2PK locking conditions for offline receiving
- Transport methods (HTTP POST, Nostr)

All payment request related types (`PaymentRequest`, `Transport`, `NUT10Option`, `PaymentRequestPayload`) are defined in `Models/PaymentRequest.swift`.

## Basic Usage

### Receiver: Creating a Payment Request

```swift
import CashuSwift

// Create a simple payment request for 100 sats
let requestString = try CashuSwift.createPaymentRequest(
    amount: 100,
    unit: "sat",
    mints: ["https://mint.example.com"],
    description: "Payment for coffee",
    transports: [
        CashuSwift.Transport(
            type: CashuSwift.Transport.TransportType.httpPost,
            target: "https://api.myshop.com/payment",
            tags: nil
        )
    ],
    singleUse: true,
    lockingPublicKey: nil,
    lockingTags: nil
)

// Share this request string with the sender (QR code, NFC, etc.)
print("Payment Request: \(requestString)")
```

### Sender: Parsing and Fulfilling a Payment Request

```swift
// Parse the payment request
let request = try CashuSwift.PaymentRequest(encodedRequest: requestString)

// Check what the request requires
print("Amount: \(request.amount ?? 0) \(request.unit ?? "unknown")")
print("Description: \(request.description ?? "No description")")
print("Accepted mints: \(request.mints ?? [])")

// Fulfill the payment request
let payload = try await CashuSwift.fulfillPaymentRequest(
    request: request,
    mint: myMint,
    proofs: myAvailableProofs,
    seed: mySeed,
    privateKey: nil
)

// Send the payment via HTTP POST
if let transport = request.transports?.first,
   transport.type == CashuSwift.Transport.TransportType.httpPost {
    let response = try await CashuSwift.sendPaymentViaHTTP(
        payload: payload,
        to: transport.target
    )
    print("Payment sent successfully!")
}
```

### Receiver: Receiving and Validating a Payment

```swift
// Receive the payment payload (from HTTP endpoint, Nostr, etc.)
let payload: CashuSwift.PaymentRequestPayload = // ... decode from request

// Validate against the original request
try payload.validates(against: originalRequest)

// Receive the payment (swaps with the mint)
let (proofs, inputDLEQ, outputDLEQ) = try await CashuSwift.receivePaymentRequest(
    payload: payload,
    request: originalRequest,
    mint: myMint,
    seed: mySeed,
    privateKey: nil
)

// Check DLEQ verification
if inputDLEQ == .valid && outputDLEQ == .valid {
    print("Payment received and verified: \(proofs.count) proofs")
} else {
    print("Warning: DLEQ verification failed")
}
```

## Advanced: P2PK-Locked Payment Requests (Offline Receiving)

```swift
// Receiver generates a keypair
let privateKey = try secp256k1.Schnorr.PrivateKey()
let publicKeyHex = String(bytes: privateKey.publicKey.dataRepresentation)

// Create a payment request with P2PK locking
let requestString = try CashuSwift.createPaymentRequest(
    amount: 500,
    unit: "sat",
    mints: ["https://mint.example.com"],
    description: "Offline payment",
    transports: nil, // Can be offline/in-band
    singleUse: true,
    lockingPublicKey: publicKeyHex,
    lockingTags: [["timeout", "3600"]] // 1 hour timeout
)

// Sender fulfills the request (automatically applies P2PK locking)
let payload = try await CashuSwift.fulfillPaymentRequest(
    request: request,
    mint: myMint,
    proofs: myAvailableProofs,
    seed: mySeed,
    privateKey: nil
)

// Receiver can receive offline (later)
let privateKeyHex = String(bytes: privateKey.dataRepresentation)
let (proofs, _, _) = try await CashuSwift.receivePaymentRequest(
    payload: payload,
    request: originalRequest,
    mint: myMint,
    seed: mySeed,
    privateKey: privateKeyHex // Unlock the P2PK-locked tokens
)
```

## Payment Request Fields

### Required Fields
- `unit`: Unit (e.g., "sat", "usd") - Required if amount is specified
- `mints`: Array of accepted mint URLs - Required if you want to restrict mints

### Optional Fields
- `paymentId`: Payment ID for tracking
- `amount`: Requested amount
- `singleUse`: Single-use flag
- `description`: Human-readable description
- `transports`: Array of transport methods
- `lockingCondition`: NUT-10 locking conditions

## Transport Types

### HTTP POST
```swift
let transport = CashuSwift.Transport(
    type: "post",
    target: "https://api.example.com/payment",
    tags: nil
)
```

### Nostr NIP-17
```swift
let transport = CashuSwift.Transport(
    type: "nostr",
    target: "nprofile1...", // or npub
    tags: [["n", "17"]] // Supports NIP-17
)
```

## Validation

The payment request includes automatic validation for:
- Amount and unit matching
- Mint acceptance
- P2PK locking conditions
- Timeout/locktime requirements
- Payment ID matching

## Token Satisfaction Check

```swift
// Check if a token satisfies a payment request
let token: CashuSwift.Token = // ... your token
let request: CashuSwift.PaymentRequest = // ... payment request

if token.satisfies(request) {
    print("Token satisfies the payment request")
} else {
    print("Token does not meet requirements")
}
```

## Error Handling

```swift
do {
    let payload = try await CashuSwift.fulfillPaymentRequest(
        request: request,
        mint: myMint,
        proofs: myProofs,
        seed: nil,
        privateKey: nil
    )
} catch CashuError.paymentRequestValidation(let message) {
    print("Validation error: \(message)")
} catch CashuError.insufficientInputs(let message) {
    print("Insufficient balance: \(message)")
} catch CashuError.lockingConditionMismatch(let message) {
    print("Locking condition error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Test Vectors

The implementation includes test vectors from the NUT-18 specification to ensure compatibility with other Cashu implementations. See `Tests/cashu-swiftTests/PaymentRequestTests.swift` for examples.

**Note:** The "Complete Payment Request" test vector in the [official spec](https://github.com/cashubtc/nuts/blob/main/tests/18-tests.md) contains malformed CBOR data (premature EOF). The test suite uses a corrected version generated from the JSON structure.

## Limitations

- Nostr transport currently requires manual implementation of NIP-17 messaging
- Payment requests are version A (as per spec)
- Swap operations may incur fees depending on the mint

## References

- [NUT-18 Specification](https://github.com/cashubtc/nuts/blob/main/18.md)
- [NUT-10 Spending Conditions](https://github.com/cashubtc/nuts/blob/main/10.md)
- [NUT-18 Test Vectors](https://github.com/cashubtc/nuts/blob/main/tests/18-tests.md)

