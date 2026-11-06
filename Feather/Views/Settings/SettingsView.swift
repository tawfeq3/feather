//
//  SettingsView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import NimbleViews
import UIKit
import Darwin
import IDeviceSwift

// MARK: - View
struct SettingsView: View {
	@AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0
	@Environment(\.dismiss) private var dismiss
	
	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>
	
	private var selectedCertificate: CertificatePair? {
		guard
			_storedSelectedCert >= 0,
			_storedSelectedCert < _certificates.count
		else {
			return nil
		}
		return _certificates[_storedSelectedCert]
	}
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Settings")) {
			Form {
				
				Section {
					NavigationLink(destination: AppearanceView()) {
						Label(.localized("Appearance"), systemImage: "paintbrush")
					}
				}
				
				Section {
					NavigationLink(destination: InstallationView()) {
						Label(.localized("Installation"), systemImage: "arrow.down.circle")
					}
					NavigationLink(destination: PlusSigningOptionsView()) {
						Label(.localized("Signing Options"), systemImage: "signature")
					}
				}
				
				NBSection(.localized("Certificates")) {
					if let cert = selectedCertificate {
						CertificatesCellView(cert: cert)
					} else {
						Text(.localized("No Certificate"))
							.font(.footnote)
							.foregroundColor(.disabled())
					}
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
					}
				}
			}
		}
	}
}

// MARK: - Trimmed Signing Options (only the important ones)
struct PlusSigningOptionsView: View {
	@StateObject private var _optionsManager = OptionsManager.shared
	
	// MARK: Body
	var body: some View {
		NBList(.localized("Signing Options")) {
			NBSection(.localized("Protection")) {
				_toggle(
					.localized("PPQ Protection"),
					systemImage: "shield",
					isOn: $_optionsManager.options.ppqProtection
				)
			} footer: {
				Text(.localized("Enabling any protection will append a random string to the bundleidentifiers of the apps you sign, this is to ensure your Apple ID does not get flagged by Apple. However, when using a signing service you can ignore this."))
			}
			
			NBSection(.localized("Removal")) {
				_toggle(
					.localized("Remove URL Scheme"),
					systemImage: "ellipsis.curlybraces",
					isOn: $_optionsManager.options.removeURLScheme
				)
				
				_toggle(
					.localized("Remove Provisioning"),
					systemImage: "doc.badge.gearshape",
					isOn: $_optionsManager.options.removeProvisioning
				)
			} footer: {
				Text(.localized("Removing the provisioning file will exclude the mobileprovision file from being embedded inside of the application when signing, to help prevent any detection."))
			}
			
			NBSection(.localized("Post Signing")) {
				_toggle(
					.localized("Install After Signing"),
					systemImage: "arrow.down.circle",
					isOn: $_optionsManager.options.post_installAppAfterSigned
				)
				
				_toggle(
					.localized("Delete After Signing"),
					systemImage: "trash",
					isOn: $_optionsManager.options.post_deleteAppAfterSigned
				)
			} footer: {
				Text(.localized("This will delete your imported application after signing, to save on using unneeded space."))
			}
		}
		.onChange(of: _optionsManager.options) { _ in
			_optionsManager.saveOptions()
		}
	}
	
	@ViewBuilder
	private func _toggle(
		_ title: String,
		systemImage: String,
		isOn: Binding<Bool>
	) -> some View {
		Toggle(isOn: isOn) {
			Label(title, systemImage: systemImage)
		}
	}
}
