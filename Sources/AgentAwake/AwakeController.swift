import Foundation
import AppKit
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement

/// Owns all of the keep-awake state.
///
/// Two separate mechanisms are used:
/// 1. An IOKit power assertion. This is the normal, Apple-sanctioned way to stop
///    idle sleep while the lid is open. No password needed.
/// 2. `pmset -a disablesleep 1`. This is the only way to stop a MacBook from
///    sleeping when the lid is closed without an external display. It is a
///    system-wide setting that needs root, so the app runs it through `sudo`
///    (with an optional narrow password-free rule) or an admin prompt.
final class AwakeController: ObservableObject {
    static let shared = AwakeController()

    private enum Key {
        static let enabled = "enabled"
        static let onlyOnPower = "onlyOnPower"
        static let lidClosedMode = "lidClosedMode"
        static let keepDisplayOn = "keepDisplayOn"
    }

    static let sudoersPath = "/etc/sudoers.d/agentawake"
    private static let pmset = "/usr/bin/pmset"

    private let defaults = UserDefaults.standard

    // MARK: User settings

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled); apply() }
    }
    @Published var onlyOnPower: Bool {
        didSet { defaults.set(onlyOnPower, forKey: Key.onlyOnPower); apply() }
    }
    @Published var lidClosedMode: Bool {
        didSet { defaults.set(lidClosedMode, forKey: Key.lidClosedMode); apply() }
    }
    @Published var keepDisplayOn: Bool {
        didSet { defaults.set(keepDisplayOn, forKey: Key.keepDisplayOn); apply() }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !updatingLoginItem, launchAtLogin != oldValue else { return }
            updateLoginItem()
        }
    }

    // MARK: Live state

    @Published private(set) var onACPower: Bool
    @Published private(set) var isHoldingAwake = false
    @Published private(set) var lidSleepDisabled: Bool
    @Published private(set) var passwordFreeReady: Bool
    @Published private(set) var lastError: String?

    /// nil = no assertion held; true/false = held, and whether it also keeps the display on.
    private var heldAssertionKeepsDisplay: Bool?
    private var assertionID: IOPMAssertionID = 0
    private var powerSource: CFRunLoopSource?
    private var updatingLoginItem = false

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Key.enabled: false,
            Key.onlyOnPower: true,
            Key.lidClosedMode: false,
            Key.keepDisplayOn: false,
        ])
        enabled = d.bool(forKey: Key.enabled)
        onlyOnPower = d.bool(forKey: Key.onlyOnPower)
        lidClosedMode = d.bool(forKey: Key.lidClosedMode)
        keepDisplayOn = d.bool(forKey: Key.keepDisplayOn)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        onACPower = Self.readIsOnACPower()
        lidSleepDisabled = Self.readSleepDisabled()
        passwordFreeReady = Self.checkPasswordFree()

        startPowerMonitoring()
        // Run once the app has finished launching. This also cleans up a leftover
        // `disablesleep 1` from a crash or forced quit.
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    var statusText: String {
        if !enabled { return "Off: your Mac sleeps normally" }
        if onlyOnPower && !onACPower { return "Paused: running on battery" }
        if lidClosedMode && lidSleepDisabled { return "On: awake, even with the lid closed" }
        return "On: keeping your Mac awake"
    }

    // MARK: Core logic

    /// Brings the system in line with the current settings and power source.
    private func apply() {
        let powerOK = !onlyOnPower || onACPower
        let shouldHold = enabled && powerOK

        // 1. Idle-sleep assertion (lid open).
        let wantedAssertion: Bool? = shouldHold ? keepDisplayOn : nil
        if wantedAssertion != heldAssertionKeepsDisplay {
            releaseAssertion()
            if let keepDisplay = wantedAssertion {
                createAssertion(keepDisplay: keepDisplay)
            }
        }
        isHoldingAwake = heldAssertionKeepsDisplay != nil

        // 2. Lid-closed mode.
        let wantLidMode = shouldHold && lidClosedMode
        if wantLidMode != lidSleepDisabled {
            setSleepDisabled(wantLidMode)
        }
    }

    func shutdown() {
        releaseAssertion()
        if lidSleepDisabled {
            setSleepDisabled(false)
        }
    }

    // MARK: Power assertion

    private func createAssertion(keepDisplay: Bool) {
        let type = (keepDisplay
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep) as CFString
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "AgentAwake is keeping this Mac awake" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
            heldAssertionKeepsDisplay = keepDisplay
        } else {
            lastError = "Couldn't create power assertion (error \(result))."
        }
    }

    private func releaseAssertion() {
        if heldAssertionKeepsDisplay != nil {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            heldAssertionKeepsDisplay = nil
        }
    }

    // MARK: Power source

    private func startPowerMonitoring() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<AwakeController>.fromOpaque(ctx).takeUnretainedValue()
            me.powerSourceChanged()
        }, context)?.takeRetainedValue() else { return }
        // Common modes so it still fires while the menu is open.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSource = source
    }

    private func powerSourceChanged() {
        let now = Self.readIsOnACPower()
        guard now != onACPower else { return }
        onACPower = now
        apply()
    }

    static func readIsOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return true } // Desktops with no battery info count as plugged in.
        return (type as String) == kIOPMACPowerKey
    }

    static func isLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(
            root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return false }
        return (value as? Bool) ?? false
    }

    // MARK: Lid-closed mode (pmset disablesleep)

    private func setSleepDisabled(_ disable: Bool) {
        // Lid-closed mode is only allowed with the password-free rule in place.
        // Otherwise unplugging the charger with the lid shut would pop up a
        // password prompt nobody can answer, and the Mac would stay awake in a bag.
        if disable && !passwordFreeReady {
            guard installPasswordFreeRule() else {
                lastError = "Lid-closed mode needs a one-time setup with your password. It's off for now."
                if lidClosedMode { lidClosedMode = false }
                return
            }
        }

        let arg = disable ? "1" : "0"
        var ok = Self.run("/usr/bin/sudo", ["-n", Self.pmset, "-a", "disablesleep", arg]) == 0
        if !ok {
            // No password-free rule installed: fall back to the standard admin prompt.
            ok = Self.runAsAdmin("\(Self.pmset) -a disablesleep \(arg)")
        }

        lidSleepDisabled = Self.readSleepDisabled()

        if lidSleepDisabled != disable {
            if disable {
                lastError = "Lid-closed mode needs your admin password. It's off for now."
                if lidClosedMode { lidClosedMode = false }
            } else {
                lastError = "Couldn't turn normal sleep back on. Run: sudo pmset -a disablesleep 0"
            }
            return
        }
        lastError = nil

        // If we just handed sleep back while the lid is shut (for example the
        // charger was unplugged with the Mac in a bag), sleep right away.
        if !disable && Self.isLidClosed() {
            _ = Self.run(Self.pmset, ["sleepnow"])
        }
    }

    static func readSleepDisabled() -> Bool {
        guard let output = runCapturing(pmset, ["-g"]) else { return false }
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" {
                return parts[1] == "1"
            }
        }
        return false
    }

    static func checkPasswordFree() -> Bool {
        run("/usr/bin/sudo", ["-n", "-l", pmset, "-a", "disablesleep", "1"]) == 0
    }

    /// Installs a sudoers rule that lets this user run exactly
    /// `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password.
    /// That's what lets the app switch automatically when you plug in or unplug.
    func setUpLidMode() {
        if installPasswordFreeRule() { apply() }
    }

    @discardableResult
    func installPasswordFreeRule() -> Bool {
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: \(Self.pmset) -a disablesleep 0, \(Self.pmset) -a disablesleep 1\n"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("agentawake-sudoers")
        do {
            try rule.write(to: tmp, atomically: true, encoding: .utf8)
        } catch {
            lastError = "Couldn't write the setup file."
            return false
        }
        let t = Self.shellQuote(tmp.path)
        let command = "/usr/sbin/visudo -cf \(t) && /usr/bin/install -m 0440 -o root -g wheel \(t) \(Self.sudoersPath)"
        let ok = Self.runAsAdmin(command)
        try? FileManager.default.removeItem(at: tmp)

        passwordFreeReady = Self.checkPasswordFree()
        if ok && passwordFreeReady {
            lastError = nil
            return true
        }
        lastError = "Setup didn't finish, so lid-closed mode stays off."
        return false
    }

    // MARK: Login item

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        updatingLoginItem = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        updatingLoginItem = false
    }

    // MARK: Process helpers

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }

    static func runCapturing(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Runs a shell command as root via the standard macOS admin password prompt.
    static func runAsAdmin(_ shellCommand: String) -> Bool {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
