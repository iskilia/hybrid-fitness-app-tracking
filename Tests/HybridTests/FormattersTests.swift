import XCTest
@testable import Hybrid

// MARK: - FormattersTests
// Tests for shared formatters (items 1-3) and RunTemplate.metaLine (item 4).

final class FormattersTests: XCTestCase {

    // MARK: - formattedDuration

    func testDuration_underOneHour() {
        XCTAssertEqual(formattedDuration(0), "00:00")
        XCTAssertEqual(formattedDuration(65), "01:05")
        XCTAssertEqual(formattedDuration(3599), "59:59")
    }

    func testDuration_oneHourExact() {
        XCTAssertEqual(formattedDuration(3600), "1:00:00")
    }

    func testDuration_overOneHour() {
        XCTAssertEqual(formattedDuration(3725), "1:02:05")
        XCTAssertEqual(formattedDuration(36000), "10:00:00")
    }

    // MARK: - kmLabel

    func testKmLabel_wholeNumber() {
        XCTAssertEqual(kmLabel(5.0), "5.0 KM")
        XCTAssertEqual(kmLabel(10.0), "10.0 KM")
    }

    func testKmLabel_fractional() {
        XCTAssertEqual(kmLabel(10.5), "10.5 KM")
        XCTAssertEqual(kmLabel(0.4), "0.4 KM")
    }

    // MARK: - paceLabel

    func testPaceLabel_roundMinutes() {
        XCTAssertEqual(paceLabel(300), "5:00 /KM")
    }

    func testPaceLabel_minutesAndSeconds() {
        XCTAssertEqual(paceLabel(270), "4:30 /KM")
        XCTAssertEqual(paceLabel(193), "3:13 /KM")
    }

    // MARK: - RunTemplate.metaLine

    // Fixture that matches all fields so callers can opt-in selectively.
    private func makeTemplate(
        runType: RunType = .steady,
        distanceKm: Double? = 10.0,
        paceSecsMin: Int? = 300,
        hrBpmMin: Int? = 140,
        hrBpmMax: Int? = 160,
        hrZoneMin: Int? = 2,
        hrZoneMax: Int? = 3
    ) -> RunTemplate {
        RunTemplate(
            id: 1,
            clientUUID: UUID(),
            name: "Test Run",
            runType: runType,
            targetTotalDistanceKm: distanceKm,
            targetWorkDistanceKm: nil,
            targetPaceSecsMin: paceSecsMin,
            targetPaceSecsMax: nil,
            hrZoneMin: hrZoneMin,
            hrZoneMax: hrZoneMax,
            hrBpmMin: hrBpmMin,
            hrBpmMax: hrBpmMax,
            isCustom: false,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil
        )
    }

    /// RunTypesView variant: includeRunType=true, includeBpm=true, includeZone=false
    func testMetaLine_runTypesViewVariant() {
        let tmpl = makeTemplate()
        let result = tmpl.metaLine(includeRunType: true, includeBpm: true, includeZone: false)
        XCTAssertEqual(result, "STEADY · 10.0 KM · 5:00 /KM · 140\u{2013}160 BPM")
    }

    /// RunRow variant: includeRunType=true, includeBpm=false, includeZone=true
    func testMetaLine_runRowVariant() {
        let tmpl = makeTemplate()
        let result = tmpl.metaLine(includeRunType: true, includeBpm: false, includeZone: true)
        XCTAssertEqual(result, "STEADY · 10.0 KM · 5:00 /KM · Z2-3")
    }

    /// MixedActiveSessionView subLine variant: includeRunType=false, includeBpm=false, includeZone=true
    func testMetaLine_subLineVariant() {
        let tmpl = makeTemplate()
        let result = tmpl.metaLine(includeRunType: false, includeBpm: false, includeZone: true)
        XCTAssertEqual(result, "10.0 KM · 5:00 /KM · Z2-3")
    }

    /// Missing optional fields are omitted gracefully.
    func testMetaLine_missingOptionalFields() {
        let tmpl = makeTemplate(distanceKm: nil, paceSecsMin: nil, hrBpmMin: nil, hrBpmMax: nil, hrZoneMin: nil, hrZoneMax: nil)
        XCTAssertEqual(tmpl.metaLine(includeRunType: true, includeBpm: true, includeZone: true), "STEADY")
    }

    /// BPM field is omitted when includeBpm is false, even if values are present.
    func testMetaLine_bpmOmittedWhenFlagFalse() {
        let tmpl = makeTemplate()
        let result = tmpl.metaLine(includeRunType: false, includeBpm: false, includeZone: false)
        XCTAssertEqual(result, "10.0 KM · 5:00 /KM")
    }

    /// Zone field is omitted when includeZone is false, even if values are present.
    func testMetaLine_zoneOmittedWhenFlagFalse() {
        let tmpl = makeTemplate()
        let result = tmpl.metaLine(includeRunType: false, includeBpm: false, includeZone: false)
        XCTAssertFalse(result.contains("Z2-3"))
    }
}
