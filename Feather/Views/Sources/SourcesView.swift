//
//  SourcesView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import CoreData
import AltSourceKit
import SwiftUI
import NimbleViews

// MARK: - View
struct SourcesView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	/// true when pushed inside Settings (no own NavigationStack)
	let embedded: Bool
	let title: String

	init(embedded: Bool = false, title: String = .localized("Sources")) {
		self.embedded = embedded
		self.title = title
	}

	/// Own instance (not .shared): the Apps tab uses the shared one, and
	/// a fetch in one would wipe the loaded sources of the other.
	@StateObject var viewModel = SourcesViewModel()
	@State private var _isAddingPresenting = false
	@State private var _addingSourceLoading = false
	@State private var _searchText = ""
	
	private var _filteredSources: [AltSource] {
		_sources.filter { _searchText.isEmpty || ($0.name?.localizedCaseInsensitiveContains(_searchText) ?? false) }
	}
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		// the built-in source (Plus Store) never shows up here, only in the Apps tab
		predicate: NSPredicate(format: "identifier != %@", Storage.plusSourceIdentifier),
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	// MARK: Body
	var body: some View {
		Group {
			if embedded {
				_content
					.navigationTitle(title)
			} else {
				NBNavigationView(title) {
					_content
				}
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}
	
	@ViewBuilder
	private var _content: some View {
		NBListAdaptable {
			if !_filteredSources.isEmpty {
				Section {
					NavigationLink {
						SourceAppsView(object: Array(_sources), viewModel: viewModel)
					} label: {
						let isRegular = horizontalSizeClass != .compact
						HStack(spacing: 18) {
							Image("Repositories").appIconStyle()
							NBTitleWithSubtitleView(
								title: .localized("All Repositories"),
								subtitle: .localized("See all apps from your sources")
							)
						}
						.padding(isRegular ? 12 : 0)
						.background(
							isRegular
								? RoundedRectangle(cornerRadius: 18, style: .continuous)
								.fill(Color(.quaternarySystemFill))
								: nil
						)
					}
					.buttonStyle(.plain)
				}
			
				NBSection(
					.localized("Repositories"),
					secondary: _filteredSources.count.description
				) {
					ForEach(_filteredSources) { source in
						NavigationLink {
							SourceAppsView(object: [source], viewModel: viewModel)
						} label: {
							SourcesCellView(source: source)
						}
						.buttonStyle(.plain)
					}
				}
			}
		}
		.searchable(text: $_searchText, placement: .platform())
		.overlay {
			if _filteredSources.isEmpty {
				if #available(iOS 17, *) {
					ContentUnavailableView {
						Label(.localized("No Repositories"), systemImage: "globe.desk.fill")
					} description: {
						Text(.localized("Get started by adding your first repository."))
					} actions: {
						Button {
							_isAddingPresenting = true
						} label: {
							NBButton(.localized("Add Source"), style: .text)
						}
					}
				}
			}
		}
		.toolbar {
			NBToolbarButton(
				systemImage: "plus",
				style: .icon,
				placement: .topBarTrailing,
				isDisabled: _addingSourceLoading
			) {
				_isAddingPresenting = true
			}
		}
		.refreshable {
			await viewModel.fetchSources(_sources, refresh: true)
		}
		.sheet(isPresented: $_isAddingPresenting) {
			SourcesAddView()
		}
	}
}
