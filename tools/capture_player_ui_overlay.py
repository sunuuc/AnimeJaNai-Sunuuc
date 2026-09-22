"""Capture the Player UI overlay as it is actually rendered.

Serves a clip over loopback HTTP so the source counts as network media (which
is what makes the read-rate line appear), launches the real player with the
production config, waits for playback, then screenshots the window both with
the bar shown and after it auto-hides.

The point is to look at the produced pixels instead of inferring the geometry
from the source, because the last two attempts at this layout were signed off
on an inference that turned out wrong.

Usage:
    python tools/capture_player_ui_overlay.py --out DIR [--geometry WxH]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = (HERE / ".." / "mpvapp").resolve()

FRAME = b"FRAME\n" + b"\xe0" * (160 * 90) + b"\x80" * (160 * 90 // 2)
# ~45 s at 24 fps: long enough that it is still streaming, not fully cached.
MEDIA = b"YUV4MPEG2 W160 H90 F24:1 Ip A1:1 C420jpeg\n" + FRAME * (24 * 45)


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
                time.sleep(0.002)
        except OSError:
            pass


class Player:
    def __init__(self, app: Path, args, geometry: str):
        self.pipe = r"\\.\pipe\player_ui-overlay-" + uuid.uuid4().hex
        flags = [
            "--config-dir=" + str(app / "portable_config"),
            "--process-instance=multi",
            "--input-ipc-server=" + self.pipe,
            "--vo=gpu",
            "--gpu-api=d3d11",
            "--gpu-context=d3d11",
            "--d3d11-warp=yes",
            "--hwdec=no",
            "--vf=",
            "--ao=null",
            "--idle=yes",
            "--keep-open=yes",
            "--save-position-on-quit=no",
            "--resume-playback=no",
            "--geometry=" + geometry,
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
        deadline = time.time() + 8
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
    ap.add_argument("--app", default=str(APP))
    ap.add_argument("--out", required=True)
    ap.add_argument("--geometry", default="1280x720")
    args = ap.parse_args()

    app = Path(args.app).resolve()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}"
    uri = base + "/media/overlay.y4m"

    player = None
    results = {}
    try:
        player = Player(app, [uri], args.geometry)
        # Wait for real playback.
        deadline = time.time() + 30
        while time.time() < deadline:
            if (player.command("get_property", "time-pos") or 0) > 0.5:
                break
            time.sleep(0.2)

        results["geometry"] = player.command("get_property", "geometry")
        results["width"] = player.command("get_property", "width")
        results["height"] = player.command("get_property", "height")
        results["hidpi"] = player.command(
            "get_property", "display-hidpi-scale"
        )
        results["demuxer_via_network"] = player.command(
            "get_property", "demuxer-via-network"
        )
        results["media_title"] = player.command("get_property", "media-title")
        results["osd_playing_msg"] = player.command(
            "get_property", "osd-playing-msg"
        )
        results["osd_align_x"] = player.command("get_property", "osd-align-x")
        results["osd_align_y"] = player.command("get_property", "osd-align-y")
        results["osd_margin_y"] = player.command("get_property", "osd-margin-y")
        results["osd_font_size"] = player.command("get_property", "osd-font-size")

        # 1) Bar visible: nudge the mouse so the bar shows.
        player.command("script-message", "player_ui-show")
        time.sleep(0.8)
        player.command("screenshot-to-file", str(out / "bar-visible.png"), "window")
        time.sleep(0.3)

        # 2) Bar hidden: hide, then wait past hide_timeout (2.5 s).
        player.command("script-message", "player_ui-hide")
        time.sleep(4.0)
        player.command("screenshot-to-file", str(out / "bar-hidden.png"), "window")
        ui = player.command("get_property", "user-data/player_ui/ui")
        results["player_ui_ui_after_hide"] = ui

        # 3) Where does mpv itself put an OSD message? (default alignment)
        player.command("show-text", "OSD-PROBE-MARKER", "3000")
        time.sleep(0.4)
        player.command("screenshot-to-file", str(out / "osd-marker.png"), "window")

        # 4) A popover must ride the same lift as the bar, otherwise it stays at
        #    the old height and covers the buttons it belongs to.
        player.command("script-message", "player_ui-show")
        time.sleep(0.4)
        player.command("script-message", "player_ui-menu", "settings")
        time.sleep(1.0)
        player.command("screenshot-to-file", str(out / "menu-open.png"), "window")
        results["menu_boxes"] = (player.command(
            "get_property", "user-data/player_ui/ui") or {}).get("menu_boxes")

        print(json.dumps(results, ensure_ascii=False, indent=2, default=str))
        (out / "probe.json").write_text(
            json.dumps(results, ensure_ascii=False, indent=2, default=str),
            encoding="utf-8",
        )
        return 0
    finally:
        if player:
            player.close()
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
