import XCTest
import AppKit
import SwiftUI
@testable import GongCore

@MainActor
final class AutoGrowingEditorTests: XCTestCase {
    func testNativeInputAreaGrowsAndShrinksWithSwiftUILayout() throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: BufferedTextEditor(
            contextID: "empty", value: "", minHeight: 56, onChange: { _ in }).frame(width: 400))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: host.fittingSize.height)
        host.layoutSubtreeIfNeeded()
        func findEditor(in view: NSView) -> FocusReportingTextView? {
            if let editor = view as? FocusReportingTextView { return editor }
            return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
        }
        let native = try XCTUnwrap(findEditor(in: host))
        XCTAssertGreaterThanOrEqual(native.frame.height, 56)
        XCTAssertGreaterThan(native.frame.width, 300)
        let emptyHeight = native.frame.height
        let longText = (1...12).map { "第\($0)行，记录今天的发现。" }.joined(separator: "\n")
        host.rootView = BufferedTextEditor(contextID: "empty", value: longText, minHeight: 56,
                                           onChange: { _ in }).frame(width: 400)
        host.frame.size.height = host.fittingSize.height
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(try XCTUnwrap(findEditor(in: host)).frame.height, emptyHeight * 3)

        host.rootView = BufferedTextEditor(contextID: "empty", value: "", minHeight: 56,
                                           onChange: { _ in }).frame(width: 400)
        host.frame.size.height = host.fittingSize.height
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(try XCTUnwrap(findEditor(in: host)).frame.height, emptyHeight, accuracy: 1)
    }

    private func editor(_ text: String) -> FocusReportingTextView {
        _ = NSApplication.shared
        let view = FocusReportingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 56))
        view.isRichText = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.widthTracksTextView = true
        view.textContainerInset = .zero
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 16), .paragraphStyle: paragraph
        ]))
        return view
    }

    func testLongEntryGrowsBeyondThreeLinesAndShrinksAfterDeletion() {
        let view = editor("第一行\n第二行\n第三行\n第四行\n第五行\n第六行")
        let longHeight = view.contentHeight(for: 400)
        XCTAssertGreaterThan(longHeight, 100)
        view.textStorage?.deleteCharacters(in: NSRange(location: 3, length: view.string.utf16.count - 3))
        XCTAssertLessThan(view.contentHeight(for: 400), longHeight / 2)
    }

    func testNarrowerWindowWrapsAndGrowingWidthRestoresHeight() {
        let view = editor(String(repeating: "这一段没有手动换行，也需要随着窗口宽度自动换行。", count: 12))
        let wide = view.contentHeight(for: 600)
        let narrow = view.contentHeight(for: 220)
        XCTAssertGreaterThan(narrow, wide * 1.5)
        XCTAssertEqual(view.contentHeight(for: 600), wide, accuracy: 1)
    }

    func testTrailingReturnReservesSpaceForTheNewEmptyLine() {
        let view = editor("第一行\n第二行\n第三行")
        let before = view.contentHeight(for: 400)
        view.textStorage?.append(NSAttributedString(string: "\n", attributes: view.textStorage!.attributes(at: 0, effectiveRange: nil)))
        XCTAssertGreaterThan(view.contentHeight(for: 400), before + 10)
    }
}
