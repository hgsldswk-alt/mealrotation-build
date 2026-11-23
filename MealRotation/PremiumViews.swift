import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        SheetPage(title: "settings") {
            if !Launch.isFree {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.t("premium")).font(.headline)
                        Text(premiumStatus(model)).foregroundStyle(muted)
                        MealButton(key: "lifetime", id: "settings.paywall", style: .plain) { model.sheet = .paywall }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("avoid_days")).font(.headline)
                    Text(L.t("avoid_note")).font(.subheadline).foregroundStyle(muted)
                    if model.premium, let days = model.state?.avoidDays {
                        Stepper(value: Binding(get: { model.state?.avoidDays ?? 2 },
                                               set: { value in
                                                   Task { await model.edit { (state: inout DinnerState) -> Void in state.avoidDays = value; state.batch = nil } }
                                               }), in: 0...14) {
                            Text(L.f("range_days", days))
                        }
                        .accessibilityIdentifier("settings.avoid")
                        .disabled(model.busy)
                    } else {
                        Text(L.f("range_days", 2)).font(.subheadline)
                    }
                }
            }
            MealButton(key: "weekly", id: "settings.weekly", full: true) { model.sheet = .weekly }
            if let count = model.state?.homeDays, count >= 7 {
                MealButton(key: "milestone_card", id: "settings.milestone", full: true) {
                    model.sheet = .share(ShareContent(milestone: count))
                }
            }
            Text(L.t("related_apps")).font(.headline)
            MealButton(key: "cooking_app", id: "settings.cooking", style: .plain, symbol: "timer") {
                openURL(Launch.cookingTimeURL) { accepted in
                    if !accepted { model.message = L.t("link_error") }
                }
            }
        }
    }
}

@MainActor private func premiumStatus(_ model: AppModel) -> String {
    guard let access = model.state?.entitlement else { return L.t("loading") }
    if access.purchasedPro { return L.t("pro_owned") }
    if model.premium {
        let end = LocalDay(access.trialEnd).formatted()
        return L.f("trial_ends", end)
    }
    return L.t("trial_expired")
}

struct PaywallView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        SheetPage(title: "lifetime") {
            Card(tinted: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("premium")).font(.largeTitle.weight(.bold)).fontDesign(.serif)
                        .accessibilityIdentifier("paywall.title")
                    Text(premiumStatus(model)).font(.subheadline).foregroundStyle(muted)
                        .accessibilityIdentifier("paywall.status")
                    Label(L.t("paywall_quick"), systemImage: "bolt")
                    Label(L.t("paywall_avoid"), systemImage: "calendar")
                    Label(L.t("weekly"), systemImage: "list.bullet")
                }
            }
            Text(L.t("paywall_free")).font(.subheadline).foregroundStyle(muted)
            if let product = model.proProduct, model.state?.entitlement.purchasedPro != true {
                Button {
                    Task { await model.purchase(product) }
                } label: {
                    Text(L.f("buy_for", product.displayPrice)).font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(clay, in: RoundedRectangle(cornerRadius: 11))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("paywall.buy")
                .disabled(model.purchasing)
            } else if model.testing && Launch.arguments.contains("-paywall") {
                MealButton(key: "sample_buy", id: "paywall.buy", style: .primary, full: true) {}
                    .allowsHitTesting(false)
            } else if model.state?.entitlement.purchasedPro != true {
                Text(L.t("price_unavailable")).font(.subheadline).foregroundStyle(muted)
                if !model.testing {
                    MealButton(key: "retry", id: "paywall.retry", full: true) {
                        Task { await model.loadProducts() }
                    }
                }
            }
            if model.showTrialClaim {
                MealButton(key: "claim_trial", id: "paywall.trial", full: true) {
                    if let trial = model.trialProduct { Task { await model.purchase(trial) } }
                }
                .disabled(model.purchasing || model.trialProduct == nil)
                Text(L.t("trial_note")).font(.footnote).foregroundStyle(muted)
            }
            MealButton(key: "restore_purchases", id: "paywall.restore", style: .plain, full: true) {
                Task { await model.restore() }
            }
            .disabled(model.purchasing)
            Text(L.t("no_subscription")).font(.footnote).foregroundStyle(muted)
        }
        .task { await model.loadProducts() }
    }
}

struct WeeklyView: View {
    @EnvironmentObject var model: AppModel
    @State private var weeksAgo = 0
    @State private var reviewed: WeeklyReview?

    var body: some View {
        SheetPage(title: "weekly") {
            HStack {
                MealButton(key: "previous_week", id: "week.previous", style: .plain) { weeksAgo += 1 }
                Spacer()
                MealButton(key: "next_week", id: "week.next", style: .plain) { weeksAgo = max(0, weeksAgo - 1) }
                    .disabled(weeksAgo == 0)
            }
            Text(L.f("week_of", start.formatted())).font(.headline)
            if let reviewed, reviewed.start == start {
                section("home_this_week", reviewed.dinners)
                section("frequent", reviewed.frequent)
                section("overdue", reviewed.overdue)
                if !reviewed.dinners.isEmpty {
                    MealButton(key: "share_card", id: "week.share", style: .plain, symbol: "square.and.arrow.up") {
                        model.sheet = .share(ShareContent(names: reviewed.dinners, weekly: true))
                    }
                }
            } else if !model.premium {
                Text(L.t("weekly_locked")).foregroundStyle(muted)
                MealButton(key: "lifetime", id: "week.unlock", style: .primary, full: true) { model.sheet = .paywall }
            } else {
                ProgressView().accessibilityLabel(L.t("loading"))
            }
        }
        .task(id: start) {
            let week = start
            reviewed = model.state?.reviews.first(where: { $0.start == week })
            if model.premium {
                let instant = model.now
                if let result = await model.edit({ $0.createReview(start: week, now: instant) }), !Task.isCancelled {
                    reviewed = result
                }
            }
        }
    }

    private var start: LocalDay {
        let day = model.today
        let weekday = LocalDay.calendar(in: .gmt).component(.weekday, from: day.date)
        return day.adding(-((weekday + 5) % 7) - weeksAgo * 7)
    }

    private func section(_ key: String, _ values: [String]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                Text(L.t(key)).font(.headline)
                if values.isEmpty { Text(L.t("none")).foregroundStyle(muted) }
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in Text(value) }
            }
        }
    }
}

struct WidgetHelpView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        SheetPage(title: "widget_help") {
            Text(L.t("widget_preview")).font(.title2.weight(.bold)).fontDesign(.serif)
            WidgetTile(day: model.today, choices: model.choices, entry: model.todayLog) { choice in
                Text(L.t("log"))
                    .font(.caption.weight(.bold)).foregroundStyle(clay)
                    .padding(4).frame(maxWidth: .infinity)
                    .background(wash, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel(L.f("log_name", choice.dinner.name))
            }
            .padding(12)
            .background(surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("widget.preview")
            Text(L.t("widget_instructions")).foregroundStyle(muted)
        }
    }
}
