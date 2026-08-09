import Foundation
import UIKit

enum DayPhase: String {
    case deepNight, lateNight, dawn, sunrise, morning, midday, afternoon, goldenHour, sunset, dusk

    var displayName: String {
        switch self {
        case .deepNight: return "Deep Night"
        case .lateNight: return "Late Night"
        case .dawn: return "Dawn"
        case .sunrise: return "Sunrise"
        case .morning: return "Morning"
        case .midday: return "Midday"
        case .afternoon: return "Afternoon"
        case .goldenHour: return "Golden Hour"
        case .sunset: return "Sunset"
        case .dusk: return "Dusk"
        }
    }

    var isDark: Bool {
        self == .deepNight || self == .lateNight || self == .dusk
    }
}

/// A snapshot of the sky derived from the device's real clock and time zone.
struct SkyState {
    var date: Date
    var localHour: Float          // 0..24
    var sunElevation: Float       // radians, negative below horizon
    var sunAzimuth: Float         // radians, 0 = north, increasing toward east
    var moonElevation: Float
    var moonAzimuth: Float
    var phase: DayPhase

    /// Sun position on a unit sphere in world space (North = +Z, East = +X, Up = +Y).
    var sunDirection: SIMD3<Float> {
        SIMD3<Float>(x: cosf(sunElevation) * sinf(sunAzimuth),
                       y: sinf(sunElevation),
                       z: cosf(sunElevation) * cosf(sunAzimuth))
    }

    var moonDirection: SIMD3<Float> {
        SIMD3<Float>(x: cosf(moonElevation) * sinf(moonAzimuth),
                       y: sinf(moonElevation),
                       z: cosf(moonElevation) * cosf(moonAzimuth))
    }

    /// 0 at night, 1 with the sun high.
    var daylight: Float { smoothstep(-0.10, 0.28, sunElevation) }

    /// Peaks when the sun is near the horizon.
    var horizonWarmth: Float {
        let e = sunElevation
        return smoothstep(-0.22, 0.02, e) * (1 - smoothstep(0.05, 0.34, e))
    }

    var sunColor: RGBColor {
        let warm = RGBColor(1.00, 0.55, 0.28)
        let gold = RGBColor(1.00, 0.82, 0.58)
        let noon = RGBColor(1.00, 0.96, 0.90)
        let t = smoothstep(-0.05, 0.30, sunElevation)
        let base = warm.mixed(with: gold, smoothstep(-0.10, 0.12, sunElevation))
        return base.mixed(with: noon, t * t)
    }

    var skyZenithColor: RGBColor {
        let night = RGBColor(0.035, 0.045, 0.085)
        let dawnC = RGBColor(0.22, 0.24, 0.42)
        let day = RGBColor(0.30, 0.52, 0.86)
        if sunElevation < -0.20 { return night }
        if sunElevation < 0.02 {
            return night.mixed(with: dawnC, smoothstep(-0.20, 0.02, sunElevation))
        }
        return dawnC.mixed(with: day, smoothstep(0.0, 0.30, sunElevation))
    }

    var skyHorizonColor: RGBColor {
        let night = RGBColor(0.07, 0.08, 0.14)
        let ember = RGBColor(0.92, 0.46, 0.28)
        let day = RGBColor(0.74, 0.84, 0.94)
        var c = night.mixed(with: ember, horizonWarmth)
        c = c.mixed(with: day, smoothstep(0.06, 0.34, sunElevation))
        return c
    }

    var ambientColor: RGBColor {
        skyZenithColor.mixed(with: skyHorizonColor, 0.45).lightened(0.12 * daylight)
    }

    /// Should the paper lantern be lit if the player left it on "auto"?
    var wantsLampLight: Bool { sunElevation < 0.06 }
}

// The hand-rolled vector that used to live here is gone. It existed so that
// `SkyState` could stay free of SceneKit at the model layer, which was the right
// instinct and the wrong remedy — `SIMD3<Float>` is in the standard library, so
// the model layer can have vectors without importing a renderer at all.

enum WorldClock {

    /// Latitude used for the solar arc. Longitude is inferred from the device time zone,
    /// which is enough to make sunrise land at a believable hour anywhere on Earth.
    static var latitudeDegrees: Double = 35.0

#if DEBUG
    /// Developer-only offset, in seconds, so the whole day can be scrubbed through
    /// from the settings sheet instead of waiting for dusk to arrive. Never compiled
    /// into a release build.
    static var debugTimeOffset: TimeInterval = 0

    /// Pins the clock to a given local hour, for screenshots and CI. Set with the
    /// MEOW_FORCE_HOUR environment variable, e.g. MEOW_FORCE_HOUR=6 for dawn.
    static func applyDebugEnvironment() {
        guard let raw = ProcessInfo.processInfo.environment["MEOW_FORCE_HOUR"],
              let target = Double(raw) else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        let c = cal.dateComponents([.hour, .minute, .second], from: now)
        let current = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        debugTimeOffset = (target - current) * 3600
    }
#endif

    static func sky(at date: Date = Date(), timeZone: TimeZone = .current) -> SkyState {
#if DEBUG
        let date = date.addingTimeInterval(debugTimeOffset)
#endif
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour = Double(comps.hour ?? 12)
        let minute = Double(comps.minute ?? 0)
        let second = Double(comps.second ?? 0)
        let localHour = hour + minute / 60 + second / 3600

        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 172)

        // Longitude implied by the UTC offset, then the correction back to the zone meridian.
        let offsetHours = Double(timeZone.secondsFromGMT(for: date)) / 3600.0
        let zoneMeridian = offsetHours * 15.0
        let longitude = zoneMeridian   // best guess: middle of the zone

        // Equation of time (minutes).
        let b = 2 * Double.pi * (dayOfYear - 81) / 364.0
        let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)

        let timeCorrection = 4 * (longitude - zoneMeridian) + eot
        let solarTime = localHour + timeCorrection / 60.0
        let hourAngle = (solarTime - 12.0) * 15.0 * .pi / 180.0

        let declination = 23.45 * .pi / 180.0 * sin(2 * Double.pi * (284 + dayOfYear) / 365.0)
        let lat = latitudeDegrees * .pi / 180.0

        let sinEl = sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)
        let elevation = asin(clampD(sinEl, -1, 1))

        let cosAz = (sin(declination) - sin(elevation) * sin(lat)) / max(0.0001, cos(elevation) * cos(lat))
        var azimuth = acos(clampD(cosAz, -1, 1))
        if hourAngle > 0 { azimuth = 2 * Double.pi - azimuth }   // afternoon → west

        // The moon simply runs a lazy counter-arc so nights are never pitch black.
        let moonAngle = (solarTime + 12.0 - 12.0) * 15.0 * .pi / 180.0
        let moonSinEl = sin(lat) * sin(-declination * 0.6) + cos(lat) * cos(declination * 0.6) * cos(moonAngle + .pi)
        let moonEl = asin(clampD(moonSinEl, -1, 1))
        let moonAz = (azimuth + Double.pi).truncatingRemainder(dividingBy: 2 * Double.pi)

        let el = Float(elevation)
        let phase: DayPhase
        switch (el, Float(localHour)) {
        case let (e, h) where e < -0.30 && (h < 4 || h >= 23): phase = .deepNight
        case let (e, _) where e < -0.30: phase = .lateNight
        case let (e, h) where e < -0.10 && h < 12: phase = .dawn
        case let (e, _) where e < -0.10: phase = .dusk
        case let (e, h) where e < 0.10 && h < 12: phase = .sunrise
        case let (e, _) where e < 0.10: phase = .sunset
        case let (e, h) where e < 0.30 && h < 12: phase = .morning
        case let (e, _) where e < 0.30: phase = .goldenHour
        case let (_, h) where h < 14: phase = .midday
        default: phase = .afternoon
        }

        return SkyState(date: date,
                        localHour: Float(localHour),
                        sunElevation: el,
                        sunAzimuth: Float(azimuth),
                        moonElevation: Float(moonEl),
                        moonAzimuth: Float(moonAz),
                        phase: phase)
    }

    static func clockString(_ date: Date = Date()) -> String {
#if DEBUG
        let date = date.addingTimeInterval(debugTimeOffset)
#endif
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}
