import ManagedSettings
import ManagedSettingsUI
import UIKit

/// iOS asks this extension what to draw when the user opens a blocked app or website.
/// Phase 1: read today's target from the App Group ("Locked until you check in — today: find a bench").
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
            title: .init(text: "QuestLock", color: .label),
            subtitle: .init(text: "Locked until you check in.", color: .secondaryLabel)
        )
    }
}
