import EventKit
import SwiftUI
import Combine

@MainActor
final class CalendarMonitor: ObservableObject {
    @Published var nextEvent: EKEvent?
    @Published var minutesUntilNext: Int?
    @Published var todayCount: Int = 0
    @Published var joinURL: URL?
    @Published var meetingAlertMode: Bool = false

    private let eventStore = EKEventStore()
    private var refreshTimer: Timer?
    private var hasRequestedAccess = false

    init() {
        Task {
            await requestAccess()
            await refreshEvents()
            startRefreshTimer()
        }
    }

    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            hasRequestedAccess = true
            if granted {
                await refreshEvents()
            }
        } catch {
            print("Calendar access error: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshEvents() async {
        let now = Date()
        let calendar = Calendar.current

        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now.addingTimeInterval(86400)

        let next24hEnd = now.addingTimeInterval(86400)

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: next24hEnd,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        let todayPredicate = eventStore.predicateForEvents(
            withStart: todayStart,
            end: todayEnd,
            calendars: nil
        )
        let todayEvents = eventStore.events(matching: todayPredicate)
        todayCount = todayEvents.count

        if let nextEventFound = events.first {
            nextEvent = nextEventFound
            let minutesDiff = Int(nextEventFound.startDate.timeIntervalSince(now) / 60)
            minutesUntilNext = max(0, minutesDiff)
            meetingAlertMode = minutesUntilNext ?? 0 <= 5
            extractJoinURL(from: nextEventFound)
        } else {
            nextEvent = nil
            minutesUntilNext = nil
            meetingAlertMode = false
            joinURL = nil
        }
    }

    private func extractJoinURL(from event: EKEvent) {
        var urlString: String?

        if let notes = event.notes {
            urlString = extractURLString(from: notes)
        }

        if urlString == nil, let location = event.location {
            urlString = extractURLString(from: location)
        }

        if let urlString = urlString, let url = URL(string: urlString) {
            joinURL = url
        } else {
            joinURL = nil
        }
    }

    private func extractURLString(from text: String) -> String? {
        let patterns = [
            "https://zoom\\.us/j/[^\\s]+",
            "https://meet\\.google\\.com/[^\\s]+",
            "https://teams\\.microsoft\\.com/[^\\s]+"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: range) {
                    if let range = Range(match.range, in: text) {
                        return String(text[range])
                    }
                }
            }
        }

        if let url = extractFirstURL(from: text) {
            return url
        }

        return nil
    }

    private func extractFirstURL(from text: String) -> String? {
        let types: NSTextCheckingResult.CheckingType = [.link]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)

        for match in matches {
            if let range = Range(match.range, in: text) {
                let urlString = String(text[range])
                if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                    return urlString
                }
            }
        }

        return nil
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshEvents()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
}

struct CalendarWidgetView: View {
    @ObservedObject var monitor: CalendarMonitor

    var body: some View {
        VStack(spacing: 8) {
            if let nextEvent = monitor.nextEvent {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(nextEvent.title)
                            .font(.system(.body, design: .default))
                            .lineLimit(1)

                        if let minutesUntilNext = monitor.minutesUntilNext {
                            if minutesUntilNext == 0 {
                                Text("now")
                                    .font(.system(.caption, design: .default))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("in \(minutesUntilNext) min")
                                    .font(.system(.caption, design: .default))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if let _ = monitor.joinURL {
                        Link(destination: monitor.joinURL!) {
                            Text("Join")
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No upcoming events")
                            .font(.system(.body, design: .default))

                        Text("\(monitor.todayCount) today")
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Material.ultraThin)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

/* DISABLED-PREVIEW #Preview {
    @Previewable @State var monitor = CalendarMonitor()

    return CalendarWidgetView(monitor: monitor)
        .padding()
        .frame(maxWidth: 300)
} */
