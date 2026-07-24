import SwiftUI
import Core
import DesignSystem

/// 設定（SCREEN_SETTINGS.md）
struct SettingsView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: SettingsViewModel?
    @State private var isLogoutConfirmPresented = false
    @State private var isClearCacheConfirmPresented = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .navigationTitle(Text("settings.title"))
        .task {
            if viewModel == nil {
                viewModel = SettingsViewModel(
                    auth: container.authService,
                    syncService: container.syncService,
                    storeInfo: container.store
                )
            }
            await viewModel?.onAppear()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: SettingsViewModel) -> some View {
        @Bindable var viewModel = viewModel
        Form {
            // ① プロフィール
            Section("settings.section.profile") {
                if let staff = viewModel.staff {
                    LabeledContent("settings.profile.name", value: staff.displayName)
                    LabeledContent("settings.profile.email", value: staff.email)
                    LabeledContent("settings.profile.role") {
                        Text(LocalizedStringKey("role." + staff.role.rawValue))
                    }
                }
                Button("settings.profile.resetPassword") {
                    Task { await viewModel.sendPasswordReset() }
                }
                if viewModel.resetMessageShown {
                    Label("settings.profile.resetSent", systemImage: "envelope")
                        .font(CIToken.Fonts.caption)
                        .foregroundStyle(CIToken.Colors.accent)
                }
            }

            // ② 店舗（manager+ のみ SCR-SET-01）
            if viewModel.showsStoreSection {
                Section("settings.section.store") {
                    LabeledContent("settings.store.name", value: viewModel.storeName)
                    LabeledContent("settings.store.address", value: viewModel.storeAddress)
                    LabeledContent("settings.store.logo") {
                        Text("settings.store.logo.none")
                            .foregroundStyle(.secondary)
                    }
                    // スタッフ管理（FR-104）: CF招待関数はスタブ→後結線（§15-2）
                    NavigationLink("settings.store.staff") {
                        StaffManagementPlaceholderView()
                    }
                }
            }

            // ③ 同期（FR-702）
            Section("settings.section.sync") {
                syncStatusRow(viewModel)
                if viewModel.queueStatus.pendingCount > 0 {
                    LabeledContent("settings.sync.pending", value: String(viewModel.queueStatus.pendingCount))
                }
                if viewModel.queueStatus.failedCount > 0 {
                    LabeledContent("settings.sync.failed") {
                        Text(String(viewModel.queueStatus.failedCount))
                            .foregroundStyle(CIToken.Colors.danger)
                    }
                }
                Button {
                    Task { await viewModel.syncNow() }
                } label: {
                    HStack {
                        Text("settings.sync.now")
                        if viewModel.isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isSyncing || !viewModel.queueStatus.isOnline)
                if viewModel.queueStatus.failedCount > 0 {
                    Button("settings.sync.retryFailed") {
                        Task { await viewModel.retryFailed() }
                    }
                }
            }

            // ④ ストレージ（FR-703）
            Section("settings.section.storage") {
                if let usage = viewModel.storageUsage {
                    LabeledContent("settings.storage.original", value: format(usage.originalBytes))
                    LabeledContent("settings.storage.masked", value: format(usage.maskedBytes))
                    LabeledContent("settings.storage.pdf", value: format(usage.pdfBytes))
                    LabeledContent("settings.storage.total") {
                        Text(format(usage.total)).bold()
                    }
                } else if viewModel.isMeasuringStorage {
                    ProgressView()
                }
                Button("settings.storage.clearCache", role: .destructive) {
                    isClearCacheConfirmPresented = true
                }
                Text("settings.storage.retention.note")
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(.secondary)
            }

            // ⑤ セキュリティ
            Section("settings.section.security") {
                Toggle("settings.security.appLock", isOn: $viewModel.isAppLockEnabled)
                Text("settings.security.appLock.note")
                    .font(CIToken.Fonts.caption)
                    .foregroundStyle(.secondary)
            }

            // ⑥ その他
            Section("settings.section.about") {
                LabeledContent("settings.about.version", value: viewModel.appVersion)
                NavigationLink("settings.about.licenses") {
                    LicensesView()
                }
                Button("settings.logout", role: .destructive) {
                    isLogoutConfirmPresented = true
                }
            }
        }
        .confirmationDialog("settings.logout.confirmTitle", isPresented: $isLogoutConfirmPresented, titleVisibility: .visible) {
            Button("settings.logout", role: .destructive) {
                Task { await viewModel.signOut() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            if viewModel.unsyncedCountForLogout > 0 {
                // SCR-SET-04: 未同期件数を明示した強い警告
                Text("settings.logout.unsyncedWarning \(viewModel.unsyncedCountForLogout)")
            } else {
                Text("settings.logout.confirmMessage")
            }
        }
        .confirmationDialog("settings.storage.clearCache", isPresented: $isClearCacheConfirmPresented, titleVisibility: .visible) {
            Button("settings.storage.clearCache.confirm", role: .destructive) {
                Task { await viewModel.clearCache() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("settings.storage.clearCache.message")
        }
    }

    private func syncStatusRow(_ viewModel: SettingsViewModel) -> some View {
        HStack {
            if !viewModel.queueStatus.isOnline {
                Label("settings.sync.offline", systemImage: "wifi.slash")
                    .foregroundStyle(CIToken.Colors.warning)
            } else if viewModel.queueStatus.failedCount > 0 {
                Label("settings.sync.hasFailed \(viewModel.queueStatus.failedCount)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(CIToken.Colors.danger)
            } else if viewModel.queueStatus.totalQueued > 0 {
                Label("settings.sync.syncing", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(CIToken.Colors.primary)
            } else {
                Label("settings.sync.upToDate", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CIToken.Colors.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// スタッフ管理（FR-104。CF招待関数のスタブ、M8で結線 §15-2）
struct StaffManagementPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            systemImage: "person.2.badge.gearshape",
            title: String(localized: "settings.staff.title"),
            message: String(localized: "settings.staff.placeholder")
        )
        .navigationTitle(Text("settings.store.staff"))
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            Text("settings.licenses.body")
                .font(CIToken.Fonts.caption)
                .padding(CIToken.Space.m)
        }
        .navigationTitle(Text("settings.about.licenses"))
    }
}
