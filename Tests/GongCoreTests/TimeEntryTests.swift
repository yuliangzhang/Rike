import XCTest
@testable import GongCore

/// 时间输入框的键盘效率。
///
/// 用户反馈：框里是 `21:16`，点进去光标停在点中的位置，直接敲 `1400`
/// 会插成一串垃圾，必须先用鼠标把原值圈掉才能重打。
///
/// 修法两半：
/// ① 获得焦点时全选（AppKit 行为，只能实机验，这里测不到）；
/// ② 边打边过滤 + 宽松解析（这两半在这里测）。
final class TimeEntryFieldTests: XCTestCase {

    // MARK: 用户报的那一幕

    /// 全选之后敲 `1400`，提交时必须变成 14:00。
    func testTypingFourDigitsOverAnExistingValueGives1400() {
        let typed = TimeEntryField.sanitize("1400")
        XCTAssertEqual(typed, "1400", "四位数字不该被过滤掉任何一位")
        guard let m = GongTime.parseMinutes(typed) else {
            return XCTFail("1400 应能解析")
        }
        XCTAssertEqual(m, 14 * 60)
        XCTAssertEqual(GongTime.formatMinutes(m), "14:00")
    }

    /// 常用的几种打法都要通，手不用离开键盘。
    func testCommonTypingShapes() {
        let cases: [(String, String)] = [
            ("9",     "09:00"),
            ("09",    "09:00"),
            ("930",   "09:30"),
            ("0930",  "09:30"),
            ("9:30",  "09:30"),
            ("09:30", "09:30"),
            ("1400",  "14:00"),
            ("14:00", "14:00"),
            ("2359",  "23:59"),
            ("0",     "00:00")
        ]
        for (typed, expected) in cases {
            let clean = TimeEntryField.sanitize(typed)
            guard let m = GongTime.parseMinutes(clean) else {
                XCTFail("「\(typed)」应能解析，过滤后是「\(clean)」")
                continue
            }
            XCTAssertEqual(GongTime.formatMinutes(m), expected, "输入「\(typed)」")
        }
    }

    // MARK: 边打边过滤

    /// 字母进不来。否则要等失焦才发现解析失败、整段被还原，白打一遍。
    func testLettersAreFilteredOut() {
        XCTAssertEqual(TimeEntryField.sanitize("14ab00"), "1400")
        XCTAssertEqual(TimeEntryField.sanitize("abc"), "")
    }

    /// 中文输入法敲出来的是全角冒号，要归一成半角。
    func testFullWidthColonIsNormalised() {
        XCTAssertEqual(TimeEntryField.sanitize("9：30"), "9:30")
        XCTAssertEqual(GongTime.parseMinutes(TimeEntryField.sanitize("9：30")), 9 * 60 + 30)
    }

    /// 只留第一个冒号。`9::30` 这种连击不该把整段变成不可解析。
    func testOnlyFirstColonKept() {
        XCTAssertEqual(TimeEntryField.sanitize("9::30"), "9:30")
        XCTAssertEqual(TimeEntryField.sanitize("1:2:3"), "1:23")
    }

    /// 最长 5 个字符（`09:30`）。多敲的直接不进来，而不是攒到提交时才整段还原。
    func testLengthIsCapped() {
        XCTAssertEqual(TimeEntryField.sanitize("140000"), "14000")
        XCTAssertEqual(TimeEntryField.sanitize("09:30:45"), "09:30")
    }

    /// 过滤是幂等的：`onChange` 里回写 text 会再触发一次 onChange，
    /// 不幂等就会无限循环。
    func testSanitizeIsIdempotent() {
        for raw in ["1400", "9：30", "14ab00", "140000", "1:2:3", "", ":::"] {
            let once = TimeEntryField.sanitize(raw)
            XCTAssertEqual(TimeEntryField.sanitize(once), once, "「\(raw)」的过滤不幂等")
        }
    }

    /// 过滤不能把本来合法的输入弄坏。
    func testValidInputPassesThroughUnchanged() {
        for raw in ["9", "09", "930", "0930", "9:30", "09:30", "1400", "24:00"] {
            XCTAssertEqual(TimeEntryField.sanitize(raw), raw, "「\(raw)」不该被改动")
        }
    }

    /// 过滤后仍然可能解析失败（例如只剩一个冒号），此时走原有的「还原不吞掉」路径。
    func testUnparseableAfterSanitizeStillReturnsNil() {
        XCTAssertNil(GongTime.parseMinutes(TimeEntryField.sanitize(":")))
        XCTAssertNil(GongTime.parseMinutes(TimeEntryField.sanitize("abc")))
        XCTAssertNil(GongTime.parseMinutes(TimeEntryField.sanitize("2560")), "25:60 不是合法时刻")
    }
}
