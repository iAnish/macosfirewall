# Scalene Firewall

A menu bar application firewall for macOS 14+ that runs entirely on your Mac. It needs no Apple Developer
account, no signing certificate and no system extension.

- The first time an app opens a network connection, a dialog asks **Allow** or **Block**. The answer is
  remembered for that app.
- The menu bar icon opens **Settings** (allowed/blocked apps, block/unblock), **History** (connections from the
  last 36 hours: app, type, direction, date/time, source, destination, result) and **About**.
- Rules and history are stored in SQLite at `~/Library/Application Support/ScaleneFirewall/firewall.sqlite`.

## Build and run

```bash
./build.sh
open build/ScaleneFirewall.app
```

The first launch asks about every app that already has a connection open (browsers, Dropbox, etc.).
Try the UI with sample data first, touching no real processes: `swift run ScaleneFirewall --demo`.

## How it works, and its limits

macOS only lets a signed Network Extension filter traffic in the kernel. Without one, this app works from user
space by polling the open sockets of your processes every 0.5 s (libproc):

- **Unknown app:** its processes are paused (SIGSTOP) while the dialog is up, then resumed on Allow.
- **Blocked app:** all its processes are terminated whenever one of them has a network connection. Unsaved work
  in a blocked app can be lost.
- **Not a packet filter:** a very short connection can finish between polls and be missed, and a blocked app
  may exchange a few packets before it is killed.
- **Visibility:** only processes owned by your user are visible. System daemons (root) are not shown, and
  Apple components under `/System/Library`, `/usr/libexec` etc. are never paused or blocked. Apple apps that
  delegate networking to a system service (Safari's WebKit networking process) are attributed to that service,
  so blocking Safari won't work.
- Loopback traffic is ignored. Connected UDP sockets (QUIC, etc.) are seen; unconnected UDP is not.

If the app crashes while an app is paused, resume it from Terminal: `killall -CONT <process name>`.
Don't block the app that hosts your terminal or this assistant unless you mean to.
