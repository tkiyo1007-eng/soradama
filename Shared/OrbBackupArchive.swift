import Foundation

/// 利用者が明示的に書き出す空玉コレクションのバックアップ形式。
/// 将来フィールドが増えても読み分けられるよう、最初からスキーマ番号を持たせる。
struct OrbBackupArchive: Codable, Equatable {
    let schemaVersion: Int
    let exportedAt: Date
    let orbs: [String: DailyOrb]
}

enum OrbBackupError: Error, Equatable {
    case fileTooLarge
    case unsupportedSchemaVersion(Int)
    case tooManyOrbs
    case inconsistentDateKey
    case invalidOrbData
    case collectionChanged
    case persistenceFailed
}

struct OrbBackupImportResult: Equatable {
    let insertedCount: Int
    let replacedCount: Int
}

struct OrbBackupMergeOutcome: Equatable {
    let orbs: [String: DailyOrb]
    let result: OrbBackupImportResult
}

/// ファイル入出力と検証を純粋ロジックにまとめ、壊れたJSONや過大なファイルを
/// UserDefaultsへ書く前に確実に拒否する。
enum OrbBackupCodec {
    static let schemaVersion = 1
    static let maximumDataSize = 10 * 1_024 * 1_024
    static let maximumOrbCount = 10_000
    static let maximumPlaceNameCharacters = 256
    static let maximumPlaceNameUTF8Bytes = 1_024

    static func encode(
        orbs: [String: DailyOrb],
        exportedAt: Date = Date()
    ) throws -> Data {
        try validate(orbs)
        let archive = OrbBackupArchive(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            orbs: orbs
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maximumDataSize else {
            throw OrbBackupError.fileTooLarge
        }
        return data
    }

    static func decode(_ data: Data) throws -> OrbBackupArchive {
        guard data.count <= maximumDataSize else {
            throw OrbBackupError.fileTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(OrbBackupArchive.self, from: data)
        guard archive.schemaVersion == schemaVersion else {
            throw OrbBackupError.unsupportedSchemaVersion(archive.schemaVersion)
        }
        try validate(archive.orbs)
        return archive
    }

    /// 復元時は既存コレクションを消さず、同じ日だけバックアップ側を採用する。
    /// 読み込み操作の直前に結果件数を表示できるよう、追加・更新を分けて返す。
    static func merging(
        existing: [String: DailyOrb],
        importing: [String: DailyOrb]
    ) throws -> OrbBackupMergeOutcome {
        try validate(existing)
        try validate(importing)
        var merged = existing
        var insertedCount = 0
        var replacedCount = 0
        for (key, orb) in importing {
            if existing[key] == nil {
                insertedCount += 1
            } else if existing[key] != orb {
                replacedCount += 1
            }
            merged[key] = orb
        }
        try validate(merged)
        // importing と existing が個別には上限内でも、結合後だけ10MBを超える
        // 可能性がある。永続状態を変更する前に完成形を実際にserializeして検査する。
        _ = try encode(orbs: merged)
        return OrbBackupMergeOutcome(
            orbs: merged,
            result: OrbBackupImportResult(
                insertedCount: insertedCount,
                replacedCount: replacedCount
            )
        )
    }

    private static func validate(_ orbs: [String: DailyOrb]) throws {
        guard orbs.count <= maximumOrbCount else {
            throw OrbBackupError.tooManyOrbs
        }
        guard orbs.allSatisfy({ key, orb in
            key == orb.dateKey && isValidDateKey(key)
        }) else {
            throw OrbBackupError.inconsistentDateKey
        }
        guard orbs.values.allSatisfy(isValidOrb) else {
            throw OrbBackupError.invalidOrbData
        }
    }

    private static func isValidOrb(_ orb: DailyOrb) -> Bool {
        let trimmedName = orb.placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              orb.placeName.count <= maximumPlaceNameCharacters,
              orb.placeName.utf8.count <= maximumPlaceNameUTF8Bytes,
              orb.tempMin.isFinite,
              orb.tempMax.isFinite,
              (-100...70).contains(orb.tempMin),
              (-100...70).contains(orb.tempMax),
              orb.tempMin <= orb.tempMax,
              orb.humidity.isFinite,
              (0...100).contains(orb.humidity) else {
            return false
        }
        if let precipitation = orb.precipProbability {
            return precipitation.isFinite && (0...100).contains(precipitation)
        }
        return true
    }

    /// ファイル提供元がサイズを返さない場合も、上限+1バイトで必ず読み止める。
    static func readData(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        let chunkSize = 64 * 1_024
        while true {
            let remaining = maximumDataSize - data.count
            guard remaining >= 0 else { throw OrbBackupError.fileTooLarge }
            let chunk = try handle.read(upToCount: min(chunkSize, remaining + 1)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
            guard data.count <= maximumDataSize else {
                throw OrbBackupError.fileTooLarge
            }
        }
        return data
    }

    private static func isValidDateKey(_ key: String) -> Bool {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard key.count == 10,
              parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )) else {
            return false
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }
}
