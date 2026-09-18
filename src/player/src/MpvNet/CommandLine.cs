namespace MpvNet;

public class CommandLine
{
    static List<StringPair>? _arguments;
    static ScopedCommandLine? _parsed;
    public static ScopedCommandLine Parsed => _parsed ??=
        ScopedCommandLine.Parse(Environment.GetCommandLineArgs().Skip(1));

    public static List<StringPair> Arguments => _arguments ??=
        Parsed.GlobalOptions.Select(o =>
            new StringPair(ScopedCommandLine.CanonicalName(o.Name), o.Value)).ToList();

    public static void ProcessCommandLineArgsPreInit()
    {
        // Native startup options (including list operations) must be installed
        // before mpv_initialize. A later scripts-append does not start a script.
        foreach (var pair in Arguments)
        {
            if (IsLaunchOption(pair.Name)) continue;
            Player.ProcessProperty(pair.Name, pair.Value);
            if (App.ProcessProperty(pair.Name, pair.Value)) continue;
            int error = MpvNet.Native.LibMpv.mpv_set_option_string(Player.Handle,
                MpvNet.Native.LibMpv.GetUtf8Bytes(pair.Name), MpvNet.Native.LibMpv.GetUtf8Bytes(pair.Value));
            if (error < 0)
            {
                StartupDiagnostics.OptionError(error);
                // Option values may contain server credentials. Do not log them.
                throw new ArgumentException($"播放器不接受启动选项 --{pair.Name}（错误 {error}）。");
            }
        }
    }

    public static void ProcessCommandLineArgsPostInit()
    {
        // Do not replay options here: that restarts IPC listeners and can erase
        // work performed by an external script while the window initializes.
        StartupDiagnostics.Ready();
    }

    static bool IsLaunchOption(string name) => name is "playlist" or "playlist-start" or "shuffle";

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
