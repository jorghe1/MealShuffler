import SwiftUI
import UIKit

/// A4 sheets of the week and the shopping list, for the fridge or the shop.
///
/// Families print the week: a sheet on the fridge is read by everyone, phone or not. The share
/// picture is a 9:16 story, which printed as a phone-shaped strip; these are pages drawn for
/// paper instead -- black on white, no background, large enough to read across a kitchen.
@MainActor
enum PrintDocuments {
    /// A4 in PostScript points.
    static let pageSize = CGSize(width: 595, height: 842)

    // MARK: - Content

    /// The week as printed: one line per day, what is for dinner and the facts that matter at
    /// the table -- who cooks, how many, how long.
    static func week(store: AppStore, nextWeek: Bool) -> PrintableWeek? {
        guard let plan = nextWeek ? store.nextWeekPlan : store.plan else { return nil }
        let days = Weekday.ordered().map { day -> PrintableWeek.Day in
            let date = plan.date(for: day)
            guard let item = plan[day] else {
                return PrintableWeek.Day(id: day, name: day.name, date: date, title: L10n.string("Not planned"), detail: "", isOff: true)
            }
            let meal = item.freezerBatch?.recipe ?? item.mealID.flatMap { store.meal(id: $0) }
            var detail: [String] = []
            if item.kind == .meal, let meal, meal.prepMinutes > 0 { detail.append(L10n.string("%ld min", meal.prepMinutes)) }
            if item.kind != .away {
                detail.append(L10n.string("%ld at dinner", store.context(for: day, nextWeek: nextWeek).diners))
            }
            if let cook = store.cook(for: day, nextWeek: nextWeek) { detail.append(L10n.string("%@ cooks", cook.displayName)) }
            return PrintableWeek.Day(
                id: day,
                name: day.name,
                date: date,
                title: DayRow.title(for: item, meal: meal),
                detail: detail.joined(separator: " · "),
                isOff: item.kind == .away || (item.kind == .meal && meal == nil)
            )
        }
        let start = plan.startDate
        return PrintableWeek(
            household: store.household.name,
            heading: L10n.string("Week %ld", Calendar.current.component(.weekOfYear, from: start)),
            range: WeekAnchor.label(forWeekStarting: start),
            days: days
        )
    }

    /// What is still to buy, aisle by aisle in the household's shop order.
    static func shoppingList(store: AppStore) -> PrintableShoppingList {
        let remaining = store.groceryItems.filter { !store.checkedGroceryIDs.contains($0.id) }
        var lines: [PrintableShoppingList.Line] = []
        for aisle in store.aisleOrder {
            let items = remaining.filter { $0.aisle == aisle }
            guard !items.isEmpty else { continue }
            lines.append(.aisle(aisle.name))
            for item in items {
                lines.append(.item(item.quantityText.isEmpty ? item.name : "\(item.quantityText) \(item.name)"))
            }
        }
        return PrintableShoppingList(
            title: L10n.string("Shopping list"),
            period: WeekAnchor.label(forWeekStarting: store.shoppingStart),
            lines: lines
        )
    }

    // MARK: - Pages

    static func pages(week: PrintableWeek?, shopping: PrintableShoppingList?) -> [AnyView] {
        var pages: [AnyView] = []
        if let week { pages.append(AnyView(PrintableWeekPage(week: week))) }
        if let shopping, !shopping.lines.isEmpty {
            let columns = shopping.columns()
            let pageCount = Int((Double(columns.count) / 2).rounded(.up))
            for index in 0..<pageCount {
                let pair = Array(columns[(index * 2)..<min(columns.count, index * 2 + 2)])
                pages.append(AnyView(PrintableShoppingPage(list: shopping, columns: pair, page: index + 1, of: pageCount)))
            }
        }
        return pages
    }

    /// The pages as one PDF, drawn by SwiftUI straight into the PDF context so text stays text.
    static func pdf(_ pages: [AnyView]) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard !pages.isEmpty,
              let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for page in pages {
            let renderer = ImageRenderer(content: page
                .frame(width: pageSize.width, height: pageSize.height)
                .environment(\.colorScheme, .light))
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    /// The PDF as a file with a readable name, for "Save to Files", Mail or AirDrop.
    static func file(_ data: Data, named name: String) -> URL? {
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe).appendingPathExtension("pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// The system print sheet, with the PDF as the job.
    static func print(_ data: Data, jobName: String) {
        guard !data.isEmpty else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
    }
}

// MARK: - Printable content

struct PrintableWeek: Hashable {
    struct Day: Identifiable, Hashable {
        let id: Weekday
        let name: String
        let date: Date
        let title: String
        let detail: String
        /// Nobody eating at home, or nothing planned: printed quieter.
        let isOff: Bool
    }

    let household: String
    let heading: String
    let range: String
    let days: [Day]
}

struct PrintableShoppingList: Hashable {
    enum Line: Hashable {
        case aisle(String)
        case item(String)

        /// An aisle heading takes the room of two items: its own line and the space above it.
        var weight: Int {
            switch self {
            case .aisle: 2
            case .item: 1
            }
        }
    }

    let title: String
    let period: String
    let lines: [Line]

    /// Lines per column of a page, in item lines: what fits between the header and the footer.
    static let columnCapacity = 40

    /// The lines split into columns, two to a page. A heading never ends a column, and a
    /// column continuing an aisle repeats its heading, so every item can be found by aisle.
    func columns(capacity: Int = Self.columnCapacity) -> [[Line]] {
        var columns: [[Line]] = []
        var current: [Line] = []
        var used = 0
        var currentAisle: Line?
        for (index, line) in lines.enumerated() {
            let isHeading: Bool
            if case .aisle = line { isHeading = true; currentAisle = line } else { isHeading = false }
            // A heading needs room for at least one item under it.
            let needed = line.weight + (isHeading ? 1 : 0)
            if used + needed > capacity, !current.isEmpty {
                columns.append(current)
                current = []
                used = 0
                if !isHeading, let currentAisle, index > 0 {
                    current.append(currentAisle)
                    used += currentAisle.weight
                }
            }
            current.append(line)
            used += line.weight
        }
        if !current.isEmpty { columns.append(current) }
        return columns
    }
}

// MARK: - Pages

private enum Paper {
    static let ink = Color(red: 0.10, green: 0.12, blue: 0.10)
    static let green = Color(red: 0.12, green: 0.42, blue: 0.28)
    static let muted = Color(red: 0.40, green: 0.42, blue: 0.38)
    static let rule = Color(red: 0.80, green: 0.80, blue: 0.78)
}

/// The week on A4: large enough to read from across the kitchen.
struct PrintableWeekPage: View {
    let week: PrintableWeek

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(week.household.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Paper.green)
            HStack(alignment: .firstTextBaseline) {
                Text(week.heading)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Paper.ink)
                Spacer(minLength: 12)
                Text(week.range)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Paper.muted)
            }
            .padding(.bottom, 14)
            Rectangle().fill(Paper.ink).frame(height: 1.5)

            ForEach(week.days) { day in
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Paper.green)
                        Text(day.date, format: .dateTime.day().month())
                            .font(.system(size: 11))
                            .foregroundStyle(Paper.muted)
                    }
                    .frame(width: 100, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(day.isOff ? Paper.muted : Paper.ink)
                            .lineLimit(2)
                        if !day.detail.isEmpty {
                            Text(day.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(Paper.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                .overlay(alignment: .bottom) { Rectangle().fill(Paper.rule).frame(height: 0.5) }
            }

            Spacer(minLength: 0)
            Text("Shuffled with Meal Shuffler")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Paper.muted)
        }
        .padding(44)
        .frame(width: PrintDocuments.pageSize.width, height: PrintDocuments.pageSize.height, alignment: .topLeading)
        .background(Color.white)
    }
}

/// The shopping list on A4, two columns of tick boxes, aisle by aisle.
struct PrintableShoppingPage: View {
    let list: PrintableShoppingList
    let columns: [[PrintableShoppingList.Line]]
    let page: Int
    let of: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(list.title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Paper.ink)
                Spacer(minLength: 12)
                Text(list.period)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Paper.muted)
            }
            .padding(.bottom, 10)
            Rectangle().fill(Paper.ink).frame(height: 1.5).padding(.bottom, 6)

            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, line in
                            lineView(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if columns.count == 1 { Color.clear.frame(maxWidth: .infinity) }
            }

            Spacer(minLength: 0)
            HStack {
                Text("Shuffled with Meal Shuffler")
                Spacer()
                if of > 1 { Text(verbatim: "\(page)/\(of)") }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Paper.muted)
        }
        .padding(44)
        .frame(width: PrintDocuments.pageSize.width, height: PrintDocuments.pageSize.height, alignment: .topLeading)
        .background(Color.white)
    }

    @ViewBuilder private func lineView(_ line: PrintableShoppingList.Line) -> some View {
        switch line {
        case .aisle(let name):
            Text(name.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Paper.green)
                .frame(height: 30, alignment: .bottomLeading)
        case .item(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).stroke(Paper.ink, lineWidth: 0.8).frame(width: 10, height: 10)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(height: 15, alignment: .leading)
        }
    }
}

// MARK: - Sharing a file

/// A file handed to the share sheet: Save to Files, Mail, AirDrop, Print.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet for things `ShareLink` cannot take, such as a file made on demand.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
