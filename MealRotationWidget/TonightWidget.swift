import SwiftUI
import WidgetKit

struct DinnerEntry: TimelineEntry {
    let date: Date
    let day: LocalDay
    let choices: [DinnerChoice]
    let record: DinnerLog?

    init(date: Date, state: DinnerState) {
        let day = LocalDay(date)
        self.date = date
        self.day = day
        choices = state.choices(on: day, now: date)
        record = state.log(on: day)
    }
}

struct DinnerTimeline: TimelineProvider {
    func placeholder(in context: Context) -> DinnerEntry {
        let now = Date()
        return DinnerEntry(date: now, state: Demo.state(at: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (DinnerEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task.detached {
            let now = Date()
            completion(DinnerEntry(date: now, state: localState()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DinnerEntry>) -> Void) {
        Task.detached {
            let now = Date()
            let calendar = LocalDay.calendar()
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ??
                now.addingTimeInterval(3600)
            let state = localState()
            let end = state.entitlement.trialEnd
            let boundary = end > now && end < midnight ? end : midnight
            completion(Timeline(entries: [DinnerEntry(date: now, state: state)], policy: .after(boundary)))
        }
    }

    private func localState() -> DinnerState {
        (try? DinnerStore.shared().read()) ?? DinnerState()
    }
}

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Launch.widgetKind, provider: DinnerTimeline()) { entry in
            WidgetTile(day: entry.day, choices: entry.choices, entry: entry.record) { choice in
                Button(intent: WidgetLogIntent(dinnerID: choice.id, day: entry.day)) {
                    Text(L.t("log")).font(.caption.weight(.bold))
                        .foregroundStyle(Color(uiColor: MealColors.accent))
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .contentShape(Rectangle())
                        .background(Color(uiColor: MealColors.tint), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.f("log_name", choice.dinner.name))
                .accessibilityIdentifier("widget.log.\(choice.id)")
            }
            .containerBackground(Color(uiColor: MealColors.paper), for: .widget)
            .widgetURL(URL(string: "mealrotation://tonight"))
        }
        .configurationDisplayName(L.t("widget_name"))
        .description(L.t("widget_description"))
        .supportedFamilies([.systemMedium])
    }
}

@main
struct MealRotationWidgets: WidgetBundle {
    var body: some Widget { TonightWidget() }
}
