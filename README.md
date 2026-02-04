# Android CLI Tools

CLI helpers for Android development without Android Studio.

## Contents
- `foodroid`: ADB + Gradle + logcat automation
- `logq`: interactive log viewer (tail + filters + color)

## Assumptions
- Python 3.10+ is available.
- JDK 17 is installed for Android Gradle Plugin 8.x.
- Android SDK is installed and either:
  - `ANDROID_SDK_ROOT` or `ANDROID_HOME` is set, or
  - your project has `local.properties` with `sdk.dir=...`.
- `adb` is available in `$ANDROID_SDK_ROOT/platform-tools` or via `ADB=/path/to/adb`.
- Your Android project uses a standard `app/` module with `app/build.gradle.kts` (KTS) or `app/build.gradle` (Groovy).

## Project Selection
`foodroid` and `logq` target a project root using this order:
1. `--project /path/to/project`
2. `ANDROID_PROJECT_ROOT` or `DO_PROJECT_ROOT`
3. Current working directory (or a parent) containing `settings.gradle(.kts)` and `app/build.gradle(.kts)`

Per‑project state is stored in `<project>/.android-dev.json` (add it to your project `.gitignore`).
Log files default to `<project>/logs/`.


## Install
Use Make to install to a system prefix (default: `/usr/local/bin`).

```bash
sudo make install
# or to install to ~/.local/bin
make install PREFIX=$HOME/.local
```

To uninstall:
```bash
sudo make uninstall
```

## Usage
From your project root, or pass `--project` explicitly:

```bash
./foodroid doctor
./foodroid pair <ip:port> <code>
./foodroid connect <ip:port>
./foodroid device set <serial>
./foodroid install
./foodroid run
./foodroid logcat
./foodroid up
```

Logcat options:
```bash
./foodroid logcat --all
./foodroid logcat --crash
./foodroid logcat --out logs/session.txt
```

## Log Parser (logq)
`logq` tails a log file and provides interactive filtering with colorized levels.

Default behavior:
- Opens the newest file in `<project>/logs/`.
- Uses package filtering by default (based on your app id) when possible.
- Keeps the last 10,000 lines in memory.

Basic usage:
```bash
./logq --project /path/to/project
./logq /path/to/log.txt
```

Key bindings:
- `q` quit
- `space` pause/resume
- `p` toggle package filter
- `P` set package name
- `t` set tag filter
- `l` set level filter (e.g. W, E, I+, VDI)
- `/` set text filter
- `c` clear filters (keeps package)
- `C` clear all
- `?` help

## Notes
- `foodroid install` and `foodroid up` respect the configured device via `ANDROID_SERIAL`.
- `foodroid logcat` writes to a default timestamped file under `logs/` and opens `logq` for interactive viewing (falls back to raw stream if `logq` is missing).

## Dependencies
Install Python deps if needed:
```bash
pip install -r requirements.txt
```
