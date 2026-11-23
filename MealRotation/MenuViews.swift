import SwiftUI

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    let openFile: () -> Void
    @State private var more = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                PageTitle(key: "menu")
                MealButton(key: "more", id: "menu.more", style: .plain, symbol: "ellipsis.circle") { more = true }
                    .confirmationDialog(L.t("more"), isPresented: $more) {
                        Button(L.t("settings")) { model.sheet = .settings }
                        Button(L.t("archived")) { model.sheet = .archived }
                        Button(L.t("export_backup")) { Task { await model.export(backup: true) } }
                        Button(L.t("restore_backup"), action: openFile)
                        Button(L.t("widget_help")) { model.sheet = .widgetHelp }
                    }
            }
            HStack(spacing: 8) {
                MealButton(key: "paste_code", id: "menu.paste", full: true) { model.clickPaste() }
                MealButton(key: "add", id: "menu.add", style: .primary, symbol: "plus", full: true) { model.sheet = .add }
            }
            let choices = Rotation.ranked(model.state?.dinners ?? [], logs: model.state?.logs ?? [], through: model.today)
            if choices.isEmpty { Card { Text(L.t("empty_menu")).foregroundStyle(muted) } }
            LazyVStack(spacing: 9) {
                ForEach(choices) { choice in
                    Card {
                        Button {
                            model.sheet = .edit(choice.dinner)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(choice.dinner.name).font(.headline)
                                    Text(choice.detail(on: model.today)).font(.subheadline).foregroundStyle(muted)
                                }
                                Spacer()
                                if choice.dinner.quick { Text(L.t("quick")).font(.caption).foregroundStyle(clay) }
                                Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("menu.dinner.\(choice.id)")
                    }
                }
            }
        }
    }
}

struct AddDinnersView: View {
    @EnvironmentObject var model: AppModel
    @State private var names = ""

    var body: some View {
        SheetPage(title: "add_dinners") {
            Text(L.t("add_note")).foregroundStyle(muted)
            MealButton(key: "save_dinners", id: "add.save", style: .primary, full: true) {
                Task { if await model.add(names) { model.sheet = nil } }
            }
            .disabled(names.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            if model.testing, let fixture = ProcessInfo.processInfo.environment["UI_DINNER_NAMES"] {
                MealButton(key: "paste_dinners", id: "add.insert_test_text", full: true) { names = fixture }
            }
            TextEditor(text: $names)
                .accessibilityLabel(L.t("dinner_names"))
                .accessibilityIdentifier("add.names")
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(rule).allowsHitTesting(false) }
        }
    }
}

struct EditDinnerView: View {
    @EnvironmentObject var model: AppModel
    @State var dinner: Dinner
    @State private var archive = false

    var body: some View {
        SheetPage(title: "edit_dinner") {
            TextField(L.t("dinner_name"), text: $dinner.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("edit.name")
            Toggle(L.t("quick"), isOn: $dinner.quick).accessibilityIdentifier("edit.quick")
            MealButton(key: "save", id: "edit.save", style: .primary, full: true) {
                Task { if await model.save(dinner) { model.sheet = nil } }
            }
            .disabled(model.busy)
            MealButton(key: "archive", id: "edit.archive", style: .plain, full: true) { archive = true }
                .confirmationDialog(L.t("archive_note"), isPresented: $archive, titleVisibility: .visible) {
                    Button(L.t("archive"), role: .destructive) {
                        let updated = model.state?.dinners.first(where: { $0.id == dinner.id }) ?? dinner
                        var archived = updated
                        archived.archived = true
                        Task { if await model.save(archived) { model.sheet = nil } }
                    }
                }
        }
    }
}

struct ArchivedView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        SheetPage(title: "archived") {
            let archived = (model.state?.dinners ?? []).filter(\.archived)
            if archived.isEmpty { Text(L.t("no_archived")).foregroundStyle(muted) }
            ForEach(archived) { dinner in
                Card {
                    HStack {
                        Text(dinner.name)
                        Spacer()
                        MealButton(key: "unarchive", id: "archived.restore.\(dinner.id)", style: .plain) {
                            var restored = dinner
                            restored.archived = false
                            Task { await model.save(restored) }
                        }
                        .disabled(model.busy)
                    }
                }
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @State private var window = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageTitle(key: "history")
            HStack {
                MealButton(key: "export_csv", id: "history.export", style: .plain, symbol: "square.and.arrow.up") {
                    Task { await model.export(backup: false) }
                }
                MealButton(key: "weekly", id: "history.weekly", style: .plain, symbol: "calendar") {
                    model.sheet = .weekly
                }
            }
            LazyVStack(spacing: 8) {
                ForEach(0..<window, id: \.self) { offset in
                    let day = model.today.adding(-offset)
                    let log = model.state?.log(on: day)
                    Card {
                        Button {
                            model.sheet = .picker(day, log)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(offset == 0 ? L.t("day_today") : offset == 1 ? L.t("yesterday") : day.formatted())
                                        .font(.subheadline).foregroundStyle(muted)
                                    Text(log?.title ?? L.t("add_log")).font(.headline)
                                }
                                Spacer()
                                Image(systemName: log == nil ? "plus" : "chevron.right")
                                    .foregroundStyle(clay).accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("history.day.\(offset)")
                    }
                }
            }
            MealButton(key: "older", id: "history.older", style: .plain, full: true) { window += 14 }
        }
    }
}

struct PickDinnerView: View {
    @EnvironmentObject var model: AppModel
    let day: LocalDay
    let expected: DinnerLog?

    var body: some View {
        SheetPage(title: expected == nil ? "choose_dinner" : "change") {
            Text(day.formatted(.full)).foregroundStyle(muted)
            HStack(spacing: 8) {
                MealButton(key: "leftovers", id: "pick.leftovers", full: true) { choose(nil, kind: .leftovers) }
                MealButton(key: "ate_out", id: "pick.out", full: true) { choose(nil, kind: .out) }
            }
            ForEach(Array(Rotation.ranked(model.state?.dinners ?? [], logs: model.state?.logs ?? [],
                                          through: model.today).enumerated()), id: \.element.id) { index, choice in
                Card {
                    Button { choose(choice.dinner, kind: .home) } label: {
                        HStack {
                            Text(choice.dinner.name).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "plus.circle").foregroundStyle(clay).accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pick.dinner.\(index)")
                    .disabled(model.busy)
                }
            }
        }
    }

    private func choose(_ dinner: Dinner?, kind: DinnerKind) {
        Task { if await model.pick(day, expected: expected, dinner: dinner, kind: kind) { model.sheet = nil } }
    }
}
