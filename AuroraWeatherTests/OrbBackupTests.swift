import Testing
import Foundation
@testable import AuroraWeather

struct OrbBackupTests {
    @Test("空玉バックアップはJSONを往復できる")
    func roundTrip() throws {
        let orb = Self.orb(dateKey: "2026-08-30", placeName: "Sydney")
        let exportedAt = Date(timeIntervalSince1970: 1_788_045_600)
        let data = try OrbBackupCodec.encode(
            orbs: [orb.dateKey: orb],
            exportedAt: exportedAt
        )
        let decoded = try OrbBackupCodec.decode(data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.exportedAt == exportedAt)
        #expect(decoded.orbs == [orb.dateKey: orb])
    }

    @Test("復元は既存の別日を残し同じ日だけ更新する")
    func mergeKeepsExistingDays() throws {
        let existingA = Self.orb(dateKey: "2026-08-28", placeName: "Tokyo")
        let existingB = Self.orb(dateKey: "2026-08-29", placeName: "Tokyo")
        let replacementB = Self.orb(dateKey: "2026-08-29", placeName: "London")
        let importedC = Self.orb(dateKey: "2026-08-30", placeName: "Sydney")

        let outcome = try OrbBackupCodec.merging(
            existing: [existingA.dateKey: existingA, existingB.dateKey: existingB],
            importing: [replacementB.dateKey: replacementB, importedC.dateKey: importedC]
        )

        #expect(outcome.orbs.count == 3)
        #expect(outcome.orbs[existingA.dateKey] == existingA)
        #expect(outcome.orbs[replacementB.dateKey] == replacementB)
        #expect(outcome.result == OrbBackupImportResult(insertedCount: 1, replacedCount: 1))
    }

    @Test("結合後の件数が上限を超える復元は拒否する")
    func mergeRejectsTooManyOrbs() {
        var existing: [String: DailyOrb] = [:]
        var date = Date(timeIntervalSince1970: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for _ in 0..<OrbBackupCodec.maximumOrbCount {
            let key = formatter.string(from: date)
            existing[key] = Self.orb(dateKey: key, placeName: "Tokyo")
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        let extra = Self.orb(dateKey: "2030-01-01", placeName: "Paris")

        #expect(throws: OrbBackupError.tooManyOrbs) {
            _ = try OrbBackupCodec.merging(
                existing: existing,
                importing: [extra.dateKey: extra]
            )
        }
    }

    @Test("キーと空玉の日付が違うバックアップは拒否する")
    func rejectsMismatchedDateKey() {
        let orb = Self.orb(dateKey: "2026-08-30", placeName: "Paris")
        #expect(throws: OrbBackupError.inconsistentDateKey) {
            _ = try OrbBackupCodec.encode(orbs: ["2026-08-29": orb])
        }
    }

    @Test("存在しない日付のバックアップは拒否する")
    func rejectsInvalidCalendarDate() {
        let orb = Self.orb(dateKey: "2026-02-30", placeName: "Paris")
        #expect(throws: OrbBackupError.inconsistentDateKey) {
            _ = try OrbBackupCodec.encode(orbs: [orb.dateKey: orb])
        }
    }

    @Test("上限を超えるファイルはデコード前に拒否する")
    func rejectsOversizedData() {
        let data = Data(repeating: 0, count: OrbBackupCodec.maximumDataSize + 1)
        #expect(throws: OrbBackupError.fileTooLarge) {
            _ = try OrbBackupCodec.decode(data)
        }
    }

    @Test("異常な数値や地点名を持つ空玉は永続化前に拒否する")
    func rejectsUnsafeOrbValues() {
        let invalidOrbs = [
            Self.orb(dateKey: "2026-08-30", placeName: "Tokyo", tempMax: 1e300),
            Self.orb(dateKey: "2026-08-30", placeName: "Tokyo", tempMin: -101),
            Self.orb(dateKey: "2026-08-30", placeName: "Tokyo", tempMax: 10, tempMin: 20),
            Self.orb(dateKey: "2026-08-30", placeName: "Tokyo", humidity: -1),
            Self.orb(dateKey: "2026-08-30", placeName: "Tokyo", precipitation: 101),
            Self.orb(dateKey: "2026-08-30", placeName: "   "),
            Self.orb(
                dateKey: "2026-08-30",
                placeName: String(repeating: "a", count: OrbBackupCodec.maximumPlaceNameCharacters + 1)
            ),
        ]

        for orb in invalidOrbs {
            #expect(throws: OrbBackupError.invalidOrbData) {
                _ = try OrbBackupCodec.encode(orbs: [orb.dateKey: orb])
            }
        }
    }

    @Test("個別には上限内でも結合後に10MBを超える復元は拒否する")
    func mergeRejectsOversizedFinalArchive() throws {
        var existing: [String: DailyOrb] = [:]
        var importing: [String: DailyOrb] = [:]
        var date = Date(timeIntervalSince1970: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let longName = String(
            repeating: "🌏",
            count: OrbBackupCodec.maximumPlaceNameCharacters
        )

        for index in 0..<OrbBackupCodec.maximumOrbCount {
            let key = formatter.string(from: date)
            let orb = Self.orb(dateKey: key, placeName: longName)
            if index < OrbBackupCodec.maximumOrbCount / 2 {
                existing[key] = orb
            } else {
                importing[key] = orb
            }
            date = try #require(calendar.date(byAdding: .day, value: 1, to: date))
        }

        #expect(try OrbBackupCodec.encode(orbs: existing).count <= OrbBackupCodec.maximumDataSize)
        #expect(try OrbBackupCodec.encode(orbs: importing).count <= OrbBackupCodec.maximumDataSize)
        #expect(throws: OrbBackupError.fileTooLarge) {
            _ = try OrbBackupCodec.merging(existing: existing, importing: importing)
        }
    }

    @Test("サイズ不明のファイルも上限を1バイト超えた時点で読み込みを止める")
    func limitedReaderRejectsOversizedFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbBackupTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: OrbBackupCodec.maximumDataSize + 1).write(to: url)

        #expect(throws: OrbBackupError.fileTooLarge) {
            _ = try OrbBackupCodec.readData(from: url)
        }
    }

    private static func orb(
        dateKey: String,
        placeName: String,
        tempMax: Double = 24,
        tempMin: Double = 16,
        humidity: Double = 55,
        precipitation: Double? = 10
    ) -> DailyOrb {
        DailyOrb(
            dateKey: dateKey,
            kind: .clear,
            tempMax: tempMax,
            tempMin: tempMin,
            humidity: humidity,
            precipProbability: precipitation,
            placeName: placeName,
            hemisphere: placeName == "Sydney" ? .southern : .northern
        )
    }
}
