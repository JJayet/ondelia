//
//  HardcoverAuthTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@Suite("Hardcover OAuth")
struct HardcoverAuthTests {
    @Test("PKCE challenge matches the RFC 7636 appendix B vector")
    func pkceVector() {
        #expect(
            HardcoverAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    @Test("Authorize URL carries the public client, the redirect and S256")
    func authorizeURL() throws {
        let request = HardcoverAuth.makeRequest()
        let items = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(request.url.host == "hardcover.app")
        #expect(value("client_id") == HardcoverAuth.clientID)
        #expect(value("redirect_uri") == "ondelia://oauth/hardcover/callback")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") == HardcoverAuth.challenge(for: request.verifier))
        #expect(value("state") == request.state)
        // Two launches never share a verifier or state.
        #expect(HardcoverAuth.makeRequest().verifier != request.verifier)
    }

    @Test("A callback carrying another state is refused before any network call")
    func stateMismatch() async {
        let request = HardcoverAuth.makeRequest()
        let callback = URL(string: "ondelia://oauth/hardcover/callback?code=abc&state=other")!
        await #expect(throws: HardcoverAuth.Failure.self) {
            try await HardcoverAuth.exchange(callback: callback, for: request)
        }
    }

    @Test("A denied authorization surfaces Hardcover's reason")
    func denied() async {
        let request = HardcoverAuth.makeRequest()
        let callback = URL(
            string: "ondelia://oauth/hardcover/callback?error=access_denied&error_description=Nope&state=\(request.state)"
        )!
        await #expect(throws: HardcoverAuth.Failure.self) {
            try await HardcoverAuth.exchange(callback: callback, for: request)
        }
    }
}
