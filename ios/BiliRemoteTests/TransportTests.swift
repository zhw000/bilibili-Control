import XCTest
@testable import BiliRemote

final class TransportTests: XCTestCase {
    private func descriptor() throws -> PairingDescriptor {
        guard let url = Bundle(for: Self.self).url(forResource: "fixture", withExtension: "json") else {
            throw XCTSkip("Run scripts/ios-transport-fixture.py --prepare and start the loopback fixture to enable transport tests.")
        }
        return try JSONDecoder().decode(PairingDescriptor.self, from: Data(contentsOf: url))
    }

    @MainActor func testPinnedPairingTextCommandsErrorsAndReconnect() async throws {
        let transport = RemoteTransport()
        defer { transport.disconnect() }
        let config = try await transport.pair(descriptor(), name: "Simulator transport test")
        XCTAssertEqual(config.computerName, "Transport fixture")
        var received = expectation(description: "Authenticated complete snapshot")
        transport.onSnapshot = { state in
            XCTAssertEqual(state.player.currentTime, 42)
            XCTAssertEqual(state.player.partCount, 2)
            XCTAssertEqual(state.systemVolume.value, 0.4)
            received.fulfill()
        }
        transport.connect(config)
        await fulfillment(of: [received], timeout: 15)
        let state: PlayerState = try await transport.request("player.command", params: ["action": .string("seekBy"), "value": .number(10)])
        XCTAssertEqual(state.currentTime, 52)
        do {
            let _: EmptyResponse = try await transport.request("unsupported")
            XCTFail("Expected the remote error")
        } catch let error as RemoteFailure {
            XCTAssertEqual(error.code, "fixture_error")
            XCTAssertEqual(error.message, "测试错误回传")
        }
        transport.disconnect()
        received = expectation(description: "Fresh snapshot after reconnect")
        transport.connect(config)
        await fulfillment(of: [received], timeout: 15)
    }

    @MainActor func testRejectsDifferentCertificate() async throws {
        let valid = try descriptor()
        let changed = PairingDescriptor(version: 1, host: valid.host, port: valid.port,
                                        certificateSha256: String(repeating: "0", count: 64), pairingToken: valid.pairingToken)
        do {
            _ = try await RemoteTransport().pair(changed, name: "Reject certificate test")
            XCTFail("A different certificate must never be accepted")
        } catch { XCTAssertFalse(error is XCTSkip) }
    }
}
