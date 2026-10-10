import Foundation

extension AppModel {
    func setLang(_ value: Lang) {
        guard value != lang else { return }
        L10n.set(value)
        lang = value
        refreshStations()
        banners.removeAll()
        rescheduleNotifications()
    }
}
