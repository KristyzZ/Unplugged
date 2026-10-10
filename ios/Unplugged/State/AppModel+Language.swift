import Foundation

extension AppModel {
    func setLang(_ value: Lang) {
        guard value != lang else { return }
        L10n.set(value)
        lang = value
        #if os(iOS)
        lastWidgetSnapshot = nil
        #endif
        NotificationManager.shared.registerCategories()
        refreshStations()
        banners.removeAll()
        rescheduleNotifications()
    }
}
