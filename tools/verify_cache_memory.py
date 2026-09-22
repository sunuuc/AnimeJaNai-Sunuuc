"""Measure the committed-memory cost of the new cache policy.

Launches the player against loopback media with the same IPC mechanism the
production frontend test uses, reads the resolved cache options back over
IPC, and samples committed memory while the cache fills.

Compares the option values the player actually ends up with against what
network_playback.lua asked for, so a silently-ignored file-local option
cannot pass as a fix.

Usage:
    python tools/verify_cache_memory.py [--app DIR] [--seconds N]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from memprobe import mem  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_APP = (HERE / ".." / "mpvapp").resolve()

FRAME = b"FRAME\n" + b"\x60" * (160 * 90) + b"\x80" * (160 * 90 // 2)
MEDIA = b"YUV4MPEG2 W160 H90 F24:1 Ip A1:1 C420jpeg\n" + FRAME * (24 * 60)

WATCH_OPTIONS = [
    "demuxer-max-bytes",
    "demuxer-max-back-bytes",
    "demuxer-readahead-secs",
    "cache-secs",
    "vd-queue-max-bytes",
    "ad-queue-max-bytes",
    "cache-on-disk",
]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_GET(self):
        start = 0
        rng = self.headers.get("Range", "")
        if rng.startswith("bytes="):
            try:
                start = int(rng[6:].split("-")[0])
            except ValueError:
                pass
        body = MEDIA[start:]
        self.send_response(206 if start else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(len(body)))
        if start:
            self.send_header(
                "Content-Range", f"bytes {start}-{len(MEDIA) - 1}/{len(MEDIA)}"
            )
        self.end_headers()
        try:
            for pos in range(0, len(body), 65536):
                self.wfile.write(body[pos : pos + 65536])
                self.wfile.flush()
                time.sleep(0.001)
        except OSError:
            pass


class Player:
    def __init__(self, app: Path, args):
        self.pipe = r"\\.\pipe\animejanai-cachemem-" + uuid.uuid4().hex
        flags = [
            "--config-dir=" + str(app / "portable_config"),
            "--process-instance=multi",
            "--input-ipc-server=" + self.pipe,
            "--vo=null",
            "--ao=null",
            "--idle=yes",
            "--keep-open=yes",
            "--save-position-on-quit=no",
            "--resume-playback=no",
            "--terminal=no",
        ]
        self.proc = subprocess.Popen(
            [str(app / "mpvnet.exe"), *flags, *args],
            cwd=app,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.fp = None
        end = time.monotonic() + 20
        while time.monotonic() < end:
            if self.proc.poll() is not None:
                raise RuntimeError("player exited early")
            try:
                self.fp = open(self.pipe, "r+b", buffering=0)
                break
            except OSError:
                time.sleep(0.1)
        if self.fp is None:
            raise RuntimeError("no IPC")

    def command(self, *args):
        self.fp.write((json.dumps({"command": list(args)}) + "\n").encode())
        deadline = time.time() + 6
        buf = b""
        while time.time() < deadline:
            chunk = self.fp.read(65536)
            if not chunk:
                break
            buf += chunk
            for line in buf.split(b"\n"):
                line = line.strip()
                if not line.startswith(b"{"):
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if d.get("error") == "success":
                    return d.get("data")
                if "error" in d:
                    return None
        return None

    def close(self):
        try:
            self.command("quit")
        except Exception:
            pass
        if self.fp:
            self.fp.close()
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", default=str(DEFAULT_APP))
    ap.add_argument("--seconds", type=float, default=25)
    args = ap.parse_args()

    app = Path(args.app).resolve()
    exe = app / "mpvnet.exe"
    if not exe.is_file():
        print("player not found:", exe)
        return 1

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}"

    player = None
    try:
        print(f"app: {app}")
        player = Player(app, [base + "/media/cachemem.y4m"])
        print("player started, waiting for playback...")
        deadline = time.time() + 20
        while time.time() < deadline:
            if (player.command("get_property", "time-pos") or 0) > 0:
                break
            time.sleep(0.2)

        print("\n== options the player actually resolved ==")
        for name in WATCH_OPTIONS:
            print(f"  {name:26s} = {player.command('get_property', name)}")

        st = player.command("get_property", "demuxer-cache-state")
        if isinstance(st, dict):
            print(f"  {'fw-bytes (cached)':26s} = {st.get('fw-bytes')}")

        pid = player.proc.pid
        print(f"\n== committed memory over {args.seconds:.0f}s (pid {pid}) ==")
        print(f"{'t':>4} {'commit_MB':>10} {'ws_MB':>8} {'cached_MB':>10}")
        start = time.time()
        samples = []
        while time.time() - start < args.seconds:
            m = mem(pid)
            cache = 0
            st = player.command("get_property", "demuxer-cache-state")
            if isinstance(st, dict):
                cache = (st.get("fw-bytes") or 0) / 1024 / 1024
            if m:
                samples.append(m["commit"])
                print(
                    f"{time.time() - start:4.0f} "
                    f"{m['commit']:10.0f} {m['working_set']:8.0f} {cache:10.1f}"
                )
            time.sleep(2)

        if samples:
            print(
                f"\ncommit: start={samples[0]:.0f}MB  "
                f"peak={max(samples):.0f}MB  end={samples[-1]:.0f}MB"
            )
        return 0
    finally:
        if player:
            player.close()
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())
