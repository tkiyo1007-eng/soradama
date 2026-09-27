import SwiftUI

/// 都市検索 + 保存地点の管理シート
struct CitySearchView: View {
    enum Purpose: Equatable {
        case browse
        case choosePrimary
    }

    @Bindable var viewModel: WeatherViewModel
    /// オンボーディングから開いた場合だけ渡される。
    /// シートを閉じただけでは呼ばず、ホーム地点が確定したときだけ呼ぶ。
    let onPrimaryPlaceSelected: (() -> Void)?
    let purpose: Purpose
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var search = CitySearchModel()
    @State private var isSelecting = false
    @State private var locationSelectionTask: Task<Void, Never>?
    @State private var pendingPlaceChoice: SavedPlace?

    init(
        viewModel: WeatherViewModel,
        purpose: Purpose = .browse,
        onPrimaryPlaceSelected: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.purpose = purpose
        self.onPrimaryPlaceSelected = onPrimaryPlaceSelected
    }

    var body: some View {
        NavigationStack {
            List {
                // 現在地
                Section {
                    Button {
                        chooseCurrentLocation()
                    } label: {
                        HStack {
                            Label("現在地を使う", systemImage: "location.fill")
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            if isSelecting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSelecting)

                    if let message = viewModel.locationSelectionError {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(message)
                    }
                }

                // 検索結果
                if !search.results.isEmpty {
                    Section("検索結果") {
                        ForEach(search.results) { result in
                            Button {
                                select(result.asSavedPlace)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if !result.detailText.isEmpty {
                                            Text(result.detailText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        viewModel.save(place: result.asSavedPlace)
                                        Haptics.success()
                                    } label: {
                                        Image(systemName: isSaved(result) ? "checkmark.circle.fill" : "plus.circle")
                                            .font(.title3)
                                            .foregroundStyle(isSaved(result) ? Color.green : Color.accentColor)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("citySearch.save.\(result.id)")
                                }
                            }
                            .accessibilityIdentifier("citySearch.result.\(result.id)")
                        }
                    }
                } else if search.isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("検索中…")
                            Spacer()
                        }
                    }
                } else if search.hasFailed {
                    Section {
                        Text("都市を検索できませんでした。通信状態を確認して、もう一度お試しください。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("再試行") { search.search(query) }
                    }
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Text("「\(query)」は見つかりませんでした。別の表記や近くの都市名でお試しください。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // 保存済みの地点
                if !viewModel.savedPlaces.isEmpty {
                    Section("マイシティ") {
                        ForEach(viewModel.savedPlaces) { place in
                            Button {
                                select(place)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if !place.detail.isEmpty {
                                        Text(place.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            viewModel.removePlaces(at: offsets)
                        }
                    }
                }
                Section {
                    WeatherAttributionFooter(showsCitySource: true)
                }
            }
            .disabled(isSelecting)
            .navigationTitle("地点を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "都市名で検索(例: 大阪、Paris)")
            .onChange(of: query) { _, newValue in
                search.search(newValue)
            }
            .onDisappear {
                search.cancel()
                cancelLocationSelection()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        cancelLocationSelection()
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog(
            "この都市をどう使いますか？",
            isPresented: Binding(
                get: { pendingPlaceChoice != nil },
                set: { if !$0 { pendingPlaceChoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("自分の空に設定") {
                guard let place = pendingPlaceChoice else { return }
                pendingPlaceChoice = nil
                selectAsPrimary(place)
            }
            Button("この都市の天気を見る") {
                guard let place = pendingPlaceChoice else { return }
                pendingPlaceChoice = nil
                selectForBrowsing(place)
            }
            Button("キャンセル", role: .cancel) {
                pendingPlaceChoice = nil
            }
        } message: {
            if let place = pendingPlaceChoice {
                Text("\(place.name)を自分の空にすると、空玉・通知・ウィジェット・Apple Watchもこの都市に変わります。")
            }
        }
    }

    private func isSaved(_ place: GeoPlace) -> Bool {
        let id = place.asSavedPlace.id
        return viewModel.savedPlaces.contains { $0.id == id }
    }

    private func select(_ place: SavedPlace) {
        guard !isSelecting else { return }
        if purpose == .browse {
            pendingPlaceChoice = place
            return
        }
        selectAsPrimary(place)
    }

    private func selectAsPrimary(_ place: SavedPlace) {
        guard !isSelecting else { return }
        isSelecting = true
        Task {
            await viewModel.selectPrimaryCity(place)
            onPrimaryPlaceSelected?()
            dismiss()
        }
    }

    private func selectForBrowsing(_ place: SavedPlace) {
        guard !isSelecting else { return }
        isSelecting = true
        Task {
            await viewModel.selectSearched(place)
            dismiss()
        }
    }

    private func chooseCurrentLocation() {
        guard !isSelecting else { return }
        isSelecting = true
        locationSelectionTask = Task {
            let succeeded = await viewModel.useCurrentLocation()
            // 取消済みの古い処理が、再表示後の状態や完了通知を変更しない。
            guard !Task.isCancelled else { return }
            locationSelectionTask = nil
            isSelecting = false
            guard succeeded else { return }
            onPrimaryPlaceSelected?()
            dismiss()
        }
    }

    private func cancelLocationSelection() {
        guard let locationSelectionTask else { return }
        locationSelectionTask.cancel()
        self.locationSelectionTask = nil
        isSelecting = false
    }
}
