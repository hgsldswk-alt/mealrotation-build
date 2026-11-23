import SwiftUI
import UIKit

struct ImportCodeView: View {
    @EnvironmentObject var model: AppModel
    @State private var code: String
    @State private var items: [MenuItem]?
    @State private var invalid = false

    init(initial: String?) {
        let decoded = initial.flatMap { try? MenuCode.decode($0) }
        _code = State(initialValue: initial ?? "")
        _items = State(initialValue: decoded)
        _invalid = State(initialValue: initial != nil && decoded == nil)
    }

    var body: some View {
        SheetPage(title: "import_code") {
            if let items {
                let preview = MenuCode.preview(items, existing: model.state?.dinners ?? [])
                Text(L.t("import_note")).foregroundStyle(muted)
                group("new_dinners", preview.added)
                group("duplicates", preview.duplicates)
                if !preview.added.isEmpty {
                    Button {
                        Task {
                            if await model.edit({ MenuCode.merge(items, into: &$0) }) != nil { model.sheet = nil }
                        }
                    } label: {
                        Text(L.f("import_add", preview.added.count))
                            .font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                            .background(clay, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("import.add")
                    .disabled(model.busy)
                }
                MealButton(key: "edit_code", id: "import.edit", style: .plain) { self.items = nil; invalid = false }
            } else {
                Text(L.t(invalid ? "invalid_code" : "enter_code")).foregroundStyle(invalid ? clay : muted)
                TextEditor(text: $code)
                    .font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .frame(minHeight: 120)
                    .accessibilityLabel(L.t("menu_code"))
                    .accessibilityIdentifier("import.code")
                MealButton(key: "preview", id: "import.preview", style: .primary, full: true) {
                    do { items = try MenuCode.decode(code); invalid = false }
                    catch { invalid = true }
                }
            }
        }
    }

    @ViewBuilder private func group(_ key: String, _ entries: [MenuItem]) -> some View {
        if !entries.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t(key)).font(.headline)
                    ForEach(entries) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            if item.quick == true { Text(L.t("quick")).font(.caption).foregroundStyle(clay) }
                        }
                    }
                }
            }
        }
    }
}

struct RestoreBackupView: View {
    @EnvironmentObject var model: AppModel
    let backup: MenuBackup

    var body: some View {
        SheetPage(title: "restore_backup") {
            let changes = backup.preview(in: model.state ?? DinnerState())
            Text(L.f("backup_counts", changes.dinners.count, changes.logs))
                .font(.headline)
            if changes.reviews > 0 { Text(L.f("backup_reviews", changes.reviews)).foregroundStyle(muted) }
            if changes.preferences != nil { Text(L.t("backup_preferences")).foregroundStyle(muted) }
            Text(L.t("backup_note")).foregroundStyle(muted)
            if !changes.dinners.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(changes.dinners.prefix(12)) { Text($0.name) }
                    }
                }
            }
            MealButton(key: "merge_backup", id: "backup.merge", style: .primary, full: true) {
                Task {
                    if await model.edit({ state in backup.merge(into: &state) }) != nil { model.sheet = nil }
                }
            }
            .disabled(model.busy || changes.isEmpty)
        }
    }
}

struct SharePreview: View {
    private struct Rendered {
        let data: Data
        let image: UIImage
    }

    @EnvironmentObject var model: AppModel
    let content: ShareContent
    @State private var showNames = true
    @State private var rendered: Rendered?
    @State private var copying = false

    var body: some View {
        SheetPage(title: "share_card") {
            if let rendered {
                Image(uiImage: rendered.image)
                    .resizable().scaledToFit().frame(maxHeight: 430)
                    .frame(maxWidth: .infinity).accessibilityLabel(content.title)
                    .accessibilityIdentifier("share.card")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 230)
            }
            if !content.names.isEmpty {
                Toggle(L.t("show_names"), isOn: $showNames).accessibilityIdentifier("share.names")
            }
            MealButton(key: "share_image", id: "share.image", style: .primary, symbol: "square.and.arrow.up", full: true) {
                guard let png = rendered?.data else { return }
                let caption = content.caption
                Task {
                    let url = await Task.detached(priority: .utility) { () -> URL? in
                        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                        let url = folder.appendingPathComponent("meal-rotation.png")
                        do {
                            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            try png.write(to: url, options: .atomic)
                            return url
                        } catch { return nil }
                    }.value
                    if let url { model.share([url, caption], insideSheet: true) }
                    else { model.message = L.t("export_error") }
                }
            }
            .disabled(rendered == nil)
            if !content.menu.isEmpty {
                MealButton(key: "copy_code", id: "share.code", full: true) { copying.toggle() }
                if copying {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L.t("code_privacy")).font(.subheadline).foregroundStyle(muted)
                            ForEach(content.menu) { item in Text(item.name).font(.subheadline) }
                            MealButton(key: "copy", id: "share.copy", style: .primary, full: true) {
                                do {
                                    let code = try MenuCode.encode(content.menu)
                                    if !model.testing { UIPasteboard.general.string = code }
                                    model.message = L.t("code_copied")
                                } catch { model.message = L.t("invalid_code") }
                            }
                        }
                    }
                }
            }
        }
        .task(id: showNames) {
            rendered = nil
            let visible = showNames
            let image = await Task.detached(priority: .userInitiated) {
                let png = ShareCard.png(content, showNames: visible, link: Launch.appStoreURL)
                return UIImage(data: png).map { Rendered(data: png, image: $0) }
            }.value
            if !Task.isCancelled {
                rendered = image
                if image == nil { model.message = L.t("export_error") }
            }
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let objects: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: objects, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
