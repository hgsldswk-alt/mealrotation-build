import SwiftUI

struct WidgetTile<LogControl: View>: View {
    let day: LocalDay
    let choices: [DinnerChoice]
    let entry: DinnerLog?
    @ViewBuilder let control: (DinnerChoice) -> LogControl

    private var ink: Color { Color(uiColor: MealColors.ink) }
    private var clay: Color { Color(uiColor: MealColors.accent) }
    private var muted: Color { Color(uiColor: MealColors.muted) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L.t("tonight")).font(.headline).fontDesign(.serif)
                Spacer()
                Text(L.t("widget_menu")).font(.caption2).foregroundStyle(muted)
            }
            if let entry {
                Label(L.t("logged"), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(clay)
                Text(entry.title).font(.headline).lineLimit(2).accessibilityLabel(entry.title)
            } else if choices.isEmpty {
                Text(L.t("widget_empty")).font(.subheadline).foregroundStyle(muted)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(choices) { choice in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(choice.dinner.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2, reservesSpace: true)
                                .accessibilityLabel(choice.dinner.name)
                            Text(choice.detail(on: day)).font(.caption2).foregroundStyle(muted).lineLimit(1)
                            control(choice)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(5)
                        .background(Color(uiColor: MealColors.surface), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
    }
}
