using System.Text;

namespace MpvNet;

// Preserve mpv --{ ... --} scopes; never interpolate media into shell commands.
public sealed class ScopedCommandLine
{
    public sealed record Option(string Name, string Value);
    public sealed record Entry(string Path, List<Option> Options);
    public List<Option> GlobalOptions { get; } = [];
    public List<Entry> Entries { get; } = [];
    public bool HasGroups { get; private set; }
    public bool NeedsDedicatedProcess => HasGroups ||
        GlobalOptions.Any(o => o.Name is "input-ipc-server" or "sub-file" or "sub-files"
            or "force-media-title" or "start" or "audio-file" or "audio-files");

    static readonly HashSet<string> ValueOptions = new(StringComparer.Ordinal) {
        "sub-file", "sub-files", "audio-file", "audio-files", "external-file",
        "external-files", "force-media-title", "title", "start", "end", "length",
        "sid", "aid", "vid", "slang", "alang", "sub-delay", "audio-delay",
        "http-header-fields", "referrer", "user-agent", "input-ipc-server",
        "config-dir", "input-conf", "script", "scripts", "script-opt",
        "script-opts", "playlist-start", "profile", "log-file", "o"
    };

    public static ScopedCommandLine Parse(IEnumerable<string> arguments)
    {
        var result = new ScopedCommandLine();
        var args = arguments.ToArray();
        List<string>? groupFiles = null;
        List<Option>? groupOptions = null;
        bool literal = false;
        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i];
            if (arg.Contains('\0')) throw new ArgumentException("启动参数包含无效字符。");
            if (!literal && arg == "--{")
            {
                if (groupFiles != null) throw new ArgumentException("不支持嵌套的 --{ 参数组。");
                result.HasGroups = true;
                groupFiles = []; groupOptions = [];
                continue;
            }
            if (!literal && arg == "--}")
            {
                if (groupFiles == null) throw new ArgumentException("--} 没有对应的 --{。");
                foreach (var path in groupFiles)
                    result.Entries.Add(new Entry(path, new List<Option>(groupOptions!)));
                groupFiles = null; groupOptions = null;
                continue;
            }
            if (!literal && arg == "--") { literal = true; continue; }
            if (!literal && arg.StartsWith("--", StringComparison.Ordinal))
            {
                string body = arg[2..];
                int eq = body.IndexOf('=');
                string name = eq < 0 ? body : body[..eq];
                string value;
                if (eq >= 0) value = body[(eq + 1)..];
                else if (name.StartsWith("no-", StringComparison.Ordinal))
                { name = name[3..]; value = "no"; }
                else if (ValueOptions.Contains(name))
                {
                    if (i + 1 >= args.Length || args[i + 1].StartsWith("--", StringComparison.Ordinal))
                        throw new ArgumentException($"选项 --{name} 缺少值；请使用 --{name}=值。");
                    value = args[++i];
                }
                else value = "yes";
                if (value.Contains('\0')) throw new ArgumentException("启动参数包含无效字符。");
                if (name.Length == 0) throw new ArgumentException("空的启动选项名称。");
                (groupOptions ?? result.GlobalOptions).Add(new Option(name, value));
            }
            else if (!string.IsNullOrEmpty(arg))
            {
                if (!literal && arg.StartsWith("-", StringComparison.Ordinal) && arg != "-")
                    throw new ArgumentException("不支持短格式启动选项；请使用 --选项=值，或先用 -- 结束选项。");
                if (groupFiles != null) groupFiles.Add(arg);
                else result.Entries.Add(new Entry(arg, []));
            }
        }
        if (groupFiles != null) throw new ArgumentException("--{ 参数组未以 --} 结束。");
        return result;
    }

    public static string CanonicalName(string name) => name switch {
        "script" => "scripts-append", "script-opt" => "script-opts-append",
        "sub-file" => "sub-files-append", "audio-file" => "audio-files-append",
        "external-file" => "external-files-append", _ => name
    };

    // mpv key/value lists require UTF-8 BYTE lengths, not UTF-16 character lengths.
    public static string Quote(string value) => $"%{Encoding.UTF8.GetByteCount(value)}%{value}";

    public static string FileOptions(IEnumerable<Option> options)
    {
        var normalized = new List<Option>();
        foreach (var raw in options)
        {
            string name = CanonicalName(raw.Name);
            // Fold repeated singular subtitles into one Windows path-list add;
            // otherwise mpv's option map keeps only the last identical key.
            bool fileAppend = name is "sub-files-append" or "audio-files-append" or "external-files-append";
            if (fileAppend)
            {
                name = name[..^7] + "-add";
                string item = raw.Value.Replace(";", "\\;", StringComparison.Ordinal);
                int n = normalized.FindLastIndex(o => o.Name == name);
                if (n >= 0)
                {
                    var old = normalized[n];
                    normalized[n] = new Option(name, old.Value + ";" + item);
                }
                else normalized.Add(new Option(name, item));
            }
            else
            {
                if (name is "sub-files" or "audio-files" or "external-files")
                    normalized.RemoveAll(o => o.Name == name + "-add");
                normalized.RemoveAll(o => o.Name == name);
                normalized.Add(new Option(name, raw.Value));
            }
        }
        return string.Join(",", normalized.Select(o => Quote(o.Name) + "=" + Quote(o.Value)));
    }
}
