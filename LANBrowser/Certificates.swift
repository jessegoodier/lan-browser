import CryptoKit
import Foundation
import Security

/// One certificate from a server’s chain, with the details people compare against the device.
struct CertificateSummary: Equatable, Sendable {
    let subject: String
    let commonName: String?
    let notBefore: Date?
    let notAfter: Date?
    let serialNumber: String?
    let sha256: String
    let key: String?

    init(_ certificate: SecCertificate) {
        subject = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown"
        var name: CFString?
        commonName = SecCertificateCopyCommonName(certificate, &name) == errSecSuccess ? name as String? : nil
        if #available(iOS 18.0, macOS 15.0, *) {
            notBefore = SecCertificateCopyNotValidBeforeDate(certificate) as Date?
            notAfter = SecCertificateCopyNotValidAfterDate(certificate) as Date?
        } else {
            notBefore = nil
            notAfter = nil
        }
        serialNumber = (SecCertificateCopySerialNumberData(certificate, nil) as Data?).map { Self.hex($0) }
        sha256 = Self.hex(Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data)))
        if let publicKey = SecCertificateCopyKey(certificate),
           let attributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any] {
            let type = (attributes[kSecAttrKeyType] as? String).map { $0 == (kSecAttrKeyTypeRSA as String) ? "RSA" : $0 == (kSecAttrKeyTypeECSECPrimeRandom as String) ? "EC" : $0 }
            let bits = attributes[kSecAttrKeySizeInBits] as? Int
            key = [type, bits.map { "\($0) bits" }].compactMap { $0 }.joined(separator: " ")
        } else {
            key = nil
        }
    }

    /// Colon-separated uppercase hex, the form most devices show fingerprints and serials in.
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// A certificate the system couldn’t verify, for a page LAN Browser opened anyway.
struct CertificateIssue: Identifiable, Equatable, Sendable {
    let id = UUID()
    let host: String
    /// The system’s own explanation, verbatim.
    let error: String
    let errorCode: Int?
    let chain: [CertificateSummary]

    init(host: String, trust: SecTrust, error: CFError?) {
        self.host = host
        self.error = error.map { CFErrorCopyDescription($0) as String } ?? "The certificate isn’t trusted."
        errorCode = error.map { CFErrorGetCode($0) }
        chain = ((SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []).map(CertificateSummary.init)
    }

    /// Plain text of everything shown, for comparing or reporting.
    var report: String {
        var lines = ["Certificate not trusted: \(host)", error]
        if let errorCode { lines.append("Error code: \(errorCode)") }
        for (index, certificate) in chain.enumerated() {
            lines.append("")
            lines.append("Certificate \(index + 1): \(certificate.subject)")
            if let commonName = certificate.commonName { lines.append("Common name: \(commonName)") }
            if let notBefore = certificate.notBefore { lines.append("Valid from: \(notBefore.formatted(date: .abbreviated, time: .shortened))") }
            if let notAfter = certificate.notAfter { lines.append("Valid until: \(notAfter.formatted(date: .abbreviated, time: .shortened))") }
            if let serial = certificate.serialNumber { lines.append("Serial: \(serial)") }
            if let key = certificate.key { lines.append("Key: \(key)") }
            lines.append("SHA-256: \(certificate.sha256)")
        }
        return lines.joined(separator: "\n")
    }
}
