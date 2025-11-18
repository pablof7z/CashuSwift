//
//  paymentRequest.swift
//  CashuSwift
//
//  Created for NUT-18 Payment Requests
//

import Foundation
import secp256k1

extension CashuSwift {
    
    // MARK: - Receiver Side Operations
    
    /// Creates a payment request for receiving payments.
    ///
    /// - Parameters:
    ///   - amount: Optional amount to request (if nil, sender can choose amount)
    ///   - unit: Unit for the payment (e.g., "sat", "usd")
    ///   - mints: Optional list of accepted mint URLs (if nil, any mint is accepted)
    ///   - description: Optional human-readable description
    ///   - transports: Optional list of transport methods for receiving payment
    ///   - singleUse: Whether the payment request is for single use only
    ///   - lockingPublicKey: Optional public key hex for P2PK locking requirement
    ///   - lockingTags: Optional tags for locking conditions (e.g., [["timeout", "3600"]])
    /// - Returns: The serialized payment request string
    /// - Throws: An error if creation fails
    public static func createPaymentRequest(amount: Int?,
                                           unit: String,
                                           mints: [String]?,
                                           description: String? = nil,
                                           transports: [Transport]? = nil,
                                           singleUse: Bool? = nil,
                                           lockingPublicKey: String? = nil,
                                           lockingTags: [[String]]? = nil) throws -> String {
        
        // Generate a random payment ID
        let paymentId = generateRandomId()
        
        // Create NUT-10 option if locking is requested
        var nut10: NUT10Option? = nil
        if let publicKey = lockingPublicKey {
            nut10 = NUT10Option(kind: NUT10Option.Kind.p2pk, data: publicKey, tags: lockingTags)
        }
        
        let request = PaymentRequest(
            paymentId: paymentId,
            amount: amount,
            unit: unit,
            singleUse: singleUse,
            mints: mints,
            description: description,
            transports: transports,
            lockingCondition: nut10
        )
        
        return try request.serialize()
    }
    
    /// Receives and validates a payment against a payment request.
    ///
    /// - Parameters:
    ///   - payload: The payment request payload from the sender
    ///   - request: The original payment request
    ///   - mint: The mint to use for receiving the payment
    ///   - seed: Optional seed for deterministic secret generation
    ///   - privateKey: Optional private key for unlocking P2PK-locked tokens
    /// - Returns: A tuple containing the received proofs and DLEQ verification results
    /// - Throws: An error if validation or receiving fails
    public static func receivePaymentRequest(payload: PaymentRequestPayload,
                                            request: PaymentRequest,
                                            mint: Mint,
                                            seed: String?,
                                            privateKey: String?) async throws -> (proofs: [Proof],
                                                                                  inputDLEQ: Crypto.DLEQVerificationResult,
                                                                                  outputDLEQ: Crypto.DLEQVerificationResult) {
        
        // Validate payload against request
        try payload.validates(against: request)
        
        // Convert payload to token
        let token = payload.toToken()
        
        // Receive the token using existing receive operation
        return try await receive(token: token, of: mint, seed: seed, privateKey: privateKey)
    }
    
    // MARK: - Sender Side Operations
    
    /// Fulfills a payment request by creating a matching token.
    ///
    /// - Parameters:
    ///   - request: The payment request to fulfill
    ///   - mint: The mint to use for creating the token
    ///   - proofs: Available proofs to use for payment
    ///   - seed: Optional seed for deterministic secret generation
    ///   - privateKey: Optional private key for P2PK signing (hex string)
    /// - Returns: A PaymentRequestPayload ready to send
    /// - Throws: An error if the request cannot be fulfilled
    public static func fulfillPaymentRequest(request: PaymentRequest,
                                            mint: Mint,
                                            proofs: [Proof],
                                            seed: String?,
                                            privateKey: String?) async throws -> PaymentRequestPayload {
        
        // Validate request
        try request.validate()
        
        // Check mint is accepted
        if !request.acceptsMint(mint.url.absoluteString) {
            throw CashuError.paymentRequestValidation("Mint '\(mint.url.absoluteString)' is not accepted by this payment request")
        }
        
        // Check unit matches
        guard let requestUnit = request.unit else {
            throw CashuError.paymentRequestValidation("Payment request must specify a unit")
        }
        
        // Calculate required amount
        let requiredAmount = request.amount ?? proofs.reduce(0) { $0 + $1.amount }
        
        // Select proofs for the amount
        let selectedProofs = try selectProofs(from: proofs, amount: requiredAmount)
        
        let totalSelected = selectedProofs.reduce(0) { $0 + $1.amount }
        guard totalSelected >= requiredAmount else {
            throw CashuError.insufficientInputs("Insufficient proofs: need \(requiredAmount), have \(totalSelected)")
        }
        
        // If we need to swap to get exact amount or apply locking conditions
        var outputProofs: [Proof]
        
        if let lockingCondition = request.lockingCondition {
            // Need to apply locking conditions
            // Get amount distribution for outputs
            let distribution = amountDistribution(for: requiredAmount)
            
            // Generate P2PK-locked outputs
            let lockedOutputs = try generateP2PKOutputs(distribution: distribution,
                                                       mint: mint,
                                                       publicKey: lockingCondition.data,
                                                       unit: requestUnit)
            
            // Generate regular outputs for any change
            let changeAmount = totalSelected - requiredAmount
            let changeDistribution = changeAmount > 0 ? amountDistribution(for: changeAmount) : []
            let changeOutputs = try generateOutputs(distribution: changeDistribution,
                                                   mint: mint,
                                                   seed: seed,
                                                   unit: requestUnit)
            
            // Perform swap with both locked and change outputs
            let swapResult = try await swap(inputs: selectedProofs,
                                          with: mint,
                                          sendOutputs: lockedOutputs,
                                          keepOutputs: changeOutputs)
            outputProofs = swapResult.send
            
        } else if totalSelected > requiredAmount {
            // Need to swap to get exact amount
            let sendDistribution = amountDistribution(for: requiredAmount)
            let changeDistribution = amountDistribution(for: totalSelected - requiredAmount)
            
            let sendOutputs = try generateOutputs(distribution: sendDistribution,
                                                 mint: mint,
                                                 seed: seed,
                                                 unit: requestUnit)
            let changeOutputs = try generateOutputs(distribution: changeDistribution,
                                                   mint: mint,
                                                   seed: seed,
                                                   unit: requestUnit,
                                                   offset: sendDistribution.count)
            
            let swapResult = try await swap(inputs: selectedProofs,
                                          with: mint,
                                          sendOutputs: sendOutputs,
                                          keepOutputs: changeOutputs)
            outputProofs = swapResult.send
            
        } else {
            // Exact amount, no locking needed
            outputProofs = selectedProofs
        }
        
        // Create payload
        return PaymentRequestPayload(
            id: request.paymentId,
            memo: nil,
            mint: mint.url.absoluteString,
            unit: requestUnit,
            proofs: outputProofs
        )
    }
    
    /// Sends a payment request payload via HTTP POST transport.
    ///
    /// - Parameters:
    ///   - payload: The payment request payload to send
    ///   - endpoint: The HTTP endpoint URL
    /// - Returns: The HTTP response data
    /// - Throws: An error if sending fails
    public static func sendPaymentViaHTTP(payload: PaymentRequestPayload,
                                         to endpoint: String) async throws -> Data {
        
        guard let url = URL(string: endpoint) else {
            throw CashuError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CashuError.networkError
        }
        
        return data
    }
    
    // MARK: - Helper Functions
    
    /// Generates a random payment ID.
    private static func generateRandomId() -> String {
        let bytes = (0..<4).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Generates a random nonce for spending conditions.
    private static func generateRandomNonce() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Selects proofs to cover a specific amount.
    private static func selectProofs(from proofs: [Proof], amount: Int) throws -> [Proof] {
        var selected: [Proof] = []
        var total = 0
        
        // Sort proofs by amount (smallest first for better selection)
        let sortedProofs = proofs.sorted { $0.amount < $1.amount }
        
        for proof in sortedProofs {
            if total >= amount {
                break
            }
            selected.append(proof)
            total += proof.amount
        }
        
        guard total >= amount else {
            throw CashuError.insufficientInputs("Cannot select enough proofs to cover amount \(amount)")
        }
        
        return selected
    }
    
    /// Creates an amount distribution using binary decomposition.
    private static func amountDistribution(for amount: Int) -> [Int] {
        var distribution: [Int] = []
        var remaining = amount
        var power = 0
        
        while remaining > 0 {
            let bit = remaining & 1
            if bit == 1 {
                let outputAmount = 1 << power
                distribution.append(outputAmount)
            }
            remaining >>= 1
            power += 1
        }
        
        return distribution
    }
}

