//
//  VariedTabbarView.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

/// Modified: two tabs only.
/// - Library: downloaded / imported / signed apps (Settings is the gear button in its toolbar)
/// - Apps: every app from the built-in source (Sources is hidden from Settings; nobody can add/edit/remove sources from the UI)
struct VariedTabbarView: View {
	init() {}
	
	var body: some View {
		TabView {
			LibraryView()
				.tabItem {
					Label(String.localized("Library"), systemImage: "square.grid.2x2")
				}
			
			AppsTabView()
				.tabItem {
					Label {
						Text(verbatim: "التطبيقات")
					} icon: {
						Image(systemName: "arrow.down.app")
					}
				}
		}
	}
}

// MARK: - Apps tab
/// Shows the apps of all added sources in one list (same list as "All Repositories").
/// Tapping an app opens its page; "Get" downloads it into the Library.
struct AppsTabView: View {
	@StateObject private var _viewModel = SourcesViewModel.shared
	@State private var _isReady = false
	@State private var _isSettingsPresenting = false
	@Environment(\.layoutDirection) private var _layoutDirection
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	/// Physical top-left corner in both LTR and RTL (Arabic) layouts.
	private var _settingsPlacement: ToolbarItemPlacement {
		_layoutDirection == .rightToLeft ? .topBarTrailing : .topBarLeading
	}
	
	var body: some View {
		NBNavigationView("التطبيقات") {
			Group {
				if _sources.isEmpty {
					_emptyState
				} else if _isReady {
					SourceAppsView(
						object: Array(_sources),
						viewModel: _viewModel
					)
					.id(_sources.compactMap { $0.sourceURL?.absoluteString })
				} else {
					ProgressView()
				}
			}
			.toolbar {
				ToolbarItem(placement: _settingsPlacement) {
					Button {
						_isSettingsPresenting = true
					} label: {
						Image(systemName: "gearshape.2")
					}
				}
			}
		}
		// Wait for the sources to finish loading before showing the list,
		// and reload it whenever a source is added or removed.
		.task(id: Array(_sources)) {
			await MainActor.run { _isReady = false }
			await _viewModel.fetchSources(_sources)
			while !_viewModel.isFinished {
				try? await Task.sleep(nanoseconds: 200_000_000)
			}
			await MainActor.run { _isReady = true }
		}
		.sheet(isPresented: $_isSettingsPresenting) {
			SettingsView()
		}
	}
	
	@ViewBuilder
	private var _emptyState: some View {
		if #available(iOS 17, *) {
			ContentUnavailableView {
				Label(String.localized("No Apps"), systemImage: "app.dashed")
			} description: {
				Text(verbatim: "لا توجد تطبيقات متاحة حالياً")
			}
		} else {
			Text(verbatim: "لا توجد تطبيقات متاحة حالياً")
				.foregroundStyle(.secondary)
				.padding()
		}
	}
}
