import PDFKit
import XCTest
@testable import MealShuffler

/// The week and the shopping list on paper.
@MainActor
final class PrintDocumentsTests: XCTestCase {

    private func makeStore() throws -> AppStore {
        let suite = "PrintDocumentsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let store = AppStore(
            repository: UserDefaultsStateRepository(defaults: defaults),
            random: SeededRandomSource(seed: 11),
            widgetRefresher: RecordingWidgetRefresher(),
            reminderService: RecordingReminderScheduler()
        )
        store.completeOnboarding()
        return store
    }

    // MARK: - Content

    func testTheWeekHasSevenDaysWithTheDinnersOnThem() throws {
        let store = try makeStore()
        let week = try XCTUnwrap(PrintDocuments.week(store: store, nextWeek: false))
        XCTAssertEqual(week.days.count, 7)
        for day in week.days {
            guard let item = store.plan[day.id], item.kind == .meal, let id = item.mealID else { continue }
            XCTAssertEqual(day.title, store.meal(id: id)?.name)
        }
    }

    func testNextWeekPrintsOnlyOnceItExists() throws {
        let store = try makeStore()
        store.discardNextWeek()
        XCTAssertNil(PrintDocuments.week(store: store, nextWeek: true))
        store.planNextWeek()
        XCTAssertNotNil(PrintDocuments.week(store: store, nextWeek: true))
    }

    func testTheShoppingListLeavesOutWhatWasBought() throws {
        let store = try makeStore()
        let first = try XCTUnwrap(store.groceryItems.first)
        store.checkedGroceryIDs.insert(first.id)
        let list = PrintDocuments.shoppingList(store: store)
        let printed = list.lines.compactMap { line -> String? in
            if case .item(let text) = line { return text }
            return nil
        }
        XCTAssertFalse(printed.contains { $0.hasSuffix(first.name) && $0.contains(first.quantityText) })
        XCTAssertFalse(printed.isEmpty)
    }

    // MARK: - Columns

    func testColumnsRespectTheirCapacityAndNeverEndOnAHeading() {
        var lines: [PrintableShoppingList.Line] = []
        for aisle in 0..<6 {
            lines.append(.aisle("Aisle \(aisle)"))
            for item in 0..<9 { lines.append(.item("Item \(aisle)-\(item)")) }
        }
        let list = PrintableShoppingList(title: "List", period: "Week", lines: lines)
        let columns = list.columns(capacity: 20)

        XCTAssertGreaterThan(columns.count, 1)
        for column in columns {
            XCTAssertLessThanOrEqual(column.reduce(0) { $0 + $1.weight }, 20)
            if case .aisle? = column.last { XCTFail("A column ends on a heading with nothing under it") }
        }
        // Every item printed exactly once.
        let items = columns.flatMap { $0 }.filter { if case .item = $0 { return true } else { return false } }
        XCTAssertEqual(items.count, 54)
    }

    func testAContinuedAisleRepeatsItsHeading() {
        var lines: [PrintableShoppingList.Line] = [.aisle("Frukt og grønt")]
        for item in 0..<30 { lines.append(.item("Item \(item)")) }
        let columns = PrintableShoppingList(title: "List", period: "Week", lines: lines).columns(capacity: 12)
        for column in columns {
            XCTAssertEqual(column.first, .aisle("Frukt og grønt"))
        }
    }

    // MARK: - The PDF

    func testTheWeekAndListMakeAnA4PdfWithAPageEach() throws {
        let store = try makeStore()
        let pages = PrintDocuments.pages(
            week: PrintDocuments.week(store: store, nextWeek: false),
            shopping: PrintDocuments.shoppingList(store: store)
        )
        let data = PrintDocuments.pdf(pages)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, pages.count)
        XCTAssertGreaterThanOrEqual(document.pageCount, 2)
        let bounds = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 595, accuracy: 1)
        XCTAssertEqual(bounds.height, 842, accuracy: 1)
    }

    func testTheWeekPageCarriesItsText() throws {
        let store = try makeStore()
        let week = try XCTUnwrap(PrintDocuments.week(store: store, nextWeek: false))
        let data = PrintDocuments.pdf(PrintDocuments.pages(week: week, shopping: nil))
        let text = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0)?.string)
        XCTAssertTrue(text.contains(week.heading), "Text stays text in the PDF, so it prints sharp and can be searched")
    }

    func testAnEmptyDocumentIsEmpty() {
        XCTAssertTrue(PrintDocuments.pdf([]).isEmpty)
    }

    func testTheFileHasAReadableName() throws {
        let url = try XCTUnwrap(PrintDocuments.file(Data("%PDF".utf8), named: "Uke 42/43"))
        XCTAssertEqual(url.lastPathComponent, "Uke 42-43.pdf")
        try? FileManager.default.removeItem(at: url)
    }
}
