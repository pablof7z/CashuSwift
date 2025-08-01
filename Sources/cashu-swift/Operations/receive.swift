import Foundation
import secp256k1
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

extension CashuSwift {
    
    /// Receives a Cashu token by swapping its proofs with the mint.
    ///
    /// This function allows a wallet to receive a token by swapping its inputs with the provided mint, thus finalizing the ecash transfer.
    ///
    /// - Parameters:
    ///   - token: A Cashu token to receive
    ///   - mint: The mint to receive with via swap operation (must be same as in token)
    ///   - seed: Optional seed for deterministic secret generation
    ///   - privateKey: Optional hex string of 32-byte Schnorr private key for unlocking P2PK-locked tokens
    ///
    /// - Returns: A tuple containing:
    ///   - proofs: The received proof objects
    ///   - inputDLEQ: DLEQ verification result for input proofs
    ///   - outputDLEQ: DLEQ verification result for output proofs
    /// - Throws: An error if the receive operation fails
    public static func receive(token: Token,
                               of mint: Mint,
                               seed: String?,
                               privateKey: String?) async throws -> (proofs: [Proof],
                                                                     inputDLEQ: Crypto.DLEQVerificationResult,
                                                                     outputDLEQ: Crypto.DLEQVerificationResult) {
        
        // this should check whether proofs are from this mint and not multi unit FIXME: potentially wonky and not very descriptive
        guard token.proofsByMint.count == 1 else {
            logger.error("You tried to receive a token that either contains no proofs at all, or proofs from more than one mint.")
            throw CashuError.invalidToken
        }
        
        if token.proofsByMint.keys.first! != mint.url.absoluteString {
            logger.warning("Mint URL field from token does not seem to match this mints URL.")
        }
        
        guard var inputProofs = token.proofsByMint.first?.value,
              try units(for: inputProofs, of: mint).count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        var publicKey: String? = nil
        if let privateKey {
            guard let k = try? secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKey.bytes) else {
                throw CashuError.spendingConditionError("Token contains locked proofs but private key was not provided or invalid.")
            }
            publicKey = String(bytes: k.publicKey.dataRepresentation)
        }
        
        switch try token.checkAllInputsLocked(to: publicKey) {
        case .match:
            // TODO: for now we skip failing DLEQ verification alltogether
            
            let proofsWitness = try inputProofs.map { p in
                // FIXME: redundant
                guard let privateKey,
                      let k = try? secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKey.bytes) else {
                    throw CashuError.spendingConditionError("Token contains locked proofs but private key was not provided or invalid.")
                }
                let sigBytes = try k.signature(for: p.secret.data(using: .utf8)!).bytes
                let witness = Proof.Witness(signatures: [String(bytes: sigBytes)])
                return try Proof(keysetID: p.keysetID,
                                 amount: p.amount,
                                 secret: p.secret,
                                 C: p.C,
                                 witness: witness.stringJSON())
            }
            inputProofs = proofsWitness
            
        case .mismatch:
            throw CashuError.spendingConditionError("P2PK locking keys did not match")
        case .noKey:
            throw CashuError.spendingConditionError("The token is locked but no key was provided")
        case .partial:
            throw CashuError.spendingConditionError("Token contains proofs with different spending conditions, which the library can not yet handle.")
        case .notLocked:
            break
        }
        
        let swapResult = try await swap(inputs: inputProofs, with: mint, seed: seed)
        return (swapResult.new, swapResult.inputDLEQ, swapResult.outputDLEQ)
    }
    
    
    @available(*, deprecated, message: "function does not check DLEQ")
    public static func receive(mint:MintRepresenting,
                               token:Token,
                               seed:String? = nil) async throws -> [ProofRepresenting] {
        // this should check whether proofs are from this mint and not multi unit FIXME: potentially wonky and not very descriptive
        guard token.proofsByMint.count == 1 else {
            logger.error("You tried to receive a token that either contains no proofs at all, or proofs from more than one mint.")
            throw CashuError.invalidToken
        }
        
        if token.proofsByMint.keys.first! != mint.url.absoluteString {
            logger.warning("Mint URL field from token does not seem to match this mints URL.")
        }
        
        guard let inputProofs = token.proofsByMint.first?.value,
              try units(for: inputProofs, of: mint).count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        return try await swap(mint:mint, proofs: inputProofs, seed: seed).new
    }
    
    @available(*, deprecated, message: "function does not check DLEQ")
    public static func receive(mint: Mint,
                             token: Token,
                             seed: String? = nil) async throws -> [Proof] {
        return try await receive(mint: mint as MintRepresenting,
                                token: token,
                                seed: seed) as! [Proof]
    }
    
    @available(*, deprecated, message: "use function with precise DLEQ check results and P2PK unlocking ability.")
    public static func receive(token: Token,
                               with mint: Mint,
                               seed: String?) async throws -> (proofs: [Proof],
                                                                     dleqValid: Bool) {
        
        let result = try await receive(token: token, of: mint, seed: seed, privateKey: nil)
        
        let valid = result.inputDLEQ == .valid && result.inputDLEQ == result.outputDLEQ // check DLEQ is valid in and out
        
        return (result.proofs, valid)
    }
}
