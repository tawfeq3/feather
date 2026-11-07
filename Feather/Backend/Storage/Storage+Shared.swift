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
	/// The copy lands in the same section (Signed / Imported) as the original.
	func cloneApp(for app: AppInfoPresentable, completion: @escaping (Error?) -> Void) {
		guard let sourceDirectory = getUuidDirectory(for: app) else {
			completion(CocoaError(.fileNoSuchFile))
			return
		}

		let newUUID = UUID().uuidString
		let destination = app.isSigned
			? FileManager.default.signed(newUUID)
			: FileManager.default.unsigned(newUUID)

		do {
			try FileManager.default.createDirectory(
				at: destination.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try FileManager.default.copyItem(at: sourceDirectory, to: destination)
		} catch {
			completion(error)
			return
		}

		if let signed = app as? Signed {
			addSigned(
				uuid: newUUID,
				source: signed.source,
				certificate: signed.certificate,
				appName: signed.name,
				appIdentifier: signed.identifier,
				appVersion: signed.version,
				appIcon: signed.icon,
				completion: completion
			)
		} else {
			addImported(
				uuid: newUUID,
				source: app.source,
				appName: app.name,
				appIdentifier: app.identifier,
				appVersion: app.version,
				appIcon: app.icon,
				completion: completion
			)
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
