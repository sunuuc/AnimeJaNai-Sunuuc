# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AnimeJaNaiConfEditor is a Windows desktop GUI for configuring AnimeJaNai, an AI-powered anime video upscaling tool. It manages upscaling profiles, processing chains, and AI model settings that get written to an INI-style config file consumed by mpv/AnimeJaNai.

## Build Commands

```bash
dotnet build                     # Debug build
dotnet build -c Release          # Release build
dotnet publish -c Release        # Publish self-contained win-x64 executable
```

No test suite or linter is configured.

## Architecture

**Framework:** Avalonia UI (.NET 10.0) with ReactiveUI (MVVM pattern).

**Data model hierarchy:** `AnimeJaNaiConf` → `UpscaleSlot[]` → `UpscaleChain[]` → `UpscaleModel[]`. All nested in `MainWindowViewModel.cs`, which is the central file (~1400 lines) containing both the ViewModel and all model classes.

**Auto-save:** Model properties use `RaiseAndSetIfChanged` and subscribe via Rx to trigger `WriteAnimeJaNaiConf()` on any change. Modifying model properties automatically persists to the config file.

**View binding:** `ViewLocator.cs` maps ViewModels to Views by convention (replacing "ViewModel" suffix with "View"). Currently there is only one view: `MainWindow`.

**Config persistence:** Uses `Salaros.ConfigParser` to read/write `animejanai.conf` in INI format. Sections are `[global]` and `[slot_N]`, with chain/model properties using `chain_N_model_N_` key prefixes.

**Player settings:** Some `[global]` keys configure mpv rather than the inference engine — `default_slot` and `sub_render_mode` (the GPU subtitle toggle). The engine ignores them; `portable_config/scripts/animejanai_backend.lua` in the mpv-upscale-2x_animejanai package reads them at startup. The mpv options themselves live in a managed profile (`[subs-gpu]` in `mpv-animejanai.conf`), so the settings can change with the player build without a Manager release. This app never writes `mpv.conf`.

**Relative paths from executable:** The app resolves paths relative to its own location — `./animejanai.conf`, `./onnx/`, `./backups/`, and `../portable_config/mpv.conf` for mpv integration.

## Key Conventions

- Decimal formatting uses `CultureInfo.InvariantCulture` to handle non-English Windows locales
- Default profiles are read-only; custom profiles (slots 4+) are editable
- Backup system auto-creates up to 10 backups in `./backups/`, deduplicating by content
- Pre-packaged ONNX neural network models live in `./onnx/`
