import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Model transport security policy")
struct ModelTransportPolicyTests {
    @Test
    func productionConfigurationHasNoSharedCredentialCookieOrCacheState() {
        let configuration = URLSessionModelFileTransport.productionConfiguration()

        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCache == nil)
        #if os(iOS)
        #expect(configuration.identifier == "com.prismml.BonsaiMobile.model-download")
        #else
        #expect(configuration.identifier == nil)
        #endif
    }

    @Test
    func sanitizationStripsCredentialHeaders() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "Authorization": "Bearer secret",
            "Cookie": "session=secret",
            "Accept": "application/octet-stream"
        ]

        let sanitized = URLSessionModelFileTransport.sanitized(configuration)

        #expect(sanitized.httpAdditionalHeaders?["Authorization"] == nil)
        #expect(sanitized.httpAdditionalHeaders?["Cookie"] == nil)
        #expect(sanitized.httpAdditionalHeaders?["Accept"] as? String == "application/octet-stream")
    }

    @Test
    func redirectsRequireHTTPSAndRejectCredentialBearingRequests() throws {
        let secure = try #require(URL(string: "https://cdn.example/model"))
        let insecure = try #require(URL(string: "http://cdn.example/model"))
        let loopback = try #require(URL(string: "http://127.0.0.1:8080/model"))
        #expect(URLSessionModelFileTransport.sanitizedRedirect(URLRequest(url: secure), permitsLoopback: false) != nil)
        #expect(
            URLSessionModelFileTransport.sanitizedRedirect(
                URLRequest(url: insecure),
                permitsLoopback: false
            ) == nil
        )
        #expect(
            URLSessionModelFileTransport.sanitizedRedirect(
                URLRequest(url: loopback),
                permitsLoopback: true
            ) != nil
        )

        var credentialed = URLRequest(url: secure)
        credentialed.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        #expect(URLSessionModelFileTransport.sanitizedRedirect(credentialed, permitsLoopback: false) == nil)
    }
}
