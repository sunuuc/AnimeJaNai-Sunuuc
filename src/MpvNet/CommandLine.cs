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
        foreach (var pair in Arguments)
        {
            if (pair.Name.EndsWith("-add") || pair.Name.EndsWith("-set") ||
                pair.Name.EndsWith("-pre") || pair.Name.EndsWith("-clr") ||
                pair.Name.EndsWith("-append") || pair.Name.EndsWith("-remove") ||
                pair.Name.EndsWith("-toggle")) continue;
            Player.ProcessProperty(pair.Name, pair.Value);
            if (!App.ProcessProperty(pair.Name, pair.Value))
                Player.SetPropertyString(pair.Name, pair.Value);
        }
    }

    public static void ProcessCommandLineArgsPostInit()
    {
        foreach (var pair in Arguments)
        {
            if (_preInitProperties.Contains(pair.Name)) continue;
            if (pair.Name.EndsWith("-add"))
                Player.CommandV("change-list", pair.Name[..^4], "add", pair.Value);
            else if (pair.Name.EndsWith("-set"))
                Player.CommandV("change-list", pair.Name[..^4], "set", pair.Value);
            else if (pair.Name.EndsWith("-append"))
                Player.CommandV("change-list", pair.Name[..^7], "append", pair.Value);
            else if (pair.Name.EndsWith("-pre"))
                Player.CommandV("change-list", pair.Name[..^4], "pre", pair.Value);
            else if (pair.Name.EndsWith("-clr"))
                Player.CommandV("change-list", pair.Name[..^4], "clr", "");
            else if (pair.Name.EndsWith("-remove"))
                Player.CommandV("change-list", pair.Name[..^7], "remove", pair.Value);
            else if (pair.Name.EndsWith("-toggle"))
                Player.CommandV("change-list", pair.Name[..^7], "toggle", pair.Value);
            else
            {
                Player.ProcessProperty(pair.Name, pair.Value);
                if (!App.ProcessProperty(pair.Name, pair.Value))
                    Player.SetPropertyString(pair.Name, pair.Value);
            }
        }
    }

    public static void ProcessCommandLineFiles()
    {
        if (!Parsed.HasGroups)
            Player.LoadFiles(Parsed.Entries.Select(e => e.Path).ToArray(), !App.Queue, App.Queue);
        else
        {
            // Keep scoped external playlists out of the one-second append
            // heuristic and extension-based global subtitle attachment.
            for (int i = 0; i < Parsed.Entries.Count; i++)
            {
                var entry = Parsed.Entries[i];
                string mode = i == 0 && !App.Queue ? "replace" : "append";
                Player.CommandV("loadfile", MainPlayer.ConvertFilePath(entry.Path), mode,
                    "-1", ScopedCommandLine.FileOptions(entry.Options));
            }
            if (int.TryParse(GetValue("playlist-start"), out int start) &&
                start >= 0 && start < Parsed.Entries.Count && !App.Queue)
                Player.SetPropertyInt("playlist-pos", start);
        }
        if (App.CommandLine.Contains("--shuffle"))
        {
            Player.Command("playlist-shuffle");
            Player.SetPropertyInt("playlist-pos", 0);
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
