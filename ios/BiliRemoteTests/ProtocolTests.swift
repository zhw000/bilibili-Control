import XCTest
@testable import BiliRemote

final class ProtocolTests: XCTestCase {
    func testExactTimeParsing() throws {
        XCTAssertEqual(try Timecode.parse("12:30"), 750)
        XCTAssertEqual(try Timecode.parse("1:02:03"), 3723)
        XCTAssertEqual(try Timecode.parse("120:00"), 7200)
        for value in ["1:60", "1:99:00", "-1:00", "12", "1::3"] { XCTAssertThrowsError(try Timecode.parse(value)) }
        XCTAssertEqual(Timecode.format(3723), "1:02:03")
    }
    func testPairingValidation() throws {
        let valid = PairingDescriptor(version: 1, host: "192.168.1.8", port: 33391, certificateSha256: String(repeating: "a", count: 64), pairingToken: String(repeating: "b", count: 43))
        func link(_ descriptor: PairingDescriptor) throws -> String { "biliremote://pair?data=" + (try JSONEncoder().encode(descriptor)).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        XCTAssertEqual(try PairingDescriptor.parse(link(valid)).host, valid.host)
        XCTAssertThrowsError(try PairingDescriptor.parse("https://attacker.test/pair"))
        let invalid = PairingDescriptor(version: 1, host: "192.168.1.8/evil", port: 33391, certificateSha256: valid.certificateSha256, pairingToken: valid.pairingToken)
        XCTAssertThrowsError(try PairingDescriptor.parse(link(invalid)))
    }
    func testJSONValuePreservesBooleanAndNumericTypes() throws {
        let data = Data(#"{"muted":true,"volume":0.35,"part":2}"#.utf8)
        struct Example: Decodable { let muted: Bool; let volume: Double; let part: Int }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let decoded = try value.decode(Example.self)
        XCTAssertTrue(decoded.muted); XCTAssertEqual(decoded.volume, 0.35); XCTAssertEqual(decoded.part, 2)
    }
}
