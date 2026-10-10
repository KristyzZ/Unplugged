import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Listing photos, as JPEG files in Application Support/HostPhotos. Kept out of
/// the saved state so it stays small.
enum HostPhotoStore {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("HostPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    #if canImport(UIKit)
    /// Saves a downscaled copy and returns its file name.
    static func save(_ image: UIImage, id: String) -> String? {
        let name = "\(id)-\(UUID().uuidString.prefix(6)).jpg"
        guard let data = downscaled(image, maxSide: 1600).jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func load(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent(name).path)
    }

    private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    #endif

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}
