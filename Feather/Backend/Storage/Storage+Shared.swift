//
//  Storage+Shared.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import CoreData

// MARK: - Class extension: Apps (Shared)
extension Storage {
	func getUuidDirectory(for app: AppInfoPresentable) -> URL? {
		guard let uuid = app.uuid else { return nil }
		return app.isSigned
			? FileManager.default.signed(uuid)
			: FileManager.default.unsigned(uuid)
	}
	
	func getAppDirectory(for app: AppInfoPresentable) -> URL? {
		guard let url = getUuidDirectory(for: app) else { return nil }
		return FileManager.default.getPath(in: url, for: "app")
	}
	
	func deleteApp(for app: AppInfoPresentable) {
		do {
			if let url = getUuidDirectory(for: app) {
				try? FileManager.default.removeItem(at: url)
			}
			deleteSourceMetadata(for: app.uuid)
			if let object = app as? NSManagedObject {
				context.delete(object)
			}
			saveContext()
		}
	}
	
	/// Modified: duplicates an app inside the Library (its files + a new database entry with a new UUID).
	/// The copy lands in the same section (Signed / Imported) as the original and gets its own
	/// bundle identifier (the original one + a short random suffix), so both can be installed side by side.
	func cloneApp(for app: AppInfoPresentable, completion: @escaping (Error?) -> Void) {
		guard let sourceDirectory = getUuidDirectory(for: app) else {
			completion(CocoaError(.fileNoSuchFile))
			return
		}
		
		let newUUID = UUID().uuidString
		let isSigned = app.isSigned
		let destination = isSigned
			? FileManager.default.signed(newUUID)
			: FileManager.default.unsigned(newUUID)
		let fallbackIdentifier = app.identifier
		
		// Copying can be slow for big apps, so keep it off the main thread.
		DispatchQueue.global(qos: .userInitiated).async {
			var newIdentifier = fallbackIdentifier
			
			do {
				let fm = FileManager.default
				try fm.createDirectory(
					at: destination.deletingLastPathComponent(),
					withIntermediateDirectories: true
				)
				try fm.copyItem(at: sourceDirectory, to: destination)
				
				if
					let appURL = fm.getPath(in: destination, for: "app"),
					let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Info.plist")),
					let oldIdentifier = info["CFBundleIdentifier"] as? String
				{
					// Bundle identifiers only allow letters, digits, "-" and ".", so use a hex suffix.
					let suffix = "c" + newUUID.replacingOccurrences(of: "-", with: "").prefix(5).lowercased()
					let identifier = oldIdentifier + "." + suffix
					Storage.rewriteBundleIdentifiers(old: oldIdentifier, new: identifier, in: appURL)
					newIdentifier = identifier
				}
			} catch {
				try? FileManager.default.removeItem(at: destination)
				DispatchQueue.main.async { completion(error) }
				return
			}
			
			// Core Data work stays on the main thread.
			DispatchQueue.main.async {
				if let signed = app as? Signed {
					self.addSigned(
						uuid: newUUID,
						source: signed.source,
						certificate: signed.certificate,
						appName: signed.name,
						appIdentifier: newIdentifier,
						appVersion: signed.version,
						appIcon: signed.icon,
						completion: completion
					)
				} else {
					self.addImported(
						uuid: newUUID,
						source: app.source,
						appName: app.name,
						appIdentifier: newIdentifier,
						appVersion: app.version,
						appIcon: app.icon,
						completion: completion
					)
				}
			}
		}
	}
	
	/// Replaces `old` with `new` in the main app's Info.plist and in every nested app / extension
	/// (same keys the signer updates when the identifier is changed while signing).
	private static func rewriteBundleIdentifiers(old: String, new: String, in appURL: URL) {
		var bundles: [URL] = [appURL]
		if let enumerator = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: nil) {
			for case let url as URL in enumerator where url.pathExtension == "app" || url.pathExtension == "appex" {
				bundles.append(url)
			}
		}
		
		for bundle in bundles {
			let plistURL = bundle.appendingPathComponent("Info.plist")
			guard let dict = NSDictionary(contentsOf: plistURL)?.mutableCopy() as? NSMutableDictionary else {
				continue
			}
			
			var changed = false
			func replace(in target: NSMutableDictionary, key: String) {
				guard let value = target[key] as? String else { return }
				let updated = value.replacingOccurrences(of: old, with: new)
				if updated != value {
					target[key] = updated
					changed = true
				}
			}
			
			replace(in: dict, key: "CFBundleIdentifier")
			replace(in: dict, key: "WKCompanionAppBundleIdentifier")
			
			if let ext = (dict["NSExtension"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary {
				if let attributes = (ext["NSExtensionAttributes"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary {
					replace(in: attributes, key: "WKAppBundleIdentifier")
					ext["NSExtensionAttributes"] = attributes
				}
				replace(in: ext, key: "NSExtensionFileProviderDocumentGroup")
				dict["NSExtension"] = ext
			}
			
			if changed {
				dict.write(to: plistURL, atomically: true)
			}
		}
	}
	
	func getCertificate(from app: AppInfoPresentable) -> CertificatePair? {
		if let signed = app as? Signed {
			return signed.certificate
		}
		return nil
	}
}

// MARK: - Helpers
struct AnyApp: Identifiable {
	let base: AppInfoPresentable
	var archive: Bool = false
	
	var id: String {
		base.uuid ?? UUID().uuidString
	}
}

protocol AppInfoPresentable {
	var name: String? { get }
	var version: String? { get }
	var identifier: String? { get }
	var date: Date? { get }
	var icon: String? { get }
	var uuid: String? { get }
	var source: URL? { get }
	var isSigned: Bool { get }
	
}

extension Signed: AppInfoPresentable {
	var isSigned: Bool { true }
}

extension Imported: AppInfoPresentable {
	var isSigned: Bool { false }
}
