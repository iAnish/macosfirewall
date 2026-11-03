# iAnish Firewall

A lightweight, menu-bar-only application firewall for macOS 14 (Sonoma) and later. The first time an app tries to use the network, iAnish Firewall asks whether to **Allow** or **Block** it and remembers your answer. It also keeps a searchable history of the last 36 hours of network connections.

It runs entirely on your own Mac and needs **no Apple Developer account, no signing certificate, no system/network extension and no admin password**.

> **Please read [Limitations](#limitations).** iAnish Firewall works in user space by watching which apps have open connections. It is not a kernel-level packet filter, and "Block" works by terminating the app's processes.

## Features

- **Menu bar only**: a shield icon, no Dock icon, no main window.
- **First-connection prompt**: a dialog shows the app's icon and name, the direction (Incoming/Outgoing), the connection type and the destination, with **Allow** and **Block** buttons. The app is paused while you decide.
- **Remembered decisions**: your choice is stored per app and applied to every later connection from that app.
- **Settings**: lists of allowed and blocked apps (5 per page) where you can block, unblock or forget an app at any time.
- **History**: the latest 100 connections from the last 36 hours, stored in SQLite, with sorting, search and paging.
- **Readable addresses**: IPv4 addresses are shown as they are; for IPv6, the website name is shown when it can be found.
- **Finder shortcut**: right-click a history row to reveal the app in Finder.
- **Local and private**: nothing leaves your Mac. Data lives in one SQLite file.
- **Optional Launch at Login**.

## How it works

```
                 every 0.5 s
 ┌──────────────┐   ┌────────────────────┐   ┌─────────────┐
 │ Menu bar app │──▶│ Connection monitor │──▶│ Rule lookup │
 └──────────────┘   │ (libproc sockets)  │   └──────┬──────┘
        ▲           └────────────────────┘          │
        │                                           ▼
 ┌──────┴───────┐        ┌───────────────────────────────────────────┐
 │ Allow / Block│◀───────│ known allowed → log                       │
 │ dialog       │        │ known blocked → terminate app, log        │
 └──────┬───────┘        │ unknown       → pause app, ask the user   │
        │                └───────────────────────────────────────────┘
        ▼
 ┌──────────────┐
 │ SQLite       │  rules + 36 h of connection history
 └──────────────┘
```

1. A background monitor polls, every 0.5 seconds, the open TCP sockets (established or connecting) and connected UDP sockets of every process visible to your user account, using the `libproc` system API.
2. Each process is mapped to an app. Helper processes inside an app bundle map to the outermost `.app`, so one rule covers the whole app (for example *Google Chrome Helper* → *Google Chrome*).
3. The app's rule decides what happens:
   - **Allowed**: the connection is logged.
   - **Blocked**: the app's processes are sent `SIGTERM`, then `SIGKILL` if they are still connected on a later poll. The attempt is logged as *Blocked*.
   - **Unknown**: all the app's processes are paused (`SIGSTOP`) and the Allow/Block dialog is shown. **Allow** resumes them (`SIGCONT`); **Block** resumes and then terminates them. The answer is saved as a rule.
4. Quitting iAnish Firewall resumes any app it had paused.

**Connection types** shown in History: `DNS` (port 53), `HTTP` (TCP 80/8080), `HTTPS` (TCP 443), `QUIC` (UDP 443), otherwise `TCP` or `UDP`. A connection is **Incoming** if its local port is one the same process is listening on, otherwise **Outgoing**.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon or Intel
- Xcode Command Line Tools (provides `swift`, `swiftc`, `lipo`, `codesign`). Full Xcode is not required.

```bash
xcode-select --install
```

## Installation

There is no prebuilt download; you build the app yourself (about a minute).

```bash
git clone https://github.com/iAnish/macosfirewall.git
cd macosfirewall
./build.sh
open build/iAnishFirewall.app
```

`build.sh` produces `build/iAnishFirewall.app` as a universal binary (arm64 + x86_64) and signs it ad hoc. To build for your Mac's architecture only, which is faster:

```bash
ARCHS=arm64 ./build.sh      # Apple Silicon
ARCHS=x86_64 ./build.sh     # Intel
```

**Optional:** copy `build/iAnishFirewall.app` to `/Applications`. This is recommended if you want *Launch at Login* to work.

**Gatekeeper:** because the app is not notarized, macOS may warn about it if it was downloaded or copied from another machine. Right-click the app, choose **Open**, then confirm. An app you build locally normally opens without a warning.

### Try it safely first (demo mode)

Demo mode uses a throwaway database filled with sample apps and history, plus a simulated first-connection prompt for "Notes". It never pauses or terminates real processes.

```bash
swift run iAnishFirewall --demo
```

### Development

```bash
swift build
swift run iAnishFirewall
```

`swift run` starts the real firewall, so it will pause and ask about apps just like the installed app.

## Usage

### First launch

iAnish Firewall asks about **every app that already has an open connection** (browsers, Dropbox, chat apps and so on), one dialog at a time. Each app is paused until you answer, so expect a short burst of prompts the first time. After that you are only asked when a new app connects for the first time.

> Don't block the app that hosts your terminal or an AI assistant unless you mean to; it will be terminated.

### The menu bar menu

Click the shield icon:

| Item | What it does |
| --- | --- |
| *Firewall: active* | Status line (shows *demo mode* in demo mode). |
| **Settings…** | Opens the allowed/blocked apps window. |
| **History** | Opens the connection history window. |
| **About** | Shows the app name and version. |
| **Launch at Login** | Toggles starting the firewall when you log in. |
| **Quit** | Quits and resumes any paused apps. |

### Settings

- Two sections, **Allowed** and **Blocked**, each showing **5 apps per page** with previous/next arrows (*Page x of y*).
- Each row shows the app's icon, name and location, plus:
  - **Block** / **Unblock**: switch the app's rule immediately.
  - **Trash**: forget the app. It will be asked about again the next time it connects.

### History

- Shows the **latest 100 connections** from the **last 36 hours**, **10 rows per page** with previous/next arrows. Older entries are deleted automatically.
- Columns: **App** (with icon), **Type**, **Direction**, **Date & Time**, **Source**, **Destination**, **Result** (green *Allowed* / red *Blocked*).
- Click a column header to sort (newest first by default). Use the search box to filter by app, type, source, destination or result.
- **Right-click a row → Open App Location in Finder** reveals the app. The option is greyed out if the app is no longer at that path.
- **Source / Destination:**
  - IPv4 endpoints appear as `IP:port`.
  - For IPv6 destinations, the website host name is shown when a reverse-DNS lookup finds one (the lookup runs in the background, so a name may appear a moment after the row); otherwise the IPv6 address is shown.
  - An IPv6 source is shown as this Mac's host name and port.

### About

A small window with the app name and version number.

### Where data is stored

`~/Library/Application Support/iAnishFirewall/firewall.sqlite`

| Table | Contents |
| --- | --- |
| `rules` | App key (path of the `.app` or executable), name, action (allow/block), last updated. |
| `connections` | App, type, direction, timestamp, source, destination, result. |

Connections older than 36 hours are pruned when the app starts and after every 500 new records. You can inspect the file with any SQLite tool, for example `sqlite3 ~/Library/Application\ Support/iAnishFirewall/firewall.sqlite`.

## Project structure

```
macosfirewall/
├── build.sh                    # Builds build/iAnishFirewall.app (ad-hoc signed)
├── Package.swift               # Swift package manifest (swift build / swift run)
├── Resources/
│   └── App-Info.plist          # App bundle metadata (menu-bar-only app)
└── Sources/
    ├── App/
    │   ├── main.swift              # Entry point
    │   ├── AppDelegate.swift       # Menu bar item and menu
    │   ├── ConnectionMonitor.swift # Polling, pausing, blocking
    │   ├── SocketScanner.swift     # libproc socket enumeration
    │   ├── Backend.swift           # LocalBackend and DemoBackend
    │   ├── FirewallModel.swift     # Observable state, address display names
    │   ├── HostResolver.swift      # Cached reverse DNS
    │   ├── PromptCoordinator.swift # Allow/Block dialog (one at a time)
    │   ├── Views.swift             # Settings, History, About, pager
    │   └── WindowManager.swift     # Window lifecycle
    └── Shared/
        ├── Models.swift            # Rule, connection record, traffic type labels
        ├── Database.swift          # SQLite wrapper
        ├── RuleStore.swift         # In-memory rule cache
        └── AppIdentity.swift       # Process → app mapping
```

## Limitations

iAnish Firewall is a convenience and visibility tool for your own Mac, not a security boundary. Real per-app packet filtering on macOS requires a signed Network Extension, which needs a paid Apple Developer account. This project deliberately avoids that, with the trade-offs below.

### Detection

- **User-space monitoring, not a packet filter.** The app observes sockets; it does not sit in the network path.
- **Polling every 0.5 s.** A connection that opens and closes between two polls is never seen or logged, and an app may send a few packets before it is paused or terminated.
- **Loopback traffic (`127.x`, `::1`) is ignored.**
- **Only TCP and UDP over IPv4/IPv6 are tracked.** UDP sockets with no remote address (some DNS/mDNS traffic) are not seen.

### Blocking

- **Blocking terminates processes** (`SIGTERM`, then `SIGKILL`); it does not drop packets. Unsaved work in a blocked app can be lost.
- **Auto-restarting apps** are terminated again each time they connect.
- **Connections already open** when you block an app end only because the app is terminated; sockets are not closed individually.

### Visibility

- **Only your user's processes are visible.** Root-owned daemons and other users' processes cannot be seen.
- **Apple system components are exempt.** Anything under `/usr/libexec/`, `/usr/sbin/`, `/sbin/` or `/System/Library/` (for example Dock, Finder, `mDNSResponder`) is never paused, blocked or prompted for, since doing so could break macOS.
- **Apps that delegate networking to a system service**, notably **Safari** (WebKit Networking process), are attributed to that service, so Safari cannot be blocked reliably.
- **Rules are keyed by the app's path.** Moving or reinstalling an app at a different location makes it a new app.

### Other

- **Not notarized**, ad-hoc signed only.
- **Launch at Login** uses `SMAppService` and may not work for an unsigned build that isn't in `/Applications`.
- **Apps are frozen while a prompt is open.** An unanswered dialog leaves that app unresponsive.

## Troubleshooting

- **An app stays frozen after iAnish Firewall crashed.** Resume it from Terminal:
  ```bash
  killall -CONT "<process name>"
  ```
- **Reset all rules and history.** Quit the app and delete `~/Library/Application Support/iAnishFirewall`.
- **The menu bar icon is missing.** The menu bar may be full; quit other menu bar apps or hide some items.
- **An app I blocked keeps closing.** That is expected; see [Blocking](#blocking). Unblock it in **Settings**.
- **A browser or other app I allowed still isn't listed in History.** Its connections may be short-lived, owned by a system service, or made by a process of another user; see [Limitations](#limitations).

## Uninstall

1. Turn off **Launch at Login** in the menu.
2. Choose **Quit** from the menu.
3. Delete `iAnishFirewall.app`.
4. Delete `~/Library/Application Support/iAnishFirewall`.

## Contributing

Issues and pull requests are welcome. Please run `swift build` before submitting changes, and try your change in demo mode (`swift run iAnishFirewall --demo`) when it affects the UI.

## License

No license has been chosen yet. Add a `LICENSE` file before accepting outside contributions or redistributing.
