//
//  File.swift
//  CashuSwift
//
//  Created by zm on 07.04.25.
//

import Foundation
import secp256k1
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

extension CashuSwift {
    public static func loadMint<T: MintRepresenting>(url:URL, type:T.Type = Mint.self) async throws -> T {
        let keysetList = try await Network.get(url: url.appending(path: "/v1/keysets"),
                                               expected: KeysetList.self)
        var keysetsWithKeys = [Keyset]()
        for keyset in keysetList.keysets {
            var new = keyset
            new.keys = try await Network.get(url: url.appending(path: "/v1/keys/\(keyset.keysetID.urlSafe)"),
                                             expected: KeysetList.self).keysets[0].keys
            keysetsWithKeys.append(new)
        }
        
        return T(url: url, keysets: keysetsWithKeys)
    }
    
    public static func loadInfoFromMint(_ mint:MintRepresenting) async throws -> MintInfo? {
        let mintInfoData = try await Network.get(url: mint.url.appending(path: "v1/info"))!
        
        if let info = try? JSONDecoder().decode(MintInfo0_16.self, from: mintInfoData) {
            return info
        } else if let info = try? JSONDecoder().decode(MintInfo0_15.self, from: mintInfoData) {
            return info
        } else if let info = try? JSONDecoder().decode(MintInfo.self, from: mintInfoData) {
            return info
        } else {
            logger.warning("Could not parse mint info of \(mint.url.absoluteString) to any known version.")
            return nil
        }
    }
    
    public static func update(_ mint: inout MintRepresenting) async throws {
        let mintURL = mint.url  // Create a local copy of the URL
        let remoteKeysetList = try await Network.get(url: mintURL.appending(path: "/v1/keysets"),
                                                     expected: KeysetList.self)
        
        let remoteIDs = remoteKeysetList.keysets.reduce(into: [String:Bool]()) { partialResult, keyset in
            partialResult[keyset.keysetID] = keyset.active
        }
        
        let localIDs = mint.keysets.reduce(into: [String:Bool]()) { partialResult, keyset in
            partialResult[keyset.keysetID] = keyset.active
        }
        
        logger.debug("Updating local representation of mint \(mintURL)...")
        
        if remoteIDs != localIDs {
            logger.debug("List of keysets changed.")
            var keysetsWithKeys = [Keyset]()
            for keyset in remoteKeysetList.keysets {
                var new = keyset
                new.keys = try await Network.get(url: mintURL.appending(path: "/v1/keys/\(keyset.keysetID.urlSafe)"),
                                                 expected: KeysetList.self).keysets[0].keys
                keysetsWithKeys.append(new)
            }
            mint.keysets = keysetsWithKeys
        } else {
            logger.debug("No changes in list of keysets.")
        }
    }
    
    public static func updatedKeysetsForMint(_ mint:MintRepresenting) async throws -> [Keyset] {
        let mintURL = mint.url
        let remoteKeysetList = try await Network.get(url: mintURL.appending(path: "/v1/keysets"),
                                                     expected: KeysetList.self)
        
        let remoteIDs = remoteKeysetList.keysets.reduce(into: [String:Bool]()) { partialResult, keyset in
            partialResult[keyset.keysetID] = keyset.active
        }
        
        let localIDs = mint.keysets.reduce(into: [String:Bool]()) { partialResult, keyset in
            partialResult[keyset.keysetID] = keyset.active
        }
        
        logger.debug("Updating local representation of mint \(mintURL)...")
        
        if remoteIDs != localIDs {
            logger.debug("List of keysets changed.")
            var keysetsWithKeys = [Keyset]()
            for keyset in remoteKeysetList.keysets {
                var new = keyset
                new.keys = try await Network.get(url: mintURL.appending(path: "/v1/keys/\(keyset.keysetID.urlSafe)"),
                                                 expected: KeysetList.self).keysets[0].keys
                
                let detsecCounter = mint.keysets.first(where: {$0.keysetID == keyset.keysetID})?.derivationCounter ?? 0
                new.derivationCounter = detsecCounter
                keysetsWithKeys.append(new)
            }
            return keysetsWithKeys
        } else {
            logger.debug("No changes in list of keysets.")
            return mint.keysets
        }
    }

    
    public static func loadMint(url: URL) async throws -> Mint {
        return try await loadMint(url: url, type: Mint.self)
    }
}
