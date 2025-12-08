//
//  Results.swift
//  CashuSwift
//
//  Created on 08.12.25.
//

import Foundation

extension CashuSwift {
    /// Result of an issue operation (minting new proofs from a paid mint quote)
    public struct IssueResult {
        /// The newly issued proofs
        public let proofs: [Proof]
        /// Result of DLEQ verification for the issued proofs
        public let dleqResult: Crypto.DLEQVerificationResult
        
        public init(proofs: [Proof], dleqResult: Crypto.DLEQVerificationResult) {
            self.proofs = proofs
            self.dleqResult = dleqResult
        }
    }
    
    /// Result of a melt operation (paying a Lightning invoice with proofs)
    public struct MeltResult {
        /// The melt quote response from the mint
        public let quote: Bolt11.MeltQuote
        /// Change proofs returned if fee was overpaid
        public let change: [Proof]?
        /// Result of DLEQ verification for the change proofs
        public let dleqResult: Crypto.DLEQVerificationResult
        
        public init(quote: Bolt11.MeltQuote, change: [Proof]?, dleqResult: Crypto.DLEQVerificationResult) {
            self.quote = quote
            self.change = change
            self.dleqResult = dleqResult
        }
    }
    
    /// Result of a send operation (creating a token from proofs)
    public struct SendResult {
        /// The created Cashu token to send
        public let token: Token
        /// Change proofs kept by the sender
        public let change: [Proof]
        /// Result of DLEQ verification for output proofs
        public let outputDLEQ: Crypto.DLEQVerificationResult
        /// Keyset ID and counter increase for deterministic derivation
        public let counterIncrease: (keysetID: String, increase: Int)?
        
        public init(token: Token, change: [Proof], outputDLEQ: Crypto.DLEQVerificationResult, counterIncrease: (keysetID: String, increase: Int)?) {
            self.token = token
            self.change = change
            self.outputDLEQ = outputDLEQ
            self.counterIncrease = counterIncrease
        }
    }
    
    /// Result of a send operation for a payment request
    public struct SendPayloadResult {
        /// The payment request payload to send
        public let payload: PaymentRequestPayload
        /// Change proofs kept by the sender
        public let change: [Proof]
        /// Result of DLEQ verification for output proofs
        public let outputDLEQ: Crypto.DLEQVerificationResult
        /// Keyset ID and counter increase for deterministic derivation
        public let counterIncrease: (keysetID: String, increase: Int)?
        
        public init(payload: PaymentRequestPayload, change: [Proof], outputDLEQ: Crypto.DLEQVerificationResult, counterIncrease: (keysetID: String, increase: Int)?) {
            self.payload = payload
            self.change = change
            self.outputDLEQ = outputDLEQ
            self.counterIncrease = counterIncrease
        }
    }
    
    /// Result of a receive operation (swapping incoming proofs for new ones)
    public struct ReceiveResult {
        /// The newly received proofs
        public let proofs: [Proof]
        /// Result of DLEQ verification for input proofs
        public let inputDLEQ: Crypto.DLEQVerificationResult
        /// Result of DLEQ verification for output proofs
        public let outputDLEQ: Crypto.DLEQVerificationResult
        
        public init(proofs: [Proof], inputDLEQ: Crypto.DLEQVerificationResult, outputDLEQ: Crypto.DLEQVerificationResult) {
            self.proofs = proofs
            self.inputDLEQ = inputDLEQ
            self.outputDLEQ = outputDLEQ
        }
    }
}

