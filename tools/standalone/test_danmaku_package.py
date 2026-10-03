"""Check the packaged converter, search flow and native subtitle composition without a desktop."""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def verify(app, evidence):
    app = app.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({
        'ANIMEJANAI_INSTALL': str(app),
        'ANIMEJANAI_MPV_EXE': str(app / 'app/mpv.exe'),
        'DANMAKU_FACTORY': str(app / 'animejanai/danmaku/DanmakuFactory.exe'),
        'ANIMEJANAI_LIBASS': str(app / 'app/libass-9.dll'),
        'ANIMEJANAI_PLAYER_CONFIG': str(app / 'portable_config/mpv.conf'),
        'ANIMEJANAI_DANMAKU_SCRIPT': str(app / 'portable_config/scripts/player_ui_danmaku.lua'),
        'ANIMEJANAI_PLAYER_UI_SCRIPT': str(app / 'portable_config/scripts/player_ui.lua'),
        'PYTHONUTF8': '1',
    })
    results = []
    for name in ('test_danmaku_canvas', 'test_mpv_danmaku_viewport', 'test_danmaku_native', 'test_danmaku_flow'):
        result = subprocess.run([sys.executable, str(ROOT / 'tests' / (name + '.py'))],
                                env=env, capture_output=True, timeout=240)
        (evidence / (name + '.log')).write_bytes(result.stdout + result.stderr)
        results.append({'case': name, 'passed': result.returncode == 0})
        (evidence / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
        if result.returncode:
            raise RuntimeError(name + ' failed:\n' + (result.stdout + result.stderr).decode('utf-8', errors='replace'))
        print('PASS packaged danmaku:', name, flush=True)


if __name__ == '__main__':
    verify(Path(sys.argv[1]), Path(sys.argv[2]))
