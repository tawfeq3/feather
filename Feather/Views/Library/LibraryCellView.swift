//
//  LibraryAppIconView.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import SwiftUI
import NimbleExtensions
import NimbleViews
import UIKit.UIAlertController

// Modified: default installation server type = Semi Local (index 1 in Settings > Installation).
// Registered once; it never overrides a value the user already chose on this device.
private enum PlusInstallDefaults {
	static let registered: Bool = {
		UserDefaults.standard.register(defaults: ["Feather.serverMethod": 1])
		return true
	}()
}

// MARK: - View
struct LibraryCellView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.editMode) private var editMode
	@State private var _isSigningDirectly = false
	
	// Same certificate list/order that SigningView uses
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>

	var certInfo: Date.ExpirationInfo? {
		Storage.shared.getCertificate(from: app)?.expiration?.expirationInfo()
	}
	
	var certRevoked: Bool {
		Storage.shared.getCertificate(from: app)?.revoked == true
	}
	
	var app: AppInfoPresentable
	@Binding var selectedInfoAppPresenting: AnyApp?
	@Binding var selectedSigningAppPresenting: AnyApp?
	@Binding var selectedInstallAppPresenting: AnyApp?
	@Binding var selectedAppUUIDs: Set<String>
	
	// MARK: Selections
	private var _isSelected: Bool {
		guard let uuid = app.uuid else { return false }
		return selectedAppUUIDs.contains(uuid)
	}
	
	private func _toggleSelection() {
		guard let uuid = app.uuid else { return }
		if selectedAppUUIDs.contains(uuid) {
			selectedAppUUIDs.remove(uuid)
		} else {
			selectedAppUUIDs.insert(uuid)
		}
	}
	
	// MARK: Body
	var body: some View {
		let isRegular = horizontalSizeClass != .compact
		let isEditing = editMode?.wrappedValue == .active
		let _ = PlusInstallDefaults.registered
		
		HStack(spacing: 18) {
			if isEditing {
				Button {
					_toggleSelection()
				} label: {
					Image(systemName: _isSelected ? "checkmark.circle.fill" : "circle")
						.foregroundColor(_isSelected ? .accentColor : .secondary)
						.font(.title2)
				}
				.buttonStyle(.borderless)
			}
			
			FRAppIconView(app: app, size: 57)
			
			NBTitleWithSubtitleView(
				title: app.name ?? .localized("Unknown"),
				subtitle: _desc,
				linelimit: 0
			)
			
			if !isEditing {
				_buttonActions(for: app)
			}
		}
		.padding(isRegular ? 12 : 0)
		.background(
			isRegular
				? RoundedRectangle(cornerRadius: 18, style: .continuous)
				.fill(_isSelected && isEditing ? Color.accentColor.opacity(0.1) : Color(.quaternarySystemFill))
				: nil
		)
		.contentShape(Rectangle())
		.onTapGesture {
			if isEditing {
				_toggleSelection()
			}
		}
		.swipeActions {
			if !isEditing {
				_actions(for: app)
			}
		}
	}
	
	private var _desc: String {
		if let version = app.version, let id = app.identifier {
			return "\(version) • \(id)"
		} else {
			return .localized("Unknown")
		}
	}
}


// MARK: - Extension: View
extension LibraryCellView {
	@ViewBuilder
	private func _actions(for app: AppInfoPresentable) -> some View {
		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			Storage.shared.deleteApp(for: app)
		}
	}
	
	@ViewBuilder
	private func _contextActions(for app: AppInfoPresentable) -> some View {
		Button(.localized("Get Info"), systemImage: "info.circle") {
			selectedInfoAppPresenting = AnyApp(base: app)
		}
	}
	
	@ViewBuilder
	private func _contextActionsExtra(for app: AppInfoPresentable) -> some View {
		if app.isSigned {
			if let id = app.identifier {
				Button(.localized("Open"), systemImage: "app.badge.checkmark") {
					UIApplication.openApp(with: id)
				}
			}
			Button(.localized("Install"), systemImage: "square.and.arrow.down") {
				selectedInstallAppPresenting = AnyApp(base: app)
			}
			Button(.localized("Re-sign"), systemImage: "signature") {
				selectedSigningAppPresenting = AnyApp(base: app)
			}
			Button(.localized("Export"), systemImage: "square.and.arrow.up") {
				selectedInstallAppPresenting = AnyApp(base: app, archive: true)
			}
		} else {
			Button(.localized("Install"), systemImage: "square.and.arrow.down") {
				selectedInstallAppPresenting = AnyApp(base: app)
			}
			Button(.localized("Sign"), systemImage: "signature") {
				selectedSigningAppPresenting = AnyApp(base: app)
			}
		}
	}
	
	@ViewBuilder
	private func _buttonActions(for app: AppInfoPresentable) -> some View {
		Group {
			if app.isSigned {
				Button {
					selectedInstallAppPresenting = AnyApp(base: app)
				} label: {
					FRExpirationPillView(
						title: .localized("Install"),
						revoked: certRevoked,
						// Modified: always show "Install" instead of the certificate's remaining-days count.
						expiration: nil
					)
				}
			} else {
				Button {
					_signDirectly(app)
				} label: {
					FRExpirationPillView(
						title: _isSigningDirectly ? .localized("Signing...") : "بدء التوقيع",
						revoked: false,
						expiration: nil
					)
				}
				.disabled(_isSigningDirectly)
			}
		}
		.buttonStyle(.borderless)
	}
	
	/// The certificate currently selected in Settings (same lookup SigningView uses).
	private func _selectedCertificate() -> CertificatePair? {
		let index = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		guard _certificates.indices.contains(index) else { return nil }
		return _certificates[index]
	}
	
	/// Modified: signs the app immediately using the last active certificate and the saved
	/// signing options, without opening the Signing screen. Mirrors SigningView's _start().
	private func _signDirectly(_ app: AppInfoPresentable) {
		var options = OptionsManager.shared.options
		let certificate = _selectedCertificate()
		
		guard certificate != nil || options.signingOption != .default else {
			UIAlertController.showAlertWithOk(
				title: .localized("No Certificate"),
				message: .localized("Please go to settings and import a valid certificate")
			)
			return
		}
		
		// ppq protection
		if
			options.ppqProtection,
			let identifier = app.identifier,
			certificate?.ppQCheck == true
		{
			options.appIdentifier = "\(identifier).\(options.ppqString)"
		}
		
		// saved identifier / display name rules
		if
			let currentBundleId = app.identifier,
			let newBundleId = options.identifiers[currentBundleId]
		{
			options.appIdentifier = newBundleId
		}
		
		if
			let currentName = app.name,
			let newName = options.displayNames[currentName]
		{
			options.appName = newName
		}
		
		let finalOptions = options
		_isSigningDirectly = true
		
		FR.signPackageFile(
			app,
			using: finalOptions,
			icon: nil,
			certificate: certificate
		) { error in
			_isSigningDirectly = false
			
			if let error {
				UIAlertController.showAlertWithOk(
					title: .localized("Error"),
					message: error.localizedDescription
				)
				return
			}
			
			if
				finalOptions.post_deleteAppAfterSigned,
				!app.isSigned
			{
				Storage.shared.deleteApp(for: app)
			}
			
			if finalOptions.post_installAppAfterSigned {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
					NotificationCenter.default.post(name: Notification.Name("Feather.installApp"), object: nil)
				}
			}
		}
	}
}
