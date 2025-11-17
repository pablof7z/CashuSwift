//
//  PaymentRequest.swift
//  CashuSwift
//
//  Created for NUT-18 Payment Requests
//

import Foundation
import SwiftCBOR

// MARK: - Transport

extension CashuSwift {
    /// Represents a transport method for sending payment request payloads.
    ///
    /// Transports specify how the sender should deliver the payment to the receiver.
    public struct Transport: Codable, Equatable, Sendable {
        
        /// The type of transport (e.g., "nostr", "post")
        public let t: String
        
        /// The target address for the transport (e.g., URL, nostr identifier)
        public let a: String
        
        /// Optional tags providing additional transport information
        public let g: [[String]]?
        
        /// Creates a new transport instance.
        /// - Parameters:
        ///   - type: The type of transport
        ///   - target: The target address
        ///   - tags: Optional tags for additional transport features
        public init(type: String, target: String, tags: [[String]]? = nil) {
            self.t = type
            self.a = target
            self.g = tags
        }
        
        /// Transport type constants
        public enum TransportType {
            public static let nostr = "nostr"
            public static let httpPost = "post"
        }
        
        /// Parses tags into a dictionary mapping tag keys to their values.
        /// - Returns: Dictionary where keys are tag names and values are arrays of tag values
        public func parsedTags() -> [String: [String]] {
            guard let tags = g else { return [:] }
            var result: [String: [String]] = [:]
            
            for tag in tags {
                guard tag.count >= 2 else { continue }
                let key = tag[0]
                let values = Array(tag.dropFirst())
                result[key, default: []].append(contentsOf: values)
            }
            
            return result
        }
        
        /// Checks if the transport supports a specific tag value.
        /// - Parameters:
        ///   - key: The tag key to check
        ///   - value: The tag value to look for
        /// - Returns: True if the tag is present with the specified value
        public func hasTag(key: String, value: String) -> Bool {
            let parsed = parsedTags()
            return parsed[key]?.contains(value) ?? false
        }
        
        // MARK: - CBOR Encoding/Decoding
        
        /// Decodes a Transport from CBOR
        init(fromCBOR cbor: CBOR) throws {
            guard let cborMap = cbor.asMap() else {
                throw CashuError.paymentRequestDecoding("Expected CBOR map for Transport")
            }
            
            guard let type = cborMap[.utf8String("t")]?.asString(),
                  let target = cborMap[.utf8String("a")]?.asString() else {
                throw CashuError.paymentRequestDecoding("Missing required fields in Transport")
            }
            
            self.t = type
            self.a = target
            
            // Decode optional tags
            if let tagsArray = cborMap[.utf8String("g")]?.asArray() {
                var tags: [[String]] = []
                for tagCBOR in tagsArray {
                    if let tagArray = tagCBOR.asArray() {
                        let stringTags = tagArray.compactMap { $0.asString() }
                        if !stringTags.isEmpty {
                            tags.append(stringTags)
                        }
                    }
                }
                self.g = tags.isEmpty ? nil : tags
            } else {
                self.g = nil
            }
        }
        
        /// Encodes the Transport to CBOR
        func toCBOR() -> CBOR {
            var cborMap: [CBOR: CBOR] = [
                .utf8String("t"): .utf8String(t),
                .utf8String("a"): .utf8String(a)
            ]
            
            if let tags = g, !tags.isEmpty {
                let tagsArray = tags.map { tag in
                    CBOR.array(tag.map { CBOR.utf8String($0) })
                }
                cborMap[.utf8String("g")] = .array(tagsArray)
            }
            
            return .map(cborMap)
        }
    }
}

// MARK: - NUT10Option

extension CashuSwift {
    /// Represents a NUT-10 locking condition option for payment requests.
    ///
    /// This specifies the required spending condition that the sender must apply to the payment.
    public struct NUT10Option: Codable, Equatable, Sendable {
        
        /// The kind of spending condition (e.g., "P2PK", "HTLC")
        public let k: String
        
        /// The data for the spending condition (e.g., public key hex, hash)
        public let d: String
        
        /// Optional tags for additional constraints
        public let t: [[String]]?
        
        /// Creates a new NUT-10 option instance.
        /// - Parameters:
        ///   - kind: The kind of spending condition
        ///   - data: The data for the spending condition
        ///   - tags: Optional tags for additional constraints
        public init(kind: String, data: String, tags: [[String]]? = nil) {
            self.k = kind
            self.d = data
            self.t = tags
        }
        
        /// Common kind constants
        public enum Kind {
            public static let p2pk = "P2PK"
            public static let htlc = "HTLC"
        }
        
        /// Parses tags into a dictionary mapping tag keys to their values.
        /// - Returns: Dictionary where keys are tag names and values are arrays of tag values
        public func parsedTags() -> [String: [String]] {
            guard let tags = t else { return [:] }
            var result: [String: [String]] = [:]
            
            for tag in tags {
                guard tag.count >= 2 else { continue }
                let key = tag[0]
                let values = Array(tag.dropFirst())
                result[key, default: []].append(contentsOf: values)
            }
            
            return result
        }
        
        /// Converts this NUT-10 option to a SpendingCondition.
        /// - Parameter nonce: A random nonce for the spending condition
        /// - Returns: A SpendingCondition instance
        /// - Throws: An error if the conversion fails
        public func toSpendingCondition(nonce: String) throws -> SpendingCondition {
            guard let conditionKind = SpendingCondition.Kind(rawValue: k) else {
                throw CashuError.spendingConditionError("Unknown spending condition kind: \(k)")
            }
            
            // Convert tags to SpendingCondition.Tag format
            var conditionTags: [SpendingCondition.Tag]? = nil
            if let tags = t {
                conditionTags = try tags.compactMap { tag in
                    guard tag.count >= 2 else { return nil }
                    let key = tag[0]
                    let values = Array(tag.dropFirst())
                    
                    switch key {
                    case "sigflag":
                        return .sigflag(values: values)
                    case "pubkeys":
                        return .pubkeys(values: values)
                    case "refund":
                        return .refund(values: values)
                    case "n_sigs":
                        let intValues = try values.map { value in
                            guard let intValue = Int(value) else {
                                throw CashuError.spendingConditionError("Invalid integer value in n_sigs tag: \(value)")
                            }
                            return intValue
                        }
                        return .n_sigs(values: intValues)
                    case "locktime", "timeout":
                        let intValues = try values.map { value in
                            guard let intValue = Int(value) else {
                                throw CashuError.spendingConditionError("Invalid integer value in \(key) tag: \(value)")
                            }
                            return intValue
                        }
                        return .locktime(values: intValues)
                    default:
                        return nil
                    }
                }
            }
            
            let payload = SpendingCondition.Payload(
                nonce: nonce,
                data: d,
                tags: conditionTags
            )
            
            return SpendingCondition(kind: conditionKind, payload: payload)
        }
        
        /// Creates a NUT-10 option from a SpendingCondition.
        /// - Parameter spendingCondition: The spending condition to convert
        /// - Returns: A NUT10Option instance
        public static func from(spendingCondition: SpendingCondition) -> NUT10Option {
            let kind = spendingCondition.kind.rawValue
            let data = spendingCondition.payload.data
            
            // Convert tags to NUT-10 format
            var tags: [[String]]? = nil
            if let conditionTags = spendingCondition.payload.tags {
                tags = conditionTags.map { tag in
                    switch tag {
                    case .sigflag(let values):
                        return ["sigflag"] + values
                    case .n_sigs(let values):
                        return ["n_sigs"] + values.map { String($0) }
                    case .pubkeys(let values):
                        return ["pubkeys"] + values
                    case .locktime(let values):
                        return ["locktime"] + values.map { String($0) }
                    case .refund(let values):
                        return ["refund"] + values
                    }
                }
            }
            
            return NUT10Option(kind: kind, data: data, tags: tags)
        }
        
        // MARK: - CBOR Encoding/Decoding
        
        /// Decodes a NUT10Option from CBOR
        init(fromCBOR cbor: CBOR) throws {
            guard let cborMap = cbor.asMap() else {
                throw CashuError.paymentRequestDecoding("Expected CBOR map for NUT10Option")
            }
            
            guard let kind = cborMap[.utf8String("k")]?.asString(),
                  let data = cborMap[.utf8String("d")]?.asString() else {
                throw CashuError.paymentRequestDecoding("Missing required fields in NUT10Option")
            }
            
            self.k = kind
            self.d = data
            
            // Decode optional tags
            if let tagsArray = cborMap[.utf8String("t")]?.asArray() {
                var tags: [[String]] = []
                for tagCBOR in tagsArray {
                    if let tagArray = tagCBOR.asArray() {
                        let stringTags = tagArray.compactMap { $0.asString() }
                        if !stringTags.isEmpty {
                            tags.append(stringTags)
                        }
                    }
                }
                self.t = tags.isEmpty ? nil : tags
            } else {
                self.t = nil
            }
        }
        
        /// Encodes the NUT10Option to CBOR
        func toCBOR() -> CBOR {
            var cborMap: [CBOR: CBOR] = [
                .utf8String("k"): .utf8String(k),
                .utf8String("d"): .utf8String(d)
            ]
            
            if let tags = t, !tags.isEmpty {
                let tagsArray = tags.map { tag in
                    CBOR.array(tag.map { CBOR.utf8String($0) })
                }
                cborMap[.utf8String("t")] = .array(tagsArray)
            }
            
            return .map(cborMap)
        }
    }
}

// MARK: - PaymentRequest

extension CashuSwift {
    /// Represents a Cashu payment request (NUT-18).
    ///
    /// Payment requests allow receivers to specify requirements for incoming payments,
    /// such as amount, unit, accepted mints, and locking conditions.
    public struct PaymentRequest: Codable, Equatable, Sendable {
        
        /// Payment ID to be included in the payment payload
        public let i: String?
        
        /// The amount of the requested payment
        public let a: Int?
        
        /// The unit of the requested payment (MUST be set if `a` is set)
        public let u: String?
        
        /// Whether the payment request is for single use
        public let s: Bool?
        
        /// A set of mints from which the payment is requested
        public let m: [String]?
        
        /// A human readable description
        public let d: String?
        
        /// The method of transport chosen to transmit the payment
        public let t: [Transport]?
        
        /// The required NUT-10 locking condition
        public let nut10: NUT10Option?
        
        /// Creates a new payment request instance.
        /// - Parameters:
        ///   - i: Optional payment ID
        ///   - a: Optional amount
        ///   - u: Optional unit (required if amount is set)
        ///   - s: Optional single-use flag
        ///   - m: Optional array of accepted mint URLs
        ///   - d: Optional description
        ///   - t: Optional array of transport methods
        ///   - nut10: Optional NUT-10 locking condition
        public init(i: String?, a: Int?, u: String?, s: Bool?, m: [String]?, d: String?, t: [Transport]?, nut10: NUT10Option?) {
            self.i = i
            self.a = a
            self.u = u
            self.s = s
            self.m = m
            self.d = d
            self.t = t
            self.nut10 = nut10
        }
        
        /// Validates the payment request.
        /// - Throws: An error if the request is invalid
        public func validate() throws {
            // If amount is set, unit must be set
            if a != nil && u == nil {
                throw CashuError.paymentRequestValidation("Unit must be set when amount is specified")
            }
        }
        
        /// Checks if a mint URL is accepted by this payment request.
        /// - Parameter mintURL: The mint URL to check
        /// - Returns: True if the mint is accepted (or if no mint constraint is specified)
        public func acceptsMint(_ mintURL: String) -> Bool {
            guard let acceptedMints = m else { return true }
            return acceptedMints.contains(mintURL)
        }
        
        /// Checks if a specific amount and unit satisfy this payment request.
        /// - Parameters:
        ///   - amount: The amount to check
        ///   - unit: The unit to check
        /// - Returns: True if the amount and unit satisfy the request
        public func satisfiesAmountAndUnit(amount: Int, unit: String) -> Bool {
            // Check unit
            if let requiredUnit = u, requiredUnit != unit {
                return false
            }
            
            // Check amount
            if let requiredAmount = a, requiredAmount != amount {
                return false
            }
            
            return true
        }
        
        // MARK: - CBOR Encoding/Decoding
        
        /// Decodes a PaymentRequest from CBOR
        init(fromCBOR cbor: CBOR) throws {
            guard let cborMap = cbor.asMap() else {
                throw CashuError.paymentRequestDecoding("Expected CBOR map for PaymentRequest")
            }
            
            // Decode optional fields
            self.i = cborMap[.utf8String("i")]?.asString()
            
            if let amountUInt = cborMap[.utf8String("a")]?.asUnsignedInt() {
                self.a = Int(amountUInt)
            } else {
                self.a = nil
            }
            
            self.u = cborMap[.utf8String("u")]?.asString()
            
            if case .boolean(let singleUse) = cborMap[.utf8String("s")] {
                self.s = singleUse
            } else {
                self.s = nil
            }
            
            // Decode mint array
            if let mintsArray = cborMap[.utf8String("m")]?.asArray() {
                self.m = mintsArray.compactMap { $0.asString() }
            } else {
                self.m = nil
            }
            
            self.d = cborMap[.utf8String("d")]?.asString()
            
            // Decode transport array
            if let transportsArray = cborMap[.utf8String("t")]?.asArray() {
                self.t = try transportsArray.map { try CashuSwift.Transport(fromCBOR: $0) }
            } else {
                self.t = nil
            }
            
            // Decode NUT-10 option
            if let nut10CBOR = cborMap[.utf8String("nut10")] {
                self.nut10 = try CashuSwift.NUT10Option(fromCBOR: nut10CBOR)
            } else {
                self.nut10 = nil
            }
        }
        
        /// Encodes the PaymentRequest to CBOR
        func toCBOR() -> CBOR {
            var cborMap: [CBOR: CBOR] = [:]
            
            // Encode only non-nil fields
            if let i = i {
                cborMap[.utf8String("i")] = .utf8String(i)
            }
            
            if let a = a {
                cborMap[.utf8String("a")] = .unsignedInt(UInt64(a))
            }
            
            if let u = u {
                cborMap[.utf8String("u")] = .utf8String(u)
            }
            
            if let s = s {
                cborMap[.utf8String("s")] = .boolean(s)
            }
            
            if let m = m, !m.isEmpty {
                cborMap[.utf8String("m")] = .array(m.map { .utf8String($0) })
            }
            
            if let d = d {
                cborMap[.utf8String("d")] = .utf8String(d)
            }
            
            if let t = t, !t.isEmpty {
                cborMap[.utf8String("t")] = .array(t.map { $0.toCBOR() })
            }
            
            if let nut10 = nut10 {
                cborMap[.utf8String("nut10")] = nut10.toCBOR()
            }
            
            return .map(cborMap)
        }
        
        // MARK: - Serialization
        
        /// Serializes the payment request to an encoded string.
        /// - Returns: The encoded payment request string with "creqA" prefix
        /// - Throws: An error if serialization fails
        public func serialize() throws -> String {
            try validate()
            
            let cborValue = self.toCBOR()
            let cborData = cborValue.encode()
            
            let base64URLSafe = Data(cborData).base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
            
            return "creqA\(base64URLSafe)"
        }
        
        /// Initializes a PaymentRequest from an encoded string.
        /// - Parameter encodedRequest: The encoded payment request string
        /// - Throws: An error if decoding fails
        public init(encodedRequest: String) throws {
            guard encodedRequest.hasPrefix("creqA") else {
                throw CashuError.paymentRequestDecoding("Payment request must start with 'creqA'")
            }
            
            let base64URLSafeString = String(encodedRequest.dropFirst(5))
            
            guard let cborData = base64URLSafeString.decodeBase64UrlSafe() else {
                throw CashuError.paymentRequestDecoding("Could not decode base64 string")
            }
            
            guard let cborValue = try? CBOR.decode([UInt8](cborData)) else {
                throw CashuError.paymentRequestDecoding("Could not decode CBOR data")
            }
            
            self = try CashuSwift.PaymentRequest(fromCBOR: cborValue)
            try self.validate()
        }
    }
}

// MARK: - PaymentRequestPayload

extension CashuSwift {
    /// Represents the payload sent from sender to receiver for a payment request.
    ///
    /// This is the actual payment data transmitted via the chosen transport method.
    public struct PaymentRequestPayload: Codable, Equatable, Sendable {
        
        /// Payment ID corresponding to the payment request
        public let id: String?
        
        /// Optional memo from the sender
        public let memo: String?
        
        /// The mint URL from which the ecash is from
        public let mint: String
        
        /// The unit of the payment
        public let unit: String
        
        /// The array of proofs (ecash) for the payment
        public let proofs: [Proof]
        
        /// Creates a new payment request payload instance.
        /// - Parameters:
        ///   - id: Optional payment ID from the payment request
        ///   - memo: Optional memo from the sender
        ///   - mint: The mint URL
        ///   - unit: The unit of the payment
        ///   - proofs: The proofs for the payment
        public init(id: String?, memo: String?, mint: String, unit: String, proofs: [Proof]) {
            self.id = id
            self.memo = memo
            self.mint = mint
            self.unit = unit
            self.proofs = proofs
        }
        
        /// Calculates the total amount of the payment.
        /// - Returns: The sum of all proof amounts
        public func totalAmount() -> Int {
            return proofs.reduce(0) { $0 + $1.amount }
        }
        
        /// Validates that the payload satisfies a payment request.
        /// - Parameter request: The payment request to validate against
        /// - Throws: An error if validation fails
        public func validates(against request: PaymentRequest) throws {
            // Check payment ID matches
            if let requestId = request.i, requestId != id {
                throw CashuError.paymentRequestValidation("Payment ID mismatch: expected '\(requestId)', got '\(id ?? "nil")'")
            }
            
            // Check unit matches
            if let requestUnit = request.u, requestUnit != unit {
                throw CashuError.paymentRequestValidation("Unit mismatch: expected '\(requestUnit)', got '\(unit)'")
            }
            
            // Check amount matches
            if let requestAmount = request.a {
                let total = totalAmount()
                if total != requestAmount {
                    throw CashuError.paymentRequestValidation("Amount mismatch: expected \(requestAmount), got \(total)")
                }
            }
            
            // Check mint is accepted
            if let acceptedMints = request.m, !acceptedMints.contains(mint) {
                throw CashuError.paymentRequestValidation("Mint '\(mint)' is not in the accepted mints list")
            }
            
            // Check locking conditions if specified
            if let nut10 = request.nut10 {
                try validateLockingConditions(nut10: nut10)
            }
        }
        
        /// Validates that the proofs have the required locking conditions.
        /// - Parameter nut10: The required NUT-10 locking condition
        /// - Throws: An error if the locking conditions are not met
        private func validateLockingConditions(nut10: NUT10Option) throws {
            // Check that all proofs have the required spending condition
            for proof in proofs {
                guard let spendingCondition = SpendingCondition.deserialize(from: proof.secret) else {
                    throw CashuError.lockingConditionMismatch("Proof does not have a spending condition")
                }
                
                // Check kind matches
                if spendingCondition.kind.rawValue != nut10.k {
                    throw CashuError.lockingConditionMismatch("Spending condition kind mismatch: expected '\(nut10.k)', got '\(spendingCondition.kind.rawValue)'")
                }
                
                // Check data matches (public key, hash, etc.)
                if spendingCondition.payload.data != nut10.d {
                    throw CashuError.lockingConditionMismatch("Spending condition data mismatch")
                }
                
                // Validate tags if specified
                let requestedTags = nut10.parsedTags()
                if !requestedTags.isEmpty {
                    let proofTags = spendingCondition.payload.tags ?? []
                    
                    // Check for timeout/locktime requirements
                    if let timeoutValues = requestedTags["timeout"] ?? requestedTags["locktime"],
                       let minTimeout = timeoutValues.compactMap({ Int($0) }).first {
                        
                        var hasValidTimeout = false
                        for tag in proofTags {
                            if case .locktime(let values) = tag {
                                if let proofTimeout = values.first, proofTimeout >= minTimeout {
                                    hasValidTimeout = true
                                    break
                                }
                            }
                        }
                        
                        if !hasValidTimeout {
                            throw CashuError.lockingConditionMismatch("Proof does not have required timeout of at least \(minTimeout) seconds")
                        }
                    }
                }
            }
        }
        
        /// Converts the payload to a Token object.
        /// - Returns: A Token instance
        public func toToken() -> Token {
            return Token(proofs: [mint: proofs], unit: unit, memo: memo)
        }
        
        /// Creates a PaymentRequestPayload from a Token and optional payment request.
        /// - Parameters:
        ///   - token: The token to convert
        ///   - request: Optional payment request to extract ID from
        /// - Returns: A PaymentRequestPayload instance
        /// - Throws: An error if the token has multiple mints
        public static func from(token: Token, request: PaymentRequest?) throws -> PaymentRequestPayload {
            guard token.proofsByMint.count == 1 else {
                throw CashuError.invalidToken
            }
            
            guard let (mintURL, proofs) = token.proofsByMint.first else {
                throw CashuError.invalidToken
            }
            
            return PaymentRequestPayload(
                id: request?.i,
                memo: token.memo,
                mint: mintURL,
                unit: token.unit,
                proofs: proofs
            )
        }
    }
}
