# Android CLI Tools

CLI helpers for Android development without Android Studio. Currently includes `do` for ADB + Gradle + logcat automation.

## Assumptions
- Python 3.10+ is available.
- JDK 17 is installed for Android Gradle Plugin 8.x.
- Android SDK is installed and either:
  - `ANDROID_SDK_ROOT` or `ANDROID_HOME` is set, or
  - your project has `local.properties` with `sdk.dir=...`.
- `adb` is available in `$ANDROID_SDK_ROOT/platform-tools` or via `ADB=/path/to/adb`.
- Your Android project uses a standard `app/` module with `app/build.gradle.kts` (KTS) or `app/build.gradle` (Groovy).

## Project Selection
`do` targets a project root using this order:
1. `--project /path/to/project`
2. `ANDROID_PROJECT_ROOT` or `DO_PROJECT_ROOT`
3. Current working directory (or a parent) containing `settings.gradle(.kts)` and `app/build.gradle(.kts)`

Per‑project state is stored in `<project>/.android-dev.json` (add it to your project `.gitignore`).
Log files default to `<project>/logs/`.

## Usage
From your project root, or pass `--project` explicitly:

```bash
/home/foo/workspace/android-cli-tools/do doctor
/home/foo/workspace/android-cli-tools/do pair <ip:port> <code>
/home/foo/workspace/android-cli-tools/do connect <ip:port>
/home/foo/workspace/android-cli-tools/do device set <serial>
/home/foo/workspace/android-cli-tools/do install
/home/foo/workspace/android-cli-tools/do run
/home/foo/workspace/android-cli-tools/do logcat
/home/foo/workspace/android-cli-tools/do up
```

Logcat options:
```bash
/home/foo/workspace/android-cli-tools/do logcat --all
/home/foo/workspace/android-cli-tools/do logcat --crash
/home/foo/workspace/android-cli-tools/do logcat --out logs/session.txt
```


## Log Parser (logq)
`logq` tails a log file and provides interactive filtering with colorized levels.

Default behavior:
- Opens the newest file in `<project>/logs/`.
- Uses package filtering by default (based on your app id) when possible.
- Keeps the last 10,000 lines in memory.

Basic usage:
```bash
/home/foo/workspace/android-cli-tools/logq --project /path/to/project
/home/foo/workspace/android-cli-tools/logq /path/to/log.txt
```

Key bindings:
- `q` quit
- `space` pause/resume
- `p` toggle package filter
- `P` set package name
- `t` set tag filter
- `l` set level filter (e.g. W, E, I+, VDI)
- `/` set text filter
- `c` clear filters
- `?` help


## Notes
- `do install` and `do up` respect the configured device via `ANDROID_SERIAL`.
- `do logcat` writes to a default timestamped file under `logs/` and opens `logq` for interactive viewing (falls back to raw stream if `logq` is missing).

## Dependencies
Install Python deps if needed:
```bash
pip install -r requirements.txt
```
