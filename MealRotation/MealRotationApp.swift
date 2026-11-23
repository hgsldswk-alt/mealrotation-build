import StoreKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
@MainActor
struct MealRotationApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .foregroundStyle(ink)
                .tint(clay)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    if url.scheme == "mealrotation" {
                        model.page = .tonight
                        model.sheet = nil
                        Task { await model.refresh() }
                    }
                    else if url.isFileURL { Task { await model.readBackup(url) } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.requestReview) private var requestReview
    @State private var selectingFile = false

    var body: some View {
        VStack(spacing: 0) {
            if model.state != nil {
                ScrollView {
                    Group {
                        switch model.page {
                        case .tonight: TonightView()
                        case .menu: MenuView(openFile: { selectingFile = true })
                        case .history: HistoryView()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 580)
                    .frame(maxWidth: .infinity)
                }
                .id(model.page)
                AppBanner()
                tabBar
            } else {
                Spacer()
                if model.message != nil {
                    MealButton(key: "retry", id: "load.retry", style: .primary) {
                        model.message = nil
                        Task { await model.start() }
                    }
                    AppBanner()
                } else {
                    ProgressView().accessibilityLabel(L.t("loading"))
                }
                Spacer()
            }
        }
        .background(paper.ignoresSafeArea())
        .sheet(item: $model.sheet, onDismiss: presentPendingActivity) { sheet in
            sheetView(sheet).environmentObject(model)
        }
        .fileImporter(isPresented: $selectingFile, allowedContentTypes: [.mealBackup, .json]) { result in
            if let url = try? result.get() { Task { await model.readBackup(url) } }
        }
        .task {
            await model.start()
            await model.refreshPurchases()
        }
        .task { await model.trackPurchases() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await model.refresh() }
        }
        .task(id: phase) {
            guard phase == .active else { return }
            await model.refresh()
            await model.refreshPurchases()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                await model.refresh()
            }
        }
        .task(id: reviewID) {
            guard let id = reviewID else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard reviewID == id, !model.busy else { return }
            if await model.markRated(id), phase == .active, model.sheet == nil, model.page == .tonight {
                requestReview()
            }
        }
    }

    private var reviewID: UUID? {
        guard phase == .active, model.page == .tonight, model.sheet == nil, model.message == nil else { return nil }
        return model.ratingCandidate
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tab(.tonight, "sun.horizon")
            tab(.menu, "list.bullet.rectangle")
            tab(.history, "clock")
        }
        .padding(.horizontal, 9)
        .padding(.top, 4)
        .background(alignment: .top) {
            surface.overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 1) }
        }
    }

    private func tab(_ page: AppPage, _ symbol: String) -> some View {
        Button {
            model.page = page
            model.message = nil
            model.shareRequested = false
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19)).accessibilityHidden(true)
                Text(L.t(page.rawValue)).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            }
            .padding(4)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
            .foregroundStyle(model.page == page ? clay : muted)
            .background(model.page == page ? wash : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.page == page ? .isSelected : [])
        .accessibilityIdentifier("tab." + page.rawValue)
    }

    @ViewBuilder private func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .add: AddDinnersView()
        case .edit(let dinner): EditDinnerView(dinner: dinner)
        case .archived: ArchivedView()
        case .picker(let day, let record): PickDinnerView(day: day, expected: record)
        case .importCode(let code): ImportCodeView(initial: code)
        case .backup(let backup): RestoreBackupView(backup: backup)
        case .share(let content): SharePreview(content: content)
        case .settings: SettingsView()
        case .paywall: PaywallView()
        case .weekly: WeeklyView()
        case .widgetHelp: WidgetHelpView()
        case .activity(let objects): ActivityView(objects: objects)
        }
    }

    private func presentPendingActivity() {
        model.message = nil
        model.shareRequested = false
        if let objects = model.pendingActivity {
            model.pendingActivity = nil
            model.sheet = .activity(objects)
        }
    }
}

extension UTType {
    static let mealBackup = UTType(exportedAs: "com.hgsldswk.mealrotation.backup", conformingTo: .json)
}
