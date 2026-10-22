import ManagedSettings
import ManagedSettingsUI
import UIKit

/// iOS asks this extension what to draw when the user opens a blocked app or website.
final class ShieldConfigExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        Self.lockedShield
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        Self.lockedShield
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        Self.lockedShield
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        Self.lockedShield
    }

    private static var lockedShield: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            icon: UIImage(systemName: "lock.fill"),
            title: .init(text: "Locked until you check in", color: .label),
            subtitle: .init(text: "Today's quest: \(SharedStore.todayTarget)", color: .secondaryLabel),
            primaryButtonLabel: .init(text: "Check in", color: .white),
            primaryButtonBackgroundColor: .systemIndigo
        )
    }
}
