using System.Text.Json;

namespace MpvNet;

// Event-driven local diagnostics. Never records argument values, URLs, titles,
// authentication headers or machine paths, and never contacts a media server.
public static class StartupDiagnostics
{
    static readonly object Sync = new();
    static readonly List<string> Phases = [];
    static bool nativeReady;
    static bool sawFile;
    static int? optionError;

    public static void Begin()
    {
        Player.Initialized += () => { nativeReady = true; Record("native-initialized"); };
        Player.StartFile += () => Record("media-opening");
        Player.FileLoaded += () => { sawFile = true; Record("media-loaded"); };
        Record("process-started");
    }

    public static void Ready()
    {
        Record("external-handoff-ready");
        if (MissingScripts() > 0)
            Player.CommandV("show-text", "外部启动脚本不存在，请检查调用方保存的播放器路径。", "8000");
    }

    public static void OptionError(int error) { optionError = error; Record("option-rejected"); }
    public static void Failed() => Record("startup-failed");

    static int MissingScripts()
    {
        int missing = 0;
        foreach (var option in CommandLine.Parsed.GlobalOptions)
        {
            // A singular --script is one filename, not a semicolon-delimited list.
            if (option.Name != "script") continue;
            string path = option.Value;
            if (path.Contains("://") || path.StartsWith("\\\\") || path.StartsWith("//")) continue;
            if (path.StartsWith("~~/")) path = Path.Combine(Player.ConfigFolder, path[3..]);
            if (path.StartsWith("~")) continue;
            if (!File.Exists(path) && !Directory.Exists(path)) missing++;
        }
        return missing;
    }

    static void Record(string phase)
    {
        lock (Sync)
        {
            try
            {
                Phases.Add(phase);
                if (Phases.Count > 24) Phases.RemoveAt(0);
                ScopedCommandLine? parsed;
                try { parsed = CommandLine.Parsed; } catch { parsed = null; }
                var options = parsed?.GlobalOptions ?? [];
                var playlistStarts = options.Where(o => o.Name == "playlist-start").ToList();
                string? rawStart = playlistStarts.LastOrDefault()?.Value;
                int? startIndex = int.TryParse(rawStart, out int selected) ? selected : null;
                string startKind = rawStart == null ? "none"
                    : startIndex.HasValue ? "index"
                    : rawStart is "auto" or "no" ? "auto" : "other";
                string configuration = options.Any(o => o.Name == "config-dir") ? "explicit"
                    : Directory.Exists(Environment.GetEnvironmentVariable("MPVNET_HOME")) ? "environment"
                    : Directory.Exists(Path.Combine(Folder.Startup, "portable_config")) ? "portable" : "appdata";
                var data = new
                {
                    version = 3,
                    phases = Phases.ToArray(),
                    argument_count = Environment.GetCommandLineArgs().Length - 1,
                    media_arguments = parsed?.Entries.Count,
                    scoped_playlist = parsed?.HasGroups,
                    empty_scope_count = parsed?.EmptyGroupCount,
                    empty_scope_options_promoted = parsed?.EmptyGroupOptionsPromoted,
                    promoted_option_names = parsed?.PromotedOptions.Select(o => o.Name)
                        .Distinct(StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal).ToArray(),
                    legacy_script_handoff = parsed?.LegacyScriptHandoff,
                    global_option_count = options.Count,
                    playlist_option = options.Any(o => o.Name == "playlist"),
                    playlist_option_count = options.Count(o => o.Name == "playlist"),
                    playlist_start_option_count = playlistStarts.Count,
                    playlist_start_kind = startKind,
                    playlist_start_index = startIndex,
                    native_playlist_handoff = options.Any(o => o.Name == "playlist"),
                    script_options = options.Count(o => ScopedCommandLine.BaseName(ScopedCommandLine.CanonicalName(o.Name)) == "scripts"),
                    script_payload_options = options.Count(o => ScopedCommandLine.BaseName(ScopedCommandLine.CanonicalName(o.Name)) == "script-opts"),
                    missing_scripts = parsed == null ? (int?)null : MissingScripts(),
                    ipc_requested = options.Any(o => o.Name is "input-ipc-server" or "input-ipc-client"),
                    configuration,
                    native_initialized = nativeReady,
                    has_media = nativeReady && Player.GetPropertyString("path").Length > 0,
                    playlist_count = nativeReady ? Player.GetPropertyInt("playlist-count") : 0,
                    playlist_current_pos = nativeReady ? Player.GetPropertyInt("playlist-pos") : -1,
                    file_loaded = sawFile,
                    option_error = optionError
                };
                string folder = Path.Combine(Folder.Startup, "portable_config");
                if (!Directory.Exists(folder)) folder = Player.ConfigFolder;
                string path = Path.Combine(folder, "startup-diagnostic.json");
                string json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(path + ".tmp", json);
                File.Move(path + ".tmp", path, true);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            catch (ArgumentException) { }
        }
    }
}
