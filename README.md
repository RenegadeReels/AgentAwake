# AgentAwake: keep your Mac awake with the lid closed while AI agents work overnight

[![Build](https://github.com/RenegadeReels/AgentAwake/actions/workflows/build.yml/badge.svg)](https://github.com/RenegadeReels/AgentAwake/actions/workflows/build.yml)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**AgentAwake is a free, open-source macOS menu bar app that stops your MacBook
from sleeping, even with the lid closed, so your AI coding agents, local LLMs,
long builds and downloads keep running overnight.** Close the laptop, plug it
in, walk away. When you unplug, it steps aside and your Mac sleeps normally.

Built for people running Claude Code, Codex, Cursor agents, Aider, Ollama,
LM Studio, or any long job that dies the moment the lid shuts.

## Why AgentAwake?

- **Closed-lid mode without an external display.** macOS normally forces a
  MacBook to sleep when you close it unless a monitor, keyboard and charger are
  attached (clamshell mode). AgentAwake keeps it running with nothing attached.
- **"Only run when connected to power."** On by default. Unplug and AgentAwake
  pauses instantly, turns normal sleep back on, and puts a closed Mac to sleep so
  it never cooks in your bag. Plug back in and it resumes by itself.
- **One click from the menu bar.** No terminal commands to remember, no
  `caffeinate` windows left open.
- **Never changes your Energy settings.** It overrides sleep only while it's on.
  Turn it off or quit, and your normal sleep timers are back.
- **Tiny, native and open source.** Swift and SwiftUI, no Electron, no
  analytics, no network access. About 400 lines you can read in ten minutes.

## Features

| Menu item | What it does |
| --- | --- |
| **Keep Mac Awake** | Main switch. Prevents idle sleep while it's on. |
| **Only Run When Connected to Power** | Pauses automatically on battery, resumes on AC power. |
| **Stay Awake With Lid Closed** | Keeps the Mac running with the lid shut, no external monitor needed. |
| **Keep Display On** | Also stops the screen from dimming and sleeping (lid open). |
| **Open at Login** | Starts AgentAwake when you log in. |

The menu bar icon is a moon while your Mac sleeps normally and a sun while
AgentAwake is keeping it awake.

## Install

### Option 1: Download

1. Grab `AgentAwake-macOS.zip` from the
   [latest release](https://github.com/RenegadeReels/AgentAwake/releases/latest).
2. Unzip it and drag **AgentAwake.app** into **Applications**.
3. The app isn't notarized by Apple, so the first time, right-click it and choose
   **Open**, then **Open** again. (Or run
   `xattr -dr com.apple.quarantine /Applications/AgentAwake.app`.)

### Option 2: Build from source

Requires macOS 13 Ventura or newer and Apple's command line tools
(`xcode-select --install`).

```bash
git clone https://github.com/RenegadeReels/AgentAwake.git
cd AgentAwake
./build-app.sh --install
```

That builds `AgentAwake.app`, copies it to `/Applications`, and launches it.

## How it works

**Lid open:** AgentAwake holds a standard IOKit power assertion
(`PreventUserIdleSystemSleep`, or `PreventUserIdleDisplaySleep` with Keep
Display On), the same mechanism video players use. No password, nothing
system-wide, released the moment the app quits.

**Lid closed:** the only switch macOS offers is
`sudo pmset -a disablesleep 1`. It's system-wide and needs admin rights. The
first time you enable closed-lid mode, AgentAwake asks for your password **once**
and installs a narrow sudoers rule at `/etc/sudoers.d/agentawake` that allows
your account to run exactly these two commands without a password:

```
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
```

Nothing else. That's what lets AgentAwake turn sleep back on silently the
instant you unplug, even with the lid closed. Closed-lid mode refuses to turn on
without this rule, because a password prompt on a closed laptop is a prompt nobody
can answer.

**Power monitoring:** AgentAwake listens for power-source changes from IOKit
(`IOPSNotificationCreateRunLoopSource`), so switching between battery and AC is
handled immediately, without polling.

**Safety nets:**

- Unplugged with the lid closed? Sleep is re-enabled and the Mac sleeps right away.
- Quitting AgentAwake always restores normal sleep.
- If it ever crashes, the next launch notices `SleepDisabled` is still set and
  fixes it.

## AgentAwake vs. caffeinate, Amphetamine and others

| | AgentAwake | `caffeinate` | Typical keep-awake apps |
| --- | --- | --- | --- |
| Works with the lid closed, no external display | ✅ | ❌ | Varies |
| Automatically pauses on battery | ✅ | ❌ | Some |
| Sleeps a closed Mac the moment it's unplugged | ✅ | ❌ | Rarely |
| Menu bar toggle | ✅ | ❌ | ✅ |
| Open source | ✅ | ✅ | Some |
| Free | ✅ | ✅ | Most |

## FAQ

**Will my Mac overheat with the lid closed?**
A closed MacBook dissipates less heat. It's fine on a desk for long AI or build
jobs, but don't run it closed inside a bag, on a bed or under a pillow. That's
exactly why "Only Run When Connected to Power" is on by default.

**Does it change my Energy / Battery settings?**
No. It overrides sleep only while active. Your settings in System Settings are
untouched.

**Does it stop my screen from locking?**
With Keep Display On, the display never sleeps, so it won't lock from the
display-sleep timer. You can still lock it yourself any time (⌃⌘Q).

**Can macOS still force sleep?**
Yes. Thermal emergencies and a critically low battery still put the Mac to sleep.

**How do I check or reset the closed-lid setting manually?**
`pmset -g | grep SleepDisabled` shows it. `sudo pmset -a disablesleep 0` resets it.

**Does it work on Intel Macs and Apple silicon?**
Yes, on any Mac running macOS 13 Ventura or newer.

## Uninstall

```bash
sudo pmset -a disablesleep 0
sudo rm -f /etc/sudoers.d/agentawake
rm -rf /Applications/AgentAwake.app
```

## Contributing

Issues and pull requests are welcome. Ideas on the list: timed sessions
("stay awake for 3 hours"), keep awake while a specific app or process is
running, and a notarized release.

## License

[MIT](LICENSE)

---

*Keywords: keep Mac awake lid closed, prevent MacBook sleep when lid is closed,
closed-lid mode without external monitor, clamshell mode without display, macOS
disable sleep, caffeinate alternative, Amphetamine alternative, keep AI agents
running overnight, Claude Code overnight, run local LLM overnight on Mac.*
