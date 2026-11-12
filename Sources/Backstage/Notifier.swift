import Foundation
import UserNotifications
import BackstageCore

/// 새로 들어온 백그라운드 항목을 시스템 알림으로 알린다. 기본은 꺼져 있고, 켤 때 권한을 묻는다.
@MainActor
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var enabled: Bool
    @Published var error: String?
    /// 알림을 눌렀을 때 그 항목을 연다.
    var onOpen: ((Job.ID?) -> Void)?

    static let key = "notifyNewItems"
    // 앱 묶음 없이 실행하면(swift run) 알림 센터를 쓸 수 없다
    private let available = Bundle.main.bundleIdentifier != nil

    override init() {
        enabled = UserDefaults.standard.bool(forKey: Notifier.key)
        super.init()
        if available, enabled { UNUserNotificationCenter.current().delegate = self }
    }

    func set(_ want: Bool) {
        guard available else { error = "설치한 앱으로 실행할 때만 알림을 쓸 수 있어요"; return }
        guard want else { enabled = false; UserDefaults.standard.set(false, forKey: Notifier.key); return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.enabled = granted
                self.error = granted ? nil : "시스템 설정 > 알림에서 Backstage 알림을 허용해 주세요"
                UserDefaults.standard.set(granted, forKey: Notifier.key)
            }
        }
    }

    func announce(_ jobs: [Job]) {
        guard available, enabled, let first = jobs.first else { return }
        let content = UNMutableNotificationContent()
        content.title = jobs.count == 1 ? "새 백그라운드 항목" : "새 백그라운드 항목 \(jobs.count)개"
        content.body = jobs.prefix(3).map { "\($0.label) · \($0.source.rawValue)" }.joined(separator: "\n")
        content.sound = .default
        content.userInfo = ["job": first.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["job"] as? String
        await MainActor.run { self.onOpen?(id) }
    }
}
