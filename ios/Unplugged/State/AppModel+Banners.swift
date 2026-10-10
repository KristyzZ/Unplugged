import Foundation
import SwiftUI

struct Banner: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let body: String?
}

extension AppModel {
    func showBanner(_ title: String, _ body: String? = nil) {
        let banner = Banner(title: title, body: body)
        banners.append(banner)
        AccessibilityNotification.Announcement([title, body].compactMap { $0 }.joined(separator: ". ")).post()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.banners.removeAll { $0.id == banner.id }
        }
    }
}
