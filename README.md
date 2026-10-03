# mpv-AnimeVE

English | [简体中文](README.zh-CN.md)

A Windows video player for anime, with danmaku, optional AI upscaling and frame interpolation. Based on [mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai), [mpv.net](https://github.com/mpvnet-player/mpv.net) and [mpv](https://github.com/mpv-player/mpv).

[Download](https://github.com/sunuuc/mpv-AnimeVE/releases/latest) · [Report an issue](https://github.com/sunuuc/mpv-AnimeVE/issues)

## Features

- Local files, network streams and external playlists.
- Playback controls, chapter markers, audio tracks and two subtitle tracks.
- Online and local danmaku, parallel route search, type filters and blocked words.
- Optional AI upscaling and RIFE frame interpolation; models and GPU components download separately.
- A configuration manager with Chinese and English interfaces, hardware recommendations and downloads verified with SHA-256.

## Get started

1. Download the `mpv-AnimeVE-*-win-x64.7z` archive from Releases and extract it.
2. Run `AnimeVE.exe` and open a video.
3. For AI processing, open `AnimeVEManager.exe`, select the required models and GPU components in **Components**, then configure a processing profile.

Windows x64 is required. The portable package includes the application runtime; no separate .NET, Python or VapourSynth installation is needed. Normal playback is enabled by default. AI performance depends on the selected model and GPU.

NVIDIA GPUs use TensorRT components matched to the GPU generation. AMD and Intel GPUs can use the included DirectML backend. Install the graphics driver separately.

For online danmaku, add your routes under **Settings → Danmaku settings**. The release includes no personal routes or credentials. Local XML files can also be imported from the danmaku menu.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| Space | Play / pause |
| Left / Right | Seek backward / forward 5 seconds |
| Up / Down | Adjust volume |
| Double-click | Toggle fullscreen |
| Esc | Back / close menu / leave fullscreen |
| Tab | Toggle full mpv statistics |
| Ctrl+J | Show AI status and actual FPS |
| Ctrl+E | Open the configuration manager |
| Ctrl+1–9 | Select a configured AI profile |
| Ctrl+0 | Disable AI processing |

## Configuration

Player settings are in `portable_config`; AI profiles are in `animejanai/animejanai.conf`. Change the interface language in the manager's global settings, then restart the player and manager.

[Detailed usage](docs/standalone.md) · [Danmaku renderer](docs/danmaku-renderer.md)

## Build

Player and manager sources are in `src/player` and `src/manager`. Portable build tools are in `tools/standalone`. The [Windows build workflow](.github/workflows/standalone.yml) compiles, tests, scans and packages the release with pinned dependencies.

## Credits and licenses

Maintained by [sunuuc](https://github.com/sunuuc). Upstream authors and component licenses are listed in [source and third-party notices](docs/open-source-notices.md). Full license texts are included in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
