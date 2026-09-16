import Foundation

/// Why the battery warning banner is on screen (SPEC §8). The banner's
/// wording and what its buttons do differ by context:
///
/// - `enabling`: the user asked for the lid tier on battery; nothing has been
///   turned on yet, so "Cancel" leaves the mode at `off`.
/// - `powerLost`: the lid tier was running on AC and the charger came out;
///   the tier keeps running while the user decides (asking is the point —
///   silently downgrading or stopping is what SPEC §8 forbids), so "Cancel"
///   turns it off and "Continue" is a no-op confirmation.
enum BatteryWarningContext {
    case enabling
    case powerLost
}

/// The banner's three choices. Session-wide suppression is separate: it's the
/// "don't remind again this session" toggle the user can set before choosing,
/// and it outlives the banner until the app restarts.
enum BatteryWarningChoice {
    /// Keep (or proceed with) the lid tier.
    case keepLid
    /// Step down to the prevent-idle tier instead.
    case useIdle
    /// Don't keep the lid tier: a no-op when it was never turned on, an
    /// explicit turn-off when the warning came from losing power.
    case cancel
}
