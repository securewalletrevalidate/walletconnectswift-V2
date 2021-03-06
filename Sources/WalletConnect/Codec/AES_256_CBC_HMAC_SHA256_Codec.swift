// 

import Foundation
import CryptoSwift

protocol Codec {
    var hmacAuthenticator: HMACAutenticating {get}
    func encode(plainText: String, agreementKeys: Crypto.X25519.AgreementKeys) throws -> EncryptionPayload
    func decode(payload: EncryptionPayload, sharedSecret: Data) throws -> String
}

class AES_256_CBC_HMAC_SHA256_Codec: Codec {
    let hmacAuthenticator: HMACAutenticating
    
    init(hmacAuthenticator: HMACAutenticating = HMACAutenticator()) {
        self.hmacAuthenticator = hmacAuthenticator
    }
    
    func encode(plainText: String, agreementKeys: Crypto.X25519.AgreementKeys) throws -> EncryptionPayload {
        let (encryptionKey, authenticationKey) = getKeyPair(from: agreementKeys.sharedSecret)
        let plainTextData = try data(string: plainText)
        let (cipherText, iv) = try encrypt(key: encryptionKey, data: plainTextData)
        let dataToMac = iv + agreementKeys.publicKey + cipherText
        let hmac = try hmacAuthenticator.generateAuthenticationDigest(for: dataToMac, using: authenticationKey)
        return EncryptionPayload(iv: iv,
                                 publicKey: agreementKeys.publicKey,
                                 mac: hmac,
                                 cipherText: cipherText)
    }
    
    func decode(payload: EncryptionPayload, sharedSecret: Data) throws -> String {
        let (decryptionKey, authenticationKey) = getKeyPair(from: sharedSecret)
        let dataToMac = payload.iv + payload.publicKey + payload.cipherText
        try hmacAuthenticator.validateAuthentication(for: dataToMac, with: payload.mac, using: authenticationKey)
        let plainTextData = try decrypt(key: decryptionKey, data: payload.cipherText, iv: payload.iv)
        let plainText = try string(data: plainTextData)
        return plainText
    }

    private func encrypt(key: Data, data: Data) throws -> (cipherText: Data, iv: Data) {
        let iv = AES.randomIV(AES.blockSize)
        let cipher = try AES(key: key.bytes, blockMode: CBC(iv: iv))
        let cipherText = try cipher.encrypt(data.bytes)
        return (Data(cipherText), Data(iv))
    }

    private func decrypt(key: Data, data: Data, iv: Data) throws -> Data {
        let cipher = try AES(key: key.bytes, blockMode: CBC(iv: iv.bytes))
        let plainText = try cipher.decrypt(data.bytes)
        return Data(plainText)
    }

    private func data(string: String) throws -> Data {
        if let data = string.data(using: .utf8) {
            return data
        } else {
            throw CodecError.stringToDataFailed(string)
        }
    }

    private func string(data: Data) throws -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string
        } else {
            throw CodecError.dataToStringFailed(data)
        }
    }

    private func getKeyPair(from keyData: Data) -> (Data, Data) {
        let keySha512 = keyData.sha512()
        let key1 = keySha512.subdata(in: 0..<32)
        let key2 = keySha512.subdata(in: 32..<64)
        return (key1, key2)
    }
}
