import SwiftUI
import SwiftData

@main
struct CarInspectorAIApp: App {
    /// UIテスト時はモック構成（インメモリDB・モックカメラ・手動接続）で起動（08 §1: 実ネットワーク禁止）
    @State private var container = ProcessInfo.processInfo.arguments.contains("--uitest")
        ? AppContainer.mock()
        : AppContainer.production()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appContainer, container)
                .modelContainer(container.modelContainer)
        }
    }
}
