import Foundation
import CryptoKit

/// Helper to sign HTTP requests with AWS Signature Version 4.
internal struct AWSSigV4Signer {
    static func sign(
        request: inout URLRequest,
        body: Data,
        service: String = "polly",
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        currentDate: Date = Date()
    ) {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: currentDate)
        
        formatter.dateFormat = "yyyyMMdd"
        let dateStamp = formatter.string(from: currentDate)
        
        guard let url = request.url, let host = url.host else { return }
        
        // Ensure standard headers
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let method = request.httpMethod ?? "POST"
        let path = url.path.isEmpty ? "/" : url.path
        
        // 1. Create Canonical Request
        let canonicalHeaders = "content-type:application/json\nhost:\(host)\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "content-type;host;x-amz-date"
        
        let payloadHash = sha256(body)
        
        let canonicalRequest = "\(method)\n\(path)\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let canonicalRequestHash = sha256(canonicalRequest.data(using: .utf8)!)
        
        // 2. Create String to Sign
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(credentialScope)\n\(canonicalRequestHash)"
        
        // 3. Calculate Signature Key
        let kDate = hmac(key: "AWS4\(secretAccessKey)".data(using: .utf8)!, data: dateStamp.data(using: .utf8)!)
        let kRegion = hmac(key: kDate, data: region.data(using: .utf8)!)
        let kService = hmac(key: kRegion, data: service.data(using: .utf8)!)
        let kSigning = hmac(key: kService, data: "aws4_request".data(using: .utf8)!)
        
        // 4. Calculate Signature
        let signature = hmac(key: kSigning, data: stringToSign.data(using: .utf8)!)
        let signatureStr = signature.map { String(format: "%02x", $0) }.joined()
        
        // 5. Add Authorization Header
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signatureStr)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }
    
    private static func sha256(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private static func hmac(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let code = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(code)
    }
}
