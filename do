#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path


TOOL_ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = None
LOG_DIR = None
CONFIG_PATH = None


def resolve_project_root(cli_value=None):
    if cli_value:
        return Path(cli_value).expanduser().resolve()
    for key in ("ANDROID_PROJECT_ROOT", "DO_PROJECT_ROOT"):
        value = os.environ.get(key)
        if value:
            return Path(value).expanduser().resolve()
    cwd = Path.cwd()
    markers = [
        ("settings.gradle.kts", "app/build.gradle.kts"),
        ("settings.gradle", "app/build.gradle"),
    ]
    for base in [cwd] + list(cwd.parents):
        for settings, appbuild in markers:
            if (base / settings).exists() and (base / appbuild).exists():
                return base
    return cwd


def set_project_root(cli_value=None):
    global PROJECT_ROOT, LOG_DIR, CONFIG_PATH
    PROJECT_ROOT = resolve_project_root(cli_value)
    LOG_DIR = PROJECT_ROOT / "logs"
    CONFIG_PATH = PROJECT_ROOT / ".android-dev.json"


def project_root():
    if PROJECT_ROOT is None:
        set_project_root(None)
    return PROJECT_ROOT


def config_path():
    if CONFIG_PATH is None:
        set_project_root(None)
    return CONFIG_PATH


def log_dir():
    if LOG_DIR is None:
        set_project_root(None)
    return LOG_DIR


def eprint(*args):
    print(*args, file=sys.stderr)


def load_config():
    path = config_path()
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        eprint(f"Invalid JSON in {path}")
        return {}


def save_config(cfg):
    config_path().write_text(json.dumps(cfg, indent=2, sort_keys=True) + "\n")


def read_sdk_dir():
    for key in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        value = os.environ.get(key)
        if value:
            return value
    local_props = project_root() / "local.properties"
    if local_props.exists():
        for line in local_props.read_text().splitlines():
            if line.startswith("sdk.dir="):
                return line.split("=", 1)[1].strip()
    return None


def adb_path():
    env_adb = os.environ.get("ADB")
    if env_adb:
        return env_adb
    sdk = read_sdk_dir()
    if sdk:
        candidate = Path(sdk) / "platform-tools" / "adb"
        if candidate.exists():
            return str(candidate)
    return "adb"


def adb_cmd(args, cfg=None, serial=None):
    cmd = [adb_path()]
    use_serial = serial if serial else (cfg.get("device_serial") if cfg else None)
    if use_serial:
        cmd += ["-s", use_serial]
    cmd += args
    return cmd


def run(
    cmd,
    check=True,
    capture=False,
    text=True,
    input_text=None,
    cwd=None,
    env=None,
    stdout=None,
    stderr=None,
):
    if capture:
        return subprocess.run(
            cmd,
            check=check,
            text=text,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd,
            env=env,
        )
    return subprocess.run(
        cmd,
        check=check,
        text=text,
        input=input_text,
        cwd=cwd,
        env=env,
        stdout=stdout,
        stderr=stderr,
    )


def stream(cmd, out_path=None, env=None, cwd=None):
    out_file = None
    if out_path:
        out_path = Path(out_path)
        if not out_path.is_absolute():
            out_path = project_root() / out_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_file = out_path.open("a", encoding="utf-8")
        print(f"Streaming logcat to {out_path} (and terminal). Ctrl-C to stop.")

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        cwd=cwd,
        env=env,
    )
    try:
        for line in proc.stdout:
            if out_file:
                out_file.write(line)
                out_file.flush()
            print(line, end="")
    except KeyboardInterrupt:
        proc.terminate()
    finally:
        if out_file:
            out_file.close()
        proc.wait()


def app_id():
    root = project_root()
    build_file = root / "app" / "build.gradle.kts"
    if build_file.exists():
        text = build_file.read_text()
        match = re.search(r'^\s*applicationId\s*=\s*"([^"]+)"', text, re.M)
        return match.group(1) if match else None
    build_file = root / "app" / "build.gradle"
    if build_file.exists():
        text = build_file.read_text()
        match = re.search(r'^\s*applicationId\s+\"([^\"]+)\"', text, re.M)
        return match.group(1) if match else None
    eprint("Missing app/build.gradle.kts or app/build.gradle")
    return None


def gradle_install_task(variant):
    if not variant:
        return "installDebug"
    if variant.lower().startswith("install"):
        return variant
    return "install" + variant[0].upper() + variant[1:]


def list_devices():
    result = run(adb_cmd(["devices", "-l"]), capture=True, check=False)
    print(result.stdout.strip())
    if result.stderr.strip():
        eprint(result.stderr.strip())
    return result.stdout


def parse_connected_devices(devices_output):
    lines = devices_output.splitlines()[1:]
    devices = []
    for line in lines:
        parts = line.strip().split()
        if len(parts) < 2:
            continue
        serial, status = parts[0], parts[1]
        if status == "device":
            devices.append(serial)
    return devices


def parse_connected_device_lines(devices_output):
    lines = devices_output.splitlines()[1:]
    devices = []
    for line in lines:
        parts = line.strip().split()
        if len(parts) < 2:
            continue
        serial, status = parts[0], parts[1]
        if status == "device":
            devices.append((serial, line.strip()))
    return devices


def device_serial_from_config(cfg):
    return cfg.get("device_serial")


def choose_device(devices):
    if not devices:
        return None
    if len(devices) == 1:
        return devices[0][0]
    print("Multiple devices connected:")
    for idx, (serial, line) in enumerate(devices, start=1):
        print(f"  {idx}. {serial} ({line})")
    while True:
        choice = input("Select device number: ").strip()
        if not choice:
            return None
        if choice.isdigit():
            idx = int(choice)
            if 1 <= idx <= len(devices):
                return devices[idx - 1][0]
        print("Invalid selection.")


def ensure_device(cfg):
    out = list_devices()
    devices = parse_connected_device_lines(out)
    configured = device_serial_from_config(cfg)
    if configured and any(serial == configured for serial, _ in devices):
        return configured

    selected = choose_device(devices)
    if selected:
        cfg["device_serial"] = selected
        if ":" in selected:
            cfg["device_host"] = selected
        save_config(cfg)
        return selected

    host = cfg.get("device_host")
    if host:
        result = run(adb_cmd(["connect", host], cfg=None), capture=True, check=False)
        if result.stdout.strip():
            print(result.stdout.strip())
        if result.stderr.strip():
            eprint(result.stderr.strip())
        out = list_devices()
        devices = parse_connected_device_lines(out)
        selected = choose_device(devices)
        if selected:
            cfg["device_serial"] = selected
            if ":" in selected:
                cfg["device_host"] = selected
            save_config(cfg)
            return selected

    print("No connected devices. You can pair or connect now.")
    pairing_host = input("Pairing ip:port (leave blank to skip): ").strip()
    if pairing_host:
        code = input("Pairing code: ").strip()
        pair_result = run(adb_cmd(["pair", pairing_host, code], cfg=None), capture=True, check=False)
        if pair_result.stdout.strip():
            print(pair_result.stdout.strip())
        if pair_result.stderr.strip():
            eprint(pair_result.stderr.strip())

    connect_host = input("Connect ip:port (from main Wireless debugging screen): ").strip()
    if not connect_host:
        eprint("No connect host provided.")
        return None

    connect_result = run(adb_cmd(["connect", connect_host], cfg=None), capture=True, check=False)
    if connect_result.stdout.strip():
        print(connect_result.stdout.strip())
    if connect_result.stderr.strip():
        eprint(connect_result.stderr.strip())

    out = list_devices()
    devices = parse_connected_device_lines(out)
    selected = choose_device(devices)
    if selected:
        cfg["device_serial"] = selected
        cfg["device_host"] = connect_host
        save_config(cfg)
        return selected
    return None


def command_doctor(_args):
    cfg = load_config()
    print("Android SDK:", read_sdk_dir() or "not set")
    print("ADB:", adb_path())
    java = subprocess.run(["java", "-version"], capture_output=True, text=True)
    if java.returncode == 0:
        print("Java:", (java.stderr or java.stdout).strip().splitlines()[0])
    else:
        eprint("Java: not available")
    if device_serial_from_config(cfg):
        print("Configured device:", device_serial_from_config(cfg))
    else:
        print("Configured device: none")
    print()
    list_devices()


def command_pair(args):
    cfg = load_config()
    host = args.host
    code = args.code
    if code:
        pair_result = run(adb_cmd(["pair", host, code], cfg=None), capture=True, check=False)
    else:
        pair_result = run(adb_cmd(["pair", host], cfg=None), capture=True, check=False)

    if pair_result.stdout.strip():
        print(pair_result.stdout.strip())
    if pair_result.stderr.strip():
        eprint(pair_result.stderr.strip())

    if pair_result.returncode != 0:
        eprint("Pairing reported a non-zero exit code. Attempting to connect anyway...")

    connect_result = run(adb_cmd(["connect", host], cfg=None), capture=True, check=False)
    if connect_result.stdout.strip():
        print(connect_result.stdout.strip())
    if connect_result.stderr.strip():
        eprint(connect_result.stderr.strip())

    if "connected to" in connect_result.stdout or "already connected" in connect_result.stdout:
        cfg["device_host"] = host
        cfg["device_serial"] = host
        save_config(cfg)
        print(f"Connected to {host}")
        return 0

    eprint("Connect failed. Check IP/port and pairing code, then retry.")
    return 1


def command_connect(args):
    cfg = load_config()
    host = args.host or cfg.get("device_host")
    if not host:
        eprint("Missing host. Provide <ip:port> or set device_host in config.")
        return 1
    result = run(adb_cmd(["connect", host], cfg=None), capture=True, check=False)
    if result.stdout.strip():
        print(result.stdout.strip())
    if result.stderr.strip():
        eprint(result.stderr.strip())

    if "connected to" in result.stdout or "already connected" in result.stdout:
        cfg["device_host"] = host
        cfg["device_serial"] = host
        save_config(cfg)
        print(f"Connected to {host}")
        return 0

    eprint("Connect failed. Check IP/port and phone prompt, then retry.")
    return 1


def command_devices(_args):
    cfg = load_config()
    out = list_devices()
    serial = device_serial_from_config(cfg)
    if serial:
        print(f"\nConfigured device: {serial}")
    devices = parse_connected_devices(out)
    if devices:
        print("Connected devices:", ", ".join(devices))


def command_device_set(args):
    cfg = load_config()
    cfg["device_serial"] = args.serial
    if ":" in args.serial:
        cfg["device_host"] = args.serial
    save_config(cfg)
    print(f"Device set to {args.serial}")


def command_device_auto(_args):
    cfg = load_config()
    out = list_devices()
    devices = parse_connected_devices(out)
    if len(devices) == 1:
        cfg["device_serial"] = devices[0]
        if ":" in devices[0]:
            cfg["device_host"] = devices[0]
        save_config(cfg)
        print(f"Device set to {devices[0]}")
        return 0
    if len(devices) == 0:
        eprint("No connected devices.")
        return 1
    eprint("Multiple devices connected. Use: do device set <serial>")
    return 1


def command_device_clear(_args):
    cfg = load_config()
    cfg.pop("device_serial", None)
    cfg.pop("device_host", None)
    save_config(cfg)
    print("Cleared device configuration")


def command_install(args):
    task = gradle_install_task(args.variant)
    cfg = load_config()
    env = os.environ.copy()
    serial = cfg.get("device_serial")
    if serial:
        env["ANDROID_SERIAL"] = serial
    run(["./gradlew", task], cwd=project_root(), env=env)


def command_run(_args):
    pkg = app_id()
    if not pkg:
        eprint("applicationId not found in app/build.gradle.kts")
        return 1
    cfg = load_config()
    run(adb_cmd(["shell", "monkey", "-p", pkg, "-c", "android.intent.category.LAUNCHER", "1"], cfg=cfg))
    return 0


def command_logcat(args):
    cfg = load_config()
    mode = None
    if hasattr(args, "logcat"):
        mode = args.logcat
    else:
        if getattr(args, "all", False):
            mode = "all"
        elif getattr(args, "crash", False):
            mode = "crash"
        else:
            mode = "app"

    out_path = getattr(args, "out", None)
    if not out_path:
        ts = time.strftime("%Y%m%d-%H%M%S")
        out_path = log_dir() / f"logcat-{ts}.txt"
    logq_path = TOOL_ROOT / "logq"

    if mode == "crash":
        logcat_cmd = adb_cmd(["logcat", "-b", "crash", "--format", args.format], cfg=cfg)
    else:
        logcat_cmd = adb_cmd(["logcat", "--format", args.format], cfg=cfg)

    if logq_path.exists():
        out_path = Path(out_path)
        if not out_path.is_absolute():
            out_path = project_root() / out_path
        out_path.parent.mkdir(parents=True, exist_ok=True)

        out_file = out_path.open("a", encoding="utf-8")
        proc = subprocess.Popen(logcat_cmd, stdout=out_file, stderr=subprocess.STDOUT, text=True)
        try:
            logq_cmd = [str(logq_path), str(out_path), "--project", str(project_root())]
            if mode in ("all", "crash"):
                logq_cmd.append("--no-package")
            run(logq_cmd, check=False)
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
            out_file.close()
        return 0

    if mode == "all":
        stream(logcat_cmd, out_path=out_path)
        return 0
    if mode == "crash":
        stream(logcat_cmd, out_path=out_path)
        return 0

    stream(logcat_cmd, out_path=out_path)
    return 0


def command_clear(_args):
    cfg = load_config()
    run(adb_cmd(["logcat", "-c"], cfg=cfg))


def command_status(_args):
    cfg = load_config()
    print("Tool:", TOOL_ROOT)
    print("Project:", project_root())
    print("Config file:", config_path())
    print("Android SDK:", read_sdk_dir() or "not set")
    print("ADB:", adb_path())
    print("App ID:", app_id() or "not found")
    print("Device serial:", cfg.get("device_serial") or "none")
    print("Device host:", cfg.get("device_host") or "none")


def command_up(args):
    cfg = load_config()
    if not ensure_device(cfg):
        return 1

    task = gradle_install_task(args.variant)
    run(["./gradlew", task], cwd=project_root())

    if command_run(args) != 0:
        return 1

    time.sleep(1)
    return command_logcat(args)


def build_parser():
    parser = argparse.ArgumentParser(prog="do")
    parser.add_argument(
        "--project",
        help="path to Android project root (defaults to cwd or ANDROID_PROJECT_ROOT)",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("doctor")

    pair = sub.add_parser("pair")
    pair.add_argument("host", help="ip:port from Wireless debugging pairing screen")
    pair.add_argument("code", nargs="?", help="pairing code (optional)")

    connect = sub.add_parser("connect")
    connect.add_argument("host", nargs="?", help="ip:port")

    sub.add_parser("devices")

    device = sub.add_parser("device")
    device_sub = device.add_subparsers(dest="device_cmd", required=True)
    device_set = device_sub.add_parser("set")
    device_set.add_argument("serial")
    device_sub.add_parser("auto")
    device_sub.add_parser("clear")

    install = sub.add_parser("install")
    install.add_argument("variant", nargs="?", help="debug/release or full task name")

    sub.add_parser("run")

    logcat = sub.add_parser("logcat")
    logcat.add_argument("--all", action="store_true", help="show full logcat")
    logcat.add_argument("--crash", action="store_true", help="show crash buffer")
    logcat.add_argument("--format", default="threadtime", help="logcat format")
    logcat.add_argument("--out", help="write logcat to file")

    sub.add_parser("clear")
    sub.add_parser("status")

    up = sub.add_parser("up")
    up.add_argument("variant", nargs="?", help="debug/release or full task name")
    up.add_argument(
        "--logcat",
        choices=["app", "all", "crash"],
        default="app",
        help="logcat mode after launch",
    )
    up.add_argument("--format", default="threadtime", help="logcat format")
    up.add_argument("--out", help="write logcat to file")

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    set_project_root(getattr(args, "project", None))

    if args.cmd == "doctor":
        return command_doctor(args)
    if args.cmd == "pair":
        return command_pair(args)
    if args.cmd == "connect":
        return command_connect(args)
    if args.cmd == "devices":
        return command_devices(args)
    if args.cmd == "device":
        if args.device_cmd == "set":
            return command_device_set(args)
        if args.device_cmd == "auto":
            return command_device_auto(args)
        if args.device_cmd == "clear":
            return command_device_clear(args)
    if args.cmd == "install":
        return command_install(args)
    if args.cmd == "run":
        return command_run(args)
    if args.cmd == "logcat":
        return command_logcat(args)
    if args.cmd == "clear":
        return command_clear(args)
    if args.cmd == "status":
        return command_status(args)
    if args.cmd == "up":
        return command_up(args)
    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
