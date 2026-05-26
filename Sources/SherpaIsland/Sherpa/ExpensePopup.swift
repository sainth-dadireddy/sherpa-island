import SwiftUI
import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Workday brand + UI palette

fileprivate let wdOrange    = Color(red: 1.00, green: 0.45, blue: 0.20)  // Workday accent
fileprivate let wdNavy      = Color(red: 0.12, green: 0.27, blue: 0.50)  // Workday header
fileprivate let wdBg        = Color(red: 0.165, green: 0.192, blue: 0.255)
fileprivate let wdPanel     = Color(red: 0.204, green: 0.235, blue: 0.302)
fileprivate let wdInput     = Color(red: 0.243, green: 0.275, blue: 0.345)
fileprivate let wdTextHi    = Color(red: 0.95,  green: 0.96,  blue: 0.98)
fileprivate let wdTextMid   = Color(red: 0.72,  green: 0.75,  blue: 0.80)
fileprivate let wdTextLow   = Color(red: 0.55,  green: 0.58,  blue: 0.64)

// MARK: - Extracted receipt model

struct ExpenseDraft: Codable {
    var merchant: String?
    var date: String?
    var amount: Double?
    var quantity: Int?
    var unitAmount: Double?
    var currency: String?
    var tax: Double?
    var tip: Double?
    var expenseItem: String?
    var mealType: String?
    var isGroupMeal: Bool?
    var attendees: [String]?
    var memoSuggestion: String?
    var items: [String]?
    var policyFlags: [String]?
    var confidence: Double?
    var rawText: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case merchant, date, amount, quantity, currency, tax, tip
        case unitAmount = "unit_amount"
        case expenseItem = "expense_item"
        case mealType = "meal_type"
        case isGroupMeal = "is_group_meal"
        case attendees
        case memoSuggestion = "memo_suggestion"
        case items
        case policyFlags = "policy_flags"
        case confidence
        case rawText = "raw_text"
        case error
    }
}

// ERPA tenant defaults
fileprivate let defaultCompany    = "LE002 ERP Analysts Inc"
fileprivate let defaultCostCenter = "CC041 COGS- Cloud Practice Delivery"

// ERPA Workday lookup lists
fileprivate let companyOptions = [
    "LE001 ERP Holdings LLC", "LE002 ERP Analysts Inc",
    "LE003 ERP Professionals Inc", "LE004 ERP FusionTech Solutions (INDIA) Pvt. Ltd",
    "LE007 ERPA India Pvt Ltd", "LE008 Sponsor Kids Foundation Inc"
]
fileprivate let costCenterOptions = [
    "CC041 COGS- Cloud Practice Delivery",
    "CC043 Workday Proposal Management",
    "CC044 Application Practice - Customer Success",
    "CC045 Cloud Practice- Proposal Mgmt",
    "CC046 Cloud Practice- Customer Success",
    "CC047 Application Practice - Management",
    "CC048 Cloud Practice - Management",
    "CC049 Applications -Overhead Allocations-G&A",
    "CC050 Cloud Overhead Allocations- G&A",
    "CC051 Workday Overhead Allocations- G&A",
    "CC052 ECS - Overhead Allocations - G&A",
    "CC053 COGS- Workday -Org Change Mgmt"
]
fileprivate let projectOptions = [
    "", "Papa Johns USA: PS Admin Services",
    "Republic Bank Limited:RBL_CRM", "Republic Bank Limited:RBL_HCM",
    "Southern Ute Indian Tribe: PeopleSoft Managed Services",
    "St. Petersburg College: Managed Services",
    "United States Merchant Marine Academy: SIS AWS PeopleSoft Managed Services_USMMA",
    "Universal Technical Institute: PeopleSoft Managed Services",
    "University of California, Santa Barbara: Managed Services",
    "University of Maryland Global Campus : Managed Services"
]
fileprivate let conferenceOptions = [
    "", "Peoplesoft Quest Reconnect",
    "Workday- Alliance", "Workday-Altitude",
    "Workday Customer Event", "Workday - DevCon",
    "Workday - Practice Off Site", "Workday-Rising",
    "Workday RUG", "Workday Sales / QBR / CSM", "Workday-SKO",
    "AWS-Cloud World", "AWS re:Invent", "AWS Summit"
]
fileprivate let expenseItemOptions = [
    "", "Software Subscriptions", "Subscriptions",
    "Taxi/Uber", "Telephone/Mobile Charges",
    "Tips & Incidental Expenses",
    "Trade Show- Gifts & Supplies", "Trade Show- Hotel",
    "Trade show- Meals", "Trade Show -Travel",
    "Travel Fee", "Travel Ticket",
    "Tuition Fee", "Shipping", "Relocation Expenses",
    "Other"
]

// MARK: - OCR runner

struct DraftItem: Identifiable {
    let id = UUID()
    var path: String
    var draft: ExpenseDraft?
    var status: Status = .pending
    enum Status { case pending, running, done, failed(String) }
    var filename: String { URL(fileURLWithPath: path).lastPathComponent }
}

@MainActor
final class ExpenseRunner: ObservableObject {
    @Published var items: [DraftItem] = []
    @Published var currentIndex: Int = 0
    @Published var isBatchRunning = false
    @Published var lastError: String?

    var currentItem: DraftItem? {
        guard !items.isEmpty, currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }
    var hasItems: Bool { !items.isEmpty }
    var isRunningCurrent: Bool {
        if case .running = currentItem?.status { return true }; return false
    }

    func addAndProcess(paths: [String]) async {
        let newItems = paths.map { DraftItem(path: $0) }
        let startIndex = items.count
        items.append(contentsOf: newItems)
        if items.count == newItems.count { currentIndex = 0 }
        isBatchRunning = true
        lastError = nil
        await withTaskGroup(of: Void.self) { group in
            for i in startIndex..<items.count {
                group.addTask { await self.runOne(index: i) }
            }
        }
        isBatchRunning = false
    }

    func runOne(index: Int) async {
        guard index < items.count else { return }
        items[index].status = .running
        do {
            let json = try await runShell(
                executable: NSHomeDirectory() + "/.claude/scripts/expense_ocr.sh",
                args: [items[index].path]
            )
            let parsed = try JSONDecoder().decode(ExpenseDraft.self, from: Data(json.utf8))
            items[index].draft = parsed
            items[index].status = parsed.error == nil ? .done : .failed(parsed.error ?? "")
        } catch {
            items[index].status = .failed(error.localizedDescription)
        }
    }

    func reset() {
        items.removeAll()
        currentIndex = 0
        lastError = nil
        isBatchRunning = false
    }

    func removeCurrent() {
        guard !items.isEmpty else { return }
        items.remove(at: currentIndex)
        if currentIndex >= items.count { currentIndex = max(0, items.count - 1) }
    }

    private func runShell(executable: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [executable] + args
                let out = Pipe(); let err = Pipe()
                p.standardOutput = out
                p.standardError  = err
                do {
                    try p.run()
                    p.waitUntilExit()
                    let so = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    cont.resume(returning: so.trimmingCharacters(in: .whitespacesAndNewlines))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Template recall (persisted last-used header)

struct ExpenseTemplate: Codable {
    var memo: String
    var company: String
    var costCenter: String
    var project: String
    var conference: String
    var expenseItem: String
    var currency: String
    var billable: Bool
    var savedAt: Date

    static let path = NSHomeDirectory() + "/.claude/wd/last_expense_template.json"

    static func load() -> ExpenseTemplate? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(ExpenseTemplate.self, from: data)
    }

    func save() {
        let dir = (Self.path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try? JSONEncoder().encode(self)
        try? data?.write(to: URL(fileURLWithPath: Self.path))
    }
}

// MARK: - View

struct ExpensePopupView: View {
    @StateObject private var runner = ExpenseRunner()
    // Header
    @State private var memo = ""
    @State private var company = defaultCompany
    @State private var reportDate = todayString()
    @State private var costCenter = defaultCostCenter
    @State private var project = ""
    @State private var conference = ""
    // Line
    @State private var merchant = ""
    @State private var lineDate = ""
    @State private var expenseItem = ""
    @State private var quantity = "1"
    @State private var unitAmount = ""
    @State private var totalAmount = ""
    @State private var currency = "USD"
    @State private var lineMemo = ""
    @State private var billable = false
    @State private var lineCostCenter = defaultCostCenter
    // UI
    @State private var isDropTarget = false
    @State private var voiceOn = true
    @Environment(\.dismiss) private var dismiss

    private let workdayURL = "https://wd12.myworkday.com/erpa/d/task/2997$728.htmld#backheader=true"

    private static func todayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(wdOrange.opacity(0.3))

            if !runner.hasItems {
                dropZone
            } else {
                if runner.items.count > 1 {
                    batchNavBar
                    Divider().background(wdOrange.opacity(0.15))
                }
                if runner.isRunningCurrent { progressBar }
                receiptStrip
                Divider().background(wdOrange.opacity(0.15))
                form
                Divider().background(wdOrange.opacity(0.15))
                actionRow
            }

            if let err = runner.lastError {
                Divider().background(.red.opacity(0.3))
                errorRow(err)
            }
            Spacer(minLength: 0)
        }
        .background(wdBg.ignoresSafeArea())
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onChange(of: runner.currentIndex) { _, _ in applyCurrent() }
        .onChange(of: runner.items.count) { _, n in
            if n > 0, runner.currentItem?.draft != nil { applyCurrent() }
        }
    }

    private var batchNavBar: some View {
        HStack(spacing: 10) {
            Button {
                runner.currentIndex = max(0, runner.currentIndex - 1)
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered).disabled(runner.currentIndex == 0)

            VStack(spacing: 2) {
                Text("Receipt \(runner.currentIndex + 1) of \(runner.items.count)")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(wdTextHi)
                if runner.isBatchRunning {
                    let done = runner.items.filter { if case .done = $0.status { return true }; return false }.count
                    Text("OCR \(done)/\(runner.items.count)").font(.system(size: 10)).foregroundColor(wdTextLow)
                }
            }
            Spacer()

            Button {
                runner.removeCurrent()
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.bordered).foregroundColor(.red)
            .help("Remove this receipt from batch")

            Button {
                runner.currentIndex = min(runner.items.count - 1, runner.currentIndex + 1)
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered).disabled(runner.currentIndex >= runner.items.count - 1)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(wdPanel.opacity(0.6))
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient(colors: [wdOrange, wdNavy],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: "doc.text.image.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Workday Expense Draft")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(wdTextHi)
                Text("OCR receipt · pre-fill · review → submit in browser")
                    .font(.system(size: 11))
                    .foregroundColor(wdTextLow)
            }
            Spacer()
            Toggle(isOn: $voiceOn) {
                Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(voiceOn ? wdOrange : wdTextLow)
            }
            .toggleStyle(.button)
            .tint(wdOrange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(wdPanel)
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: isDropTarget ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(isDropTarget ? wdOrange : wdTextMid)
            Text(isDropTarget ? "Release to OCR" : "Drop receipt(s) here")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(wdTextHi)
            Text("Drop ONE or MANY · PNG · JPG · PDF · HEIC")
                .font(.system(size: 11))
                .foregroundColor(wdTextLow)
            HStack(spacing: 10) {
                Button { pickFile() } label: {
                    Label("Choose Files…", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(wdOrange.opacity(0.2)))
                        .foregroundColor(wdOrange)
                }
                .buttonStyle(.plain)

                if ExpenseTemplate.load() != nil {
                    Button { applyTemplate() } label: {
                        Label("Use last template", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(wdNavy.opacity(0.25)))
                            .foregroundColor(wdNavy.opacity(0.95))
                    }
                    .buttonStyle(.plain)
                    .help("Pre-fill header from last submitted expense")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTarget ? wdOrange : wdTextLow.opacity(0.35),
                    style: StrokeStyle(lineWidth: isDropTarget ? 2.5 : 1.5, dash: [6,4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDropTarget ? wdOrange.opacity(0.06) : Color.clear)
                )
        )
        .padding(16)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget) { providers in
            var paths: [String] = []
            let group = DispatchGroup()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let u = url { paths.append(u.path) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                Task { @MainActor in
                    await runner.addAndProcess(paths: paths)
                    applyCurrent()
                    announceBatchComplete()
                }
            }
            return true
        }
        .animation(.easeOut(duration: 0.18), value: isDropTarget)
    }

    private var progressBar: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(wdOrange)
            Text("OCR via Gemini…")
                .font(.system(size: 12))
                .foregroundColor(wdTextMid)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(wdPanel.opacity(0.5))
    }

    private var receiptStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill").foregroundColor(wdOrange)
            Text(runner.currentItem?.filename ?? "(no file)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(wdTextMid)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if let conf = runner.currentItem?.draft?.confidence {
                Text("\(Int(conf * 100))% conf")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(confColor(conf).opacity(0.2)))
                    .foregroundColor(confColor(conf))
            }
            Button {
                runner.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundColor(wdTextMid)
            }
            .buttonStyle(.plain)
            .help("Clear all / start over")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(wdPanel.opacity(0.5))
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 14) {
                sectionLabel("REPORT HEADER")
                row(label: "Memo (business purpose)", text: $memo, icon: "text.alignleft")
                pickerRow(label: "Company", selection: $company, options: companyOptions, icon: "building.2.fill")
                HStack(spacing: 8) {
                    row(label: "Report Date", text: $reportDate, icon: "calendar")
                    pickerRow(label: "Conference / Event", selection: $conference, options: conferenceOptions, icon: "person.3")
                }
                pickerRow(label: "Cost Center", selection: $costCenter, options: costCenterOptions, icon: "building.columns")
                pickerRow(label: "Project", selection: $project, options: projectOptions, icon: "folder")

                if let flags = runner.currentItem?.draft?.policyFlags, !flags.isEmpty {
                    policyWarnings(flags)
                }

                sectionLabel("EXPENSE LINE")
                row(label: "Merchant",     text: $merchant,    icon: "building.2")
                HStack(spacing: 8) {
                    row(label: "Date",      text: $lineDate,   icon: "calendar")
                    row(label: "Currency",  text: $currency,   icon: "dollarsign.circle", width: 90)
                }
                pickerRow(label: "Expense Item", selection: $expenseItem, options: expenseItemOptions, icon: "tag")
                HStack(spacing: 8) {
                    row(label: "Qty",        text: $quantity,    icon: "number.square", width: 60)
                    row(label: "Unit Amt",   text: $unitAmount,  icon: "number")
                    row(label: "Total",      text: $totalAmount, icon: "sum")
                }
                row(label: "Line Memo",    text: $lineMemo,    icon: "text.bubble")
                HStack {
                    Toggle("Billable", isOn: $billable)
                        .toggleStyle(.switch).tint(wdOrange)
                        .foregroundColor(wdTextHi)
                    Spacer()
                }
            }
            .padding(16)
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        HStack {
            Text(s).font(.system(size: 10, weight: .heavy)).foregroundColor(wdOrange)
                .tracking(1.2)
            Rectangle().fill(wdOrange.opacity(0.3)).frame(height: 1)
        }
    }

    private func policyWarnings(_ flags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(flags, id: \.self) { f in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(humanFlag(f))
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.yellow.opacity(0.08))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow.opacity(0.3), lineWidth: 0.5))
    }

    private func humanFlag(_ f: String) -> String {
        switch f {
        case "over_meal_cap": return "Meal exceeds ERPA cap — may need justification"
        case "mileage_needs_map": return "Mileage: attach trip calculator map screenshot"
        case "over_60_days": return "Receipt is over 60 days old — won't be reimbursed if personal card"
        case "hotel_needs_itemization": return "Hotel: itemize meals/incidentals separately"
        default: return f
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                copyToClipboard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy fields")
                }
                .padding(.vertical, 6).padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)

            Button {
                openInWorkday()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "safari")
                    Text("Open in Workday").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(wdOrange)
        }
        .padding(.horizontal, 16).padding(.bottom, 14)
    }

    private func errorRow(_ err: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            Text(err).font(.system(size: 11)).foregroundStyle(.red)
            Spacer()
        }
        .padding(14)
    }

    // MARK: - Helpers

    private var receiptFilename: String {
        runner.currentItem?.filename ?? "(no file)"
    }

    private func confColor(_ c: Double) -> Color {
        if c >= 0.8 { return .green }
        if c >= 0.5 { return .yellow }
        return .red
    }

    private func row(label: String, text: Binding<String>, icon: String, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(wdTextMid)
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(wdOrange)
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(wdTextHi)
                copyButton(text.wrappedValue)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(wdInput)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .frame(width: width)
    }

    private func pickerRow(label: String, selection: Binding<String>, options: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(wdTextMid)
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(wdOrange)
                Picker("", selection: selection) {
                    ForEach(options, id: \.self) { opt in
                        Text(opt.isEmpty ? "—" : opt).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(wdTextHi)
                .frame(maxWidth: .infinity, alignment: .leading)
                copyButton(selection.wrappedValue)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(wdInput)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
    }

    @State private var lastCopied: String = ""
    private func copyButton(_ value: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            lastCopied = value
        } label: {
            Image(systemName: lastCopied == value && !value.isEmpty ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundColor(lastCopied == value && !value.isEmpty ? .green : wdTextMid)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy")
        .disabled(value.isEmpty)
    }

    private func applyCurrent() {
        guard let d = runner.currentItem?.draft else { return }
        merchant     = d.merchant ?? ""
        lineDate     = d.date ?? ""
        expenseItem  = d.expenseItem ?? ""
        quantity     = d.quantity.map(String.init) ?? "1"
        unitAmount   = d.unitAmount.map { String(format: "%.2f", $0) } ?? ""
        totalAmount  = d.amount.map { String(format: "%.2f", $0) } ?? ""
        currency     = d.currency ?? "USD"
        let itemsStr = (d.items ?? []).joined(separator: ", ")
        lineMemo     = d.memoSuggestion ?? itemsStr
        if memo.isEmpty {
            memo = d.memoSuggestion ?? (d.merchant ?? "")
        }
        if let attendees = d.attendees, !attendees.isEmpty {
            lineMemo += " — Attendees: " + attendees.joined(separator: ", ")
        }
    }

    private func applyTemplate() {
        guard let t = ExpenseTemplate.load() else { return }
        memo = t.memo
        company = t.company
        costCenter = t.costCenter
        project = t.project
        conference = t.conference
        expenseItem = t.expenseItem
        currency = t.currency
        billable = t.billable
    }

    private func saveTemplate() {
        let t = ExpenseTemplate(
            memo: memo, company: company, costCenter: costCenter,
            project: project, conference: conference, expenseItem: expenseItem,
            currency: currency, billable: billable, savedAt: Date()
        )
        t.save()
    }

    private func copyToClipboard() {
        let block = """
        === HEADER ===
        Memo: \(memo)
        Company: \(company)
        Report Date: \(reportDate)
        Cost Center: \(costCenter)
        Project: \(project)
        Conference/Event: \(conference)

        === EXPENSE LINE ===
        Date: \(lineDate)
        Expense Item: \(expenseItem)
        Merchant: \(merchant)
        Quantity: \(quantity)
        Unit Amount: \(unitAmount)
        Total: \(totalAmount) \(currency)
        Memo: \(lineMemo)
        Billable: \(billable ? "Yes" : "No")
        Receipt file: \(runner.currentItem?.path ?? "—")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block, forType: .string)
    }

    private func openInWorkday() {
        saveTemplate()      // remember for next time
        copyToClipboard()   // paste-by-field via copy buttons; also full block
        if let url = URL(string: workdayURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true   // batch
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf]
        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path }
            Task {
                await runner.addAndProcess(paths: paths)
                applyCurrent()
                announceBatchComplete()
            }
        }
    }

    private func announceBatchComplete() {
        guard voiceOn else { return }
        let count = runner.items.count
        let done = runner.items.filter { if case .done = $0.status { return true }; return false }.count
        if count == 1, let d = runner.currentItem?.draft {
            let merch = d.merchant ?? "unknown merchant"
            let amt = d.amount.map { String(format: "%.2f", $0) } ?? "?"
            let cur = d.currency ?? "USD"
            TempoSpeech.shared.speak("Receipt extracted: \(cur) \(amt) at \(merch)")
        } else {
            TempoSpeech.shared.speak("Batch OCR complete: \(done) of \(count) receipts ready")
        }
    }
}

// MARK: - Window controller

@MainActor
final class ExpensePopupWindowController: NSWindowController {
    static let shared = ExpensePopupWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Expense Draft"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        win.contentView = NSHostingView(rootView: ExpensePopupView())
        win.minSize = NSSize(width: 480, height: 460)
        super.init(window: win)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let win = window else { return }
        if !win.isVisible {
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                let w: CGFloat = 540, h: CGFloat = 560
                win.setFrame(NSRect(x: f.midX - w/2, y: f.midY - h/2, width: w, height: h), display: true)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

/* DISABLED-PREVIEW #Preview { ExpensePopupView() } */
