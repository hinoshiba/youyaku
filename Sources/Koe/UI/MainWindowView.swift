import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 600)
    }

    private var sidebar: some View {
        List(selection: $windowManager.tab) {
            Section {
                ForEach(MainTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.icon)
                        .tag(tab)
                }
            } header: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Brand.gradient)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Koe")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(tr("AIのための音声入力", "Voice input for AI"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    }

    @ViewBuilder
    private var detail: some View {
        switch windowManager.tab {
        case .home: HomeView()
        case .models: ModelsView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}
