# mpv-AnimeVE

[简体中文](README.md) | English

A Windows anime player with AI upscaling, RIFE frame interpolation and online/local danmaku.

[Download](https://github.com/sunuuc/mpv-AnimeVE/releases/latest) · [Changelog](CHANGELOG.md) · [User guide](docs/standalone.md) · [Report an issue](https://github.com/sunuuc/mpv-AnimeVE/issues)

## Features

- **AI upscaling and interpolation**: multiple-model processing chains, adjustable RIFE interpolation and custom profiles with resolution/FPS conditions.
- **Optional downloads**: GPU detection, component recommendations and manual selection of models and GPU components. Models download separately.
- **Danmaku**: parallel route search and automatic fallback when an episode has no comments; local XML, speed, font size, opacity, display area, type filters and blocked words.
- **Playback and subtitles**: local files, network streams, playlists, resume positions, chapters, audio tracks and dual subtitles.
- **External playback**: integration with apps such as Hills Lite, including video URLs, playlists and episode selection.

## Installation

Requires 64-bit Windows.

1. Download `mpv-AnimeVE-*-win-x64.7z` from [Releases](https://github.com/sunuuc/mpv-AnimeVE/releases/latest) and extract it.
2. Run `AnimeVE.exe`, then open or drag in a video.
3. For AI processing, open `AnimeVEManager.exe`, download the required items under **Components**, then enable them under **Profiles**.

The package includes the application runtime. Separate .NET, Python and VapourSynth installations are not required.

## Usage

### Upscaling and interpolation

Choose recommended components or select them manually under **Components**, then click **Apply** to download. NVIDIA GPUs can use TensorRT; AMD and Intel GPUs can use DirectML. Select the backend and processing profile in the manager.

Under **Profiles**, choose upscaling models, interpolation settings and activation conditions, then set a default profile. TensorRT builds a local engine cache on first use.

### Danmaku

Add and sort routes under **Settings → Danmaku settings → Danmaku routes**. Matching runs automatically during playback; the bottom-bar danmaku menu also provides manual search and episode selection. Adjust speed, size, display area and filters under **Danmaku settings**.

Use **Import local danmaku** for local comments; an XML file with the same name as the video can load automatically. Use **Import local subtitles** in the subtitle menu for subtitles.

### External playback

Select `AnimeVE.exe` in Hills Lite's external player settings.

### Keyboard shortcuts

| Key | Action |
| --- | --- |
| Space | Play / pause |
| Left / Right | Seek backward / forward 5 seconds |
| Up / Down | Adjust volume |
| Double-click | Toggle fullscreen |
| Esc | Back in menus / leave fullscreen |
| Tab | Toggle full mpv statistics |
| Ctrl+E | Open the configuration manager |
| Ctrl+J | AI status and actual FPS |
| Ctrl+1–9 | Select a custom profile |
| Ctrl+0 | Disable AI processing |

## Documentation and credits

[Configuration](docs/standalone.md) · [Build guide](docs/build.md) · [Danmaku rendering](docs/danmaku-renderer.md) · [Sources and third-party licenses](docs/open-source-notices.md)

Based on [mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai), [mpv.net](https://github.com/mpvnet-player/mpv.net) and [mpv](https://github.com/mpv-player/mpv). Maintained by [sunuuc](https://github.com/sunuuc).
