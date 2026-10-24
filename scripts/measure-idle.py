#!/usr/bin/env python3
"""Measure the built app with disposable synthetic archives, without recording.

macOS only; standard-library tooling, not an application dependency.
Reports the main process only. No ASR, model request or WebKit document is run.
CPU 100% means one fully occupied core. Memory values use MiB (2**20 bytes).
"""
import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import sqlite3
import statistics
import subprocess
import tempfile
import time


class Usage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in (
            "user_ticks", "system_ticks", "idle_wakeups", "interrupt_wakeups",
            "pageins", "wired", "resident", "footprint", "start", "exit",
            "child_user", "child_system", "child_idle_wakeups",
            "child_interrupt_wakeups", "child_pageins", "child_elapsed",
            "disk_read", "disk_write",
        )
    ]


libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
libproc.proc_pid_rusage.restype = ctypes.c_int


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


timebase = Timebase()
libsystem = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
if libsystem.mach_timebase_info(ctypes.byref(timebase)) != 0:
    raise RuntimeError("Cannot read the Mach clock timebase")
ns_per_tick = timebase.numer / timebase.denom


def usage(pid):
    value = Usage()
    if libproc.proc_pid_rusage(pid, 2, ctypes.byref(value)):
        raise OSError(ctypes.get_errno(), "proc_pid_rusage failed")
    return value


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def seed(directory, count):
    library = directory / "Library"
    library.mkdir(parents=True)
    if not count:
        return
    db = sqlite3.connect(library / "archive.sqlite")
    db.execute("""CREATE TABLE lectures (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, subject TEXT NOT NULL,
        file_path TEXT NOT NULL DEFAULT '', transcript TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '', duration REAL NOT NULL DEFAULT 0,
        created_at REAL NOT NULL, tags TEXT NOT NULL DEFAULT '',
        calendar_event_id TEXT NOT NULL DEFAULT '')""")
    transcript = ("Synthetic study material about eigenvalues and linear algebra. " * 50).strip()
    summary = "## Synthetic notes\nFor a diagonal matrix, coordinate directions are eigenvectors."
    db.executemany("INSERT INTO lectures VALUES (?, ?, ?, '', ?, ?, 1800, ?, ?, '')", [
        (f"benchmark-{i}", f"Synthetic class {i:04d}", "Mathematics", transcript,
         summary, 1792800000 + i, "benchmark, synthetic") for i in range(count)
    ])
    db.commit()
    db.close()


def measure(binary, count, run, warmup, seconds):
    with tempfile.TemporaryDirectory(prefix="askfor-benchmark-") as temp:
        directory = Path(temp)
        seed(directory, count)
        env = dict(os.environ, QIUSUO_DATA_DIRECTORY=str(directory))
        with (directory / "app.log").open("w") as log:
            process = subprocess.Popen([str(binary), "-AppleLanguages", "(en)"],
                                       env=env, stdout=log, stderr=log)
            try:
                time.sleep(warmup)
                if process.poll() is not None:
                    raise RuntimeError("App exited before sampling: " + (directory / "app.log").read_text())
                first = usage(process.pid)
                started = time.monotonic_ns()
                samples = []
                for _ in range(seconds):
                    time.sleep(1)
                    value = usage(process.pid)
                    samples.append({"elapsed_s": (time.monotonic_ns() - started) / 1e9,
                                    "footprint_bytes": value.footprint,
                                    "resident_bytes": value.resident})
                last = usage(process.pid)
                elapsed = (time.monotonic_ns() - started) / 1e9
                result = {
                    "archive_lectures": count, "run": run,
                    "elapsed_s": elapsed,
                    "mean_footprint_mib": statistics.mean(x["footprint_bytes"] for x in samples) / 2**20,
                    "max_sampled_footprint_mib": max(x["footprint_bytes"] for x in samples) / 2**20,
                    "mean_resident_mib": statistics.mean(x["resident_bytes"] for x in samples) / 2**20,
                    "cpu_ticks_delta": last.user_ticks + last.system_ticks - first.user_ticks - first.system_ticks,
                    "cpu_core_percent": ((last.user_ticks + last.system_ticks - first.user_ticks - first.system_ticks) * ns_per_tick / 1e9) / elapsed * 100,
                    "samples": samples,
                }
                print(json.dumps({k: v for k, v in result.items() if k != "samples"}), flush=True)
                return result
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path("dist/求索.app"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--seconds", type=int, default=20)
    parser.add_argument("--warmup", type=int, default=5)
    args = parser.parse_args()
    if min(args.runs, args.seconds, args.warmup) < 1:
        parser.error("runs, seconds and warmup must be positive")
    app = args.app.resolve()
    binary = app / "Contents/MacOS/求索"
    report = {
        "measured_at_utc": datetime.now(timezone.utc).isoformat(),
        "machine": command("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"),
        "memory_bytes": int(command("/usr/sbin/sysctl", "-n", "hw.memsize")),
        "macos": command("/usr/bin/sw_vers", "-productVersion"),
        "macos_build": command("/usr/bin/sw_vers", "-buildVersion"),
        "architecture": platform.machine(),
        "mach_timebase": {"numer": timebase.numer, "denom": timebase.denom},
        "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "app_bundle_bytes": sum(p.stat().st_size for p in app.rglob("*") if p.is_file()),
        "conditions": {"warmup_seconds": args.warmup, "sample_seconds": args.seconds,
                       "sample_interval_seconds": 1, "runs_per_scenario": args.runs,
                       "view": "Homework, window open, no interaction",
                       "scope": "main app process only", "speech_model_loaded": False,
                       "recording": False, "external_model_requests": False,
                       "web_document_rendering": False},
        "runs": [],
    }
    for count in [0, 1000]:
        for run in range(1, args.runs + 1):
            report["runs"].append(measure(binary, count, run, args.warmup, args.seconds))
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
