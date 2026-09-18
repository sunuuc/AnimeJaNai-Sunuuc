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

    public static List<StringPair> Arguments => _arguments ??= BuildArguments();

    static List<StringPair> BuildArguments()
    {
        var result = new List<StringPair>();
        bool scriptsAssigned = false;
        bool scriptOptionsAssigned = false;

        foreach (var raw in Parsed.GlobalOptions)
        {
            string name;
            if (Parsed.LegacyScriptHandoff && raw.Name == "script")
                name = scriptsAssigned ? "scripts-append" : "scripts";
            else if (Parsed.LegacyScriptHandoff && raw.Name == "script-opt")
                name = scriptOptionsAssigned ? "script-opts-append" : "script-opts";
            else
                name = ScopedCommandLine.CanonicalName(raw.Name);

            result.Add(new StringPair(name, raw.Value));

            string baseName = ScopedCommandLine.BaseName(name);
            bool destructiveOnly = name.EndsWith("-remove", StringComparison.Ordinal) ||
                                   name.EndsWith("-toggle", StringComparison.Ordinal);
            if (!destructiveOnly && baseName == "scripts") scriptsAssigned = true;
            if (!destructiveOnly && baseName == "script-opts") scriptOptionsAssigned = true;
        }

        return result;
    }

    static void SetStartupOption(string name, string value)
    {
        int error = MpvNet.Native.LibMpv.mpv_set_option_string(Player.Handle,
            MpvNet.Native.LibMpv.GetUtf8Bytes(name), MpvNet.Native.LibMpv.GetUtf8Bytes(value));
        if (error < 0)
        {
            StartupDiagnostics.OptionError(error);
            // Values may contain media-server credentials; never include them.
            throw new ArgumentException($"播放器不接受启动选项 --{name}（错误 {error}）。");
        }
    }

    public static void ProcessCommandLineArgsPreInit()
    {
        // The startup script may issue loadfile during mpv_initialize. Therefore
        // caller options such as --vf=, --hwdec and authentication fields must be
        // native mpv options before scripts start, not late runtime properties.
        foreach (var pair in Arguments)
        {
            if (IsLaunchOption(pair.Name) || IsStartupList(pair.Name) || IsListOperation(pair.Name))
                continue;

            Player.ProcessProperty(pair.Name, pair.Value);
            if (!App.ProcessProperty(pair.Name, pair.Value))
                SetStartupOption(pair.Name, pair.Value);
        }

        if (TryBuildStartupList("script-opts", ',', out string scriptOptions))
            SetStartupOption("script-opts", scriptOptions);

        if (TryBuildStartupList("scripts", Path.PathSeparator, out string scripts))
            SetStartupOption("scripts", scripts);
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
                // Reapply mutable properties after initialization so saved
                // frontend state cannot override explicit caller values.
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
