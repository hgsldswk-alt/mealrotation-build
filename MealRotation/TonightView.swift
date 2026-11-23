import SwiftUI

struct TonightView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .bottom) {
                PageTitle(key: model.todayLog == nil ? "whats_for_dinner" : "tonight", eyebrow: model.today.formatted(.full))
                if model.state?.dinners.contains(where: { !$0.archived }) == true {
                    Button { model.sheet = .add } label: {
                        Image(systemName: "plus").font(.headline).foregroundStyle(clay)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("add_dinners"))
                    .accessibilityIdentifier("tonight.add")
                }
            }
            if let entry = model.todayLog {
                logged(entry)
            } else if model.state?.dinners.contains(where: { !$0.archived }) != true {
                empty
            } else {
                candidates
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tonight.page")
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Card(tinted: true) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L.t("empty_title")).font(.title.weight(.bold)).fontDesign(.serif)
                    Text(L.t("empty_note")).foregroundStyle(muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("example")).font(.caption).foregroundStyle(muted)
                        Text(L.t("sample_chicken")).font(.subheadline)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(clay.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])).allowsHitTesting(false) }
                    MealButton(key: "add_dinners", id: "tonight.add", style: .primary, full: true) { model.sheet = .add }
                }
            }
            MealButton(key: "import_code", id: "tonight.import", style: .outline, full: true) { model.clickPaste() }
        }
    }

    private var candidates: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.t("rotation_hint")).font(.subheadline.weight(.semibold)).foregroundStyle(muted)
                Spacer()
                if model.premium {
                    MealButton(key: model.state?.quickOnly == true ? "show_all" : "quick", id: "tonight.quick", style: .plain) {
                        Task { await model.edit { (state: inout DinnerState) -> Void in state.quickOnly.toggle(); state.batch = nil } }
                    }
                }
            }
            if model.choices.isEmpty {
                Card { Text(L.t("no_quick")).foregroundStyle(muted) }
            }
            ForEach(Array(model.choices.enumerated()), id: \.element.id) { index, choice in
                Card(highlighted: index == 0) {
                    if size.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { dinnerText(choice); logButton(choice, index) }
                    } else {
                        HStack(spacing: 10) { dinnerText(choice); logButton(choice, index) }
                    }
                }
            }
            let actions = size.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
            actions {
                if model.canShuffle {
                    MealButton(key: "shuffle", id: "tonight.shuffle", style: .outline, symbol: "shuffle", full: true) {
                        Task { await model.shuffle() }
                    }
                }
                MealButton(key: "log_other", id: "tonight.other", style: .outline, full: true) {
                    model.sheet = .picker(model.today, nil)
                }
            }
            actions {
                if !model.choices.isEmpty {
                    MealButton(key: "share_card", id: "tonight.share", style: .plain, symbol: "square.and.arrow.up") {
                        let choices = model.choices
                        model.sheet = .share(ShareContent(names: choices.map(\.dinner.name),
                            menu: choices.map { MenuItem(name: $0.dinner.name, quick: $0.dinner.quick) }))
                    }
                }
                cookingTime
            }
        }
    }

    private func dinnerText(_ choice: DinnerChoice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(choice.dinner.name).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(choice.detail(on: model.today)).font(.subheadline).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func logButton(_ choice: DinnerChoice, _ index: Int) -> some View {
        MealButton(key: "log", id: "tonight.log.\(index)", style: index == 0 ? .primary : .secondary,
                   spoken: L.f("log_name", choice.dinner.name)) {
            Task { await model.log(choice) }
        }
        .disabled(model.busy)
    }

    private func logged(_ entry: DinnerLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Card(tinted: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L.t("logged"), systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                        .foregroundStyle(clay).accessibilityIdentifier("tonight.logged")
                    Text(entry.title).font(.title.weight(.bold)).fontDesign(.serif)
                    HStack {
                        Text(L.t("saved_tonight")).font(.subheadline).foregroundStyle(muted)
                        Spacer()
                        MealButton(key: "undo", id: "tonight.undo", style: .plain) { Task { await model.undo(entry) } }
                    }
                }
            }
            MealButton(key: "change", id: "tonight.change", style: .outline, full: true) { model.sheet = .picker(entry.day, entry) }
            if let count = model.state?.homeDays, count >= 7 {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.f("milestone_title", count)).font(.headline)
                        MealButton(key: "milestone_card", id: "tonight.milestone", style: .plain) {
                            model.sheet = .share(ShareContent(milestone: count))
                        }
                    }
                }
            }
            cookingTime
        }
    }

    private var cookingTime: some View {
        MealButton(key: "plan_cooking", id: "tonight.cooking", style: .plain, symbol: "timer") {
            openURL(Launch.cookingTimeURL) { accepted in
                if !accepted { model.message = L.t("link_error") }
            }
        }
    }
}
