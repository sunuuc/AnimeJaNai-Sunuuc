namespace MpvNet;

public class CommandLine
{
    static List<StringPair>? _arguments;
    static ScopedCommandLine? _parsed;
    public static ScopedCommandLine Parsed => _parsed ??=
        ScopedCommandLine.Parse(Environment.GetCommandLineArgs().Skip(1));

    static string[] _preInitProperties { get; } = {
        "input-terminal", "terminal", "input-file", "config", "o", "config-dir", "input-conf",
        "load-scripts", "scripts", "script-opts", "player-operation-mode", "idle", "log-file",
        "msg-color", "dump-stats", "msg-level", "really-quiet" };

    public static List<StringPair> Arguments => _arguments ??=
        Parsed.GlobalOptions.Select(o =>
            new StringPair(ScopedCommandLine.CanonicalName(o.Name), o.Value)).ToList();

    public static void ProcessCommandLineArgsPreInit()
    {
        // Ordinary options can be set on the pre-initialized mpv handle. List
        // mutations are commands, not libmpv option names, so most of them must
        // wait until after initialization. Scripts are the exception: they must
        // be assembled into their base options before mpv_initialize or they
        // will never start.
        foreach (var pair in Arguments)
        {
            if (IsLaunchOption(pair.Name) || IsStartupList(pair.Name) || IsListOperation(pair.Name))
                continue;

            Player.ProcessProperty(pair.Name, pair.Value);
            if (!App.ProcessProperty(pair.Name, pair.Value))
                Player.SetPropertyString(pair.Name, pair.Value);
        }

        if (TryBuildStartupList("script-opts", ',', out string scriptOptions))
            Player.SetPropertyString("script-opts", scriptOptions);

        if (TryBuildStartupList("scripts", Path.PathSeparator, out string scripts))
            Player.SetPropertyString("scripts", scripts);
    }

    public static void ProcessCommandLineArgsPostInit()
    {
        foreach (var pair in Arguments)
        {
            if (IsLaunchOption(pair.Name) || IsStartupList(pair.Name))
                continue;

            if (pair.Name.EndsWith("-add", StringComparison.Ordinal))
                Player.CommandV("change-list", pair.Name[..^4], "add", pair.Value);
            else if (pair.Name.EndsWith("-set", StringComparison.Ordinal))
                Player.CommandV("change-list", pair.Name[..^4], "set", pair.Value);
            else if (pair.Name.EndsWith("-append", StringComparison.Ordinal))
                Player.CommandV("change-list", pair.Name[..^7], "append", pair.Value);
            else if (pair.Name.EndsWith("-pre", StringComparison.Ordinal))
                Player.CommandV("change-list", pair.Name[..^4], "pre", pair.Value);
            else if (pair.Name.EndsWith("-clr", StringComparison.Ordinal))
                Player.CommandV("change-list", pair.Name[..^4], "clr", "");
            else if (pair.Name.EndsWith("-remove", StringComparison.Ordinal))
                Player.CommandV("change-list", pair.Name[..^7], "remove", pair.Value);
            else if (pair.Name.EndsWith("-toggle", StringComparison.Ordinal))
                Player.CommandV("change-list", pair.Name[..^7], "toggle", pair.Value);
            else if (!_preInitProperties.Contains(pair.Name))
            {
                // Runtime properties such as volume and media title are applied
                // once more after initialization so caller values win over saved
                // frontend settings, while IPC and scripts are never restarted.
                Player.ProcessProperty(pair.Name, pair.Value);
                if (!App.ProcessProperty(pair.Name, pair.Value))
                    Player.SetPropertyString(pair.Name, pair.Value);
            }
        }

        StartupDiagnostics.Ready();
    }

    static bool IsLaunchOption(string name) => name is "playlist" or "playlist-start" or "shuffle";

    static bool IsListOperation(string name) =>
        name.EndsWith("-add", StringComparison.Ordinal) ||
        name.EndsWith("-set", StringComparison.Ordinal) ||
        name.EndsWith("-pre", StringComparison.Ordinal) ||
        name.EndsWith("-clr", StringComparison.Ordinal) ||
        name.EndsWith("-append", StringComparison.Ordinal) ||
        name.EndsWith("-remove", StringComparison.Ordinal) ||
        name.EndsWith("-toggle", StringComparison.Ordinal);

    static bool IsStartupList(string name) =>
        ScopedCommandLine.BaseName(name) is "scripts" or "script-opts";

    static string EscapeListItem(string value, char separator) =>
        value.Replace(separator.ToString(), "\\" + separator, StringComparison.Ordinal);

    static bool TryBuildStartupList(string baseName, char separator, out string value)
    {
        bool seen = false;
        value = "";

        foreach (var pair in Arguments)
        {
            if (ScopedCommandLine.BaseName(pair.Name) != baseName)
                continue;

            seen = true;
            if (pair.Name == baseName || pair.Name.EndsWith("-set", StringComparison.Ordinal))
            {
                value = pair.Value;
            }
            else if (pair.Name.EndsWith("-clr", StringComparison.Ordinal))
            {
                value = "";
            }
            else if (pair.Name.EndsWith("-append", StringComparison.Ordinal) ||
                     pair.Name.EndsWith("-add", StringComparison.Ordinal))
            {
                string item = EscapeListItem(pair.Value, separator);
                value = value.Length == 0 ? item : value + separator + item;
            }
            else if (pair.Name.EndsWith("-pre", StringComparison.Ordinal))
            {
                string item = EscapeListItem(pair.Value, separator);
                value = value.Length == 0 ? item : item + separator + value;
            }
            else
            {
                // Removing or toggling startup scripts after they have already
                // been selected is ambiguous before mpv initializes. Refuse the
                // request rather than silently starting the wrong script.
                throw new ArgumentException($"启动阶段不支持列表操作 --{pair.Name}。");
            }
        }

        return seen;
    }

    public static void ProcessCommandLineFiles()
    {
        bool shuffle = GetValue("shuffle") == "yes";
        string playlist = GetValue("playlist");
        if (!Parsed.HasGroups && playlist.Length == 0 && !Contains("playlist-start") && !shuffle)
        {
            Player.LoadFiles(Parsed.Entries.Select(e => e.Path).ToArray(), !App.Queue, App.Queue);
            return;
        }
        if (Parsed.Entries.Count == 0 && playlist.Length == 0) return;

        // Assemble while stopped: no temporary request to the first episode.
        bool keepPlaying = App.Queue && Player.GetPropertyInt("playlist-count") > 0
            && Player.GetPropertyInt("playlist-pos") >= 0;
        if (!App.Queue)
        {
            Player.CommandV("stop");
            Player.CommandV("playlist-clear");
        }
        int offset = Player.GetPropertyInt("playlist-count");
        if (playlist.Length > 0)
            Player.CommandV("loadlist", MainPlayer.ConvertFilePath(playlist), "append");
        foreach (var entry in Parsed.Entries)
            Player.CommandV("loadfile", MainPlayer.ConvertFilePath(entry.Path), "append",
                "-1", ScopedCommandLine.FileOptions(entry.Options));

        if (shuffle) Player.CommandV("playlist-shuffle");
        int count = Player.GetPropertyInt("playlist-count");
        if (!keepPlaying && count > offset)
        {
            int start = int.TryParse(GetValue("playlist-start"), out int selected) ? selected : 0;
            start = Math.Clamp(start, 0, count - offset - 1);
            Player.SetPropertyInt("playlist-pos", shuffle ? 0 : offset + start);
        }
    }

    public static bool Contains(string name) => Arguments.Any(p => p.Name == name);
    public static string GetValue(string name)
    {
        for (int i=Arguments.Count-1; i>=0; i--)
            if (Arguments[i].Name == name) return Arguments[i].Value;
        return "";
    }
}
