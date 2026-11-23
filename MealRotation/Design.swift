import SwiftUI
import UIKit

let paper = Color(uiColor: MealColors.paper)
let ink = Color(uiColor: MealColors.ink)
let clay = Color(uiColor: MealColors.accent)
let wash = Color(uiColor: MealColors.tint)
let surface = Color(uiColor: MealColors.surface)
let rule = Color(uiColor: MealColors.line)
let muted = Color(uiColor: MealColors.muted)

struct MealButton: View {
    enum Style { case primary, secondary, outline, plain }
    let key: String
    let id: String
    var style: Style = .secondary
    var symbol: String?
    var full = false
    var spoken: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(L.t(key))
                    .multilineTextAlignment(.center)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minWidth: 44, maxWidth: full ? .infinity : nil, minHeight: 44)
            .contentShape(Rectangle())
            .foregroundStyle(style == .primary ? .white : style == .outline ? ink : clay)
            .background(style == .primary ? clay : style == .secondary ? wash : style == .outline ? surface : .clear,
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                if style == .outline { RoundedRectangle(cornerRadius: 11).strokeBorder(rule).allowsHitTesting(false) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken ?? L.t(key))
        .accessibilityIdentifier(id)
    }
}

struct Card<Content: View>: View {
    var tinted = false
    var highlighted = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tinted ? wash : surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15).strokeBorder(highlighted ? clay.opacity(0.40) : rule)
                    .allowsHitTesting(false)
            }
    }
}

struct PageTitle: View {
    let key: String
    var eyebrow: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let eyebrow { Text(eyebrow).font(.subheadline.weight(.semibold)).foregroundStyle(clay) }
            Text(L.t(key))
                .font(.largeTitle.weight(.bold))
                .fontDesign(.serif)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SheetPage<Content: View>: View {
    @EnvironmentObject var model: AppModel
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(18)
                    .frame(maxWidth: 580)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(paper.ignoresSafeArea())
            .navigationTitle(L.t(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    MealButton(key: "close", id: "sheet.close", style: .plain) { model.sheet = nil }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    MealButton(key: "done", id: "keyboard.done", style: .plain) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { AppBanner() }
        }
    }
}

struct AppBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let message = model.message {
            HStack {
                Text(message)
                    .font(.subheadline)
                    .accessibilityIdentifier("status.message")
                Spacer(minLength: 2)
                MealButton(key: "dismiss", id: "status.close", style: .plain) { model.message = nil }
            }
            .padding(.horizontal, 14)
            .background(wash)
            .accessibilityElement(children: .contain)
        } else if model.shareRequested {
            Text(L.t("share_ready"))
                .font(.subheadline)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(wash)
                .accessibilityIdentifier("share.requested")
        }
    }
}
