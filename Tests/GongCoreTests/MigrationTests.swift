import XCTest
@testable import GongCore

/// 老记录必须读得出来。
///
/// 这一条是有真实风险的：Swift 合成的 `Codable` **在缺键时会抛错**，
/// 非可选字段哪怕写了默认值也救不了旧 JSON。加字段时如果不管，
/// 结果就是打开历史某天报「读取当日记录失败」，用户看到的就是数据没了。
/// 所以 `DayRecord` / `DaySummary` / `FloorItem` 都改成手写 `decodeIfPresent`。
final class SchemaMigrationTests: XCTestCase {

    private func decode(_ json: String) throws -> DayRecord {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(DayRecord.self, from: json.data(using: .utf8)!)
    }

    /// 用户机器上真实存在的那种记录：没有 floor、没有 wins、没有 tomorrow。
    func testOldRecordWithoutNewFieldsStillDecodes() throws {
        let json = """
        {
          "schemaVersion": 1,
          "key": {"date":"2026-09-01","timeZoneIdentifier":"Australia/Perth",
                  "calendarIdentifier":"gregorian"},
          "todos": [{"id":"\(UUID().uuidString)","text":"1. Shenton Park",
                     "status":"notRecorded","kind":"normal","order":0}],
          "planned": [], "actual": [],
          "summary": {"touched":"今天没被小说带走","clarity":[],"freeText":""},
          "breaker": {"interruptions":[],"timerRuns":0},
          "updatedAt": "2026-09-01T10:00:00Z",
          "revision": 3
        }
        """
        let rec = try decode(json)
        XCTAssertEqual(rec.todos.first?.text, "1. Shenton Park")
        XCTAssertEqual(rec.summary.touched, "今天没被小说带走")
        XCTAssertEqual(rec.revision, 3)
        // 新字段取默认值，不该抛错
        XCTAssertEqual(rec.floor.text, "")
        XCTAssertEqual(rec.floor.status, .notRecorded)
        XCTAssertTrue(rec.summary.wins.isEmpty)
        XCTAssertEqual(rec.summary.tomorrow, "")
    }

    /// 更老的记录：连 summary / breaker 整段都没有。
    func testVeryOldRecordWithMissingSectionsDecodes() throws {
        let json = """
        {
          "key": {"date":"2026-08-31","timeZoneIdentifier":"Australia/Perth",
                  "calendarIdentifier":"gregorian"}
        }
        """
        let rec = try decode(json)
        XCTAssertEqual(rec.date, "2026-08-31")
        XCTAssertTrue(rec.todos.isEmpty)
        XCTAssertEqual(rec.summary.touched, "")
        XCTAssertEqual(rec.revision, 0)
    }

    /// 老版本把下限做成 TODO 上的一个标记。迁移时要搬到独立字段，
    /// **并从 TODO 列表里移除**，否则同一件事会出现两遍。
    func testLegacyFloorTodoMigratesOutOfTheList() throws {
        let json = """
        {
          "key": {"date":"2026-08-30","timeZoneIdentifier":"Australia/Perth",
                  "calendarIdentifier":"gregorian"},
          "todos": [
            {"id":"\(UUID().uuidString)","text":"23:00 前睡觉","status":"done",
             "kind":"floor","order":0},
            {"id":"\(UUID().uuidString)","text":"写周报","status":"notRecorded",
             "kind":"normal","order":1}
          ]
        }
        """
        let rec = try decode(json)
        XCTAssertEqual(rec.floor.text, "23:00 前睡觉", "下限应搬进独立字段")
        XCTAssertEqual(rec.floor.status, .done, "完成状态要一起搬过来")
        XCTAssertEqual(rec.todos.map(\.text), ["写周报"], "下限不该在 TODO 里留下副本")
    }

    /// 新字段存在时按原样读，不被迁移逻辑覆盖。
    func testExistingFloorFieldWins() throws {
        let json = """
        {
          "key": {"date":"2026-09-02","timeZoneIdentifier":"Australia/Perth",
                  "calendarIdentifier":"gregorian"},
          "floor": {"text":"新的下限","status":"done"},
          "todos": [{"id":"\(UUID().uuidString)","text":"旧的下限","status":"notRecorded",
                     "kind":"floor","order":0}]
        }
        """
        let rec = try decode(json)
        XCTAssertEqual(rec.floor.text, "新的下限")
        XCTAssertEqual(rec.todos.count, 1, "已有 floor 字段时不做迁移，TODO 原样保留")
    }

    /// 编解码往返：新字段写出去再读回来必须一致。
    func testRoundTripPreservesNewFields() throws {
        var rec = DayRecord(date: "2026-09-02")
        rec.floor.text = "23:00 前睡觉"
        rec.floor.status = .done
        rec.summary.wins = [WinEntry(text: "发出了那封邮件")]
        rec.summary.tomorrow = "上午不排会"

        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let back = try decode(String(data: try e.encode(rec), encoding: .utf8)!)

        XCTAssertEqual(back.floor.text, "23:00 前睡觉")
        XCTAssertEqual(back.floor.status, .done)
        XCTAssertEqual(back.summary.wins.map(\.text), ["发出了那封邮件"])
        XCTAssertEqual(back.summary.tomorrow, "上午不排会")
    }
}
