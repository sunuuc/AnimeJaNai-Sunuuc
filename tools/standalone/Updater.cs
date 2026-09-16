using System.Management;
using System.Text.Json;
using System.Security.Cryptography;

string root = AppContext.BaseDirectory;
string mode = args.FirstOrDefault()?.ToLowerInvariant() ?? "--components";
try
{
    if (mode == "--components")
    {
        string name = "Unknown";
        bool nvidia = false;
        try
        {
            using var query = new ManagementObjectSearcher("SELECT Name,PNPDeviceID FROM Win32_VideoController");
            using var found = query.Get();
            foreach (ManagementObject item in found)
            {
                using (item)
                {
                    string n = item["Name"]?.ToString() ?? "Unknown";
                    bool nv = (item["PNPDeviceID"]?.ToString() ?? "").Contains("VEN_10DE", StringComparison.OrdinalIgnoreCase);
                    if (name == "Unknown" || nv) name = n;
                    nvidia |= nv;
                }
            }
        }
        catch (ManagementException) { }
        catch (UnauthorizedAccessException) { }

        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "build-info", "standalone", "components.json")));
        var packs = new List<object>();
        foreach (var item in doc.RootElement.EnumerateArray())
        {
            string id = item.GetProperty("name").GetString()!;
            bool installed = true;
            long bytes = 0;
            foreach (var entry in item.GetProperty("files").EnumerateArray())
            {
                string relative = entry.GetProperty("path").GetString()!;
                string file = Path.GetFullPath(Path.Combine(root, relative));
                if (!file.StartsWith(Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Invalid component path");
                long size = entry.GetProperty("bytes").GetInt64();
                bytes += size;
                installed &= File.Exists(file) && new FileInfo(file).Length == size;
            }
            packs.Add(new { name = id, bytes, installed, recommended = id == "rife" || (nvidia && id == "trt-runtime"), preselect = installed });
        }
        Console.WriteLine(JsonSerializer.Serialize(new { gpu = new { name, nvidia }, packs, version_mismatch = (string?)null, distribution = "full-portable", offline = true }));
        return 0;
    }

    if (mode == "--verify")
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "build-info", "standalone", "SHA256.json")));
        var bad = new List<string>();
        foreach (var p in doc.RootElement.EnumerateObject())
        {
            if (p.Name.EndsWith(".conf", StringComparison.OrdinalIgnoreCase) || p.Name.EndsWith("interface-language.json", StringComparison.OrdinalIgnoreCase)) continue;
            string file = Path.GetFullPath(Path.Combine(root, p.Name));
            if (!file.StartsWith(Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Invalid manifest path");
            if (!File.Exists(file)) { bad.Add(p.Name); continue; }
            using var f = File.OpenRead(file);
            if (!Convert.ToHexString(SHA256.HashData(f)).Equals(p.Value.GetString(), StringComparison.OrdinalIgnoreCase)) bad.Add(p.Name);
        }
        Console.WriteLine(JsonSerializer.Serialize(new { ok = bad.Count == 0, failed = bad }));
        return bad.Count == 0 ? 0 : 1;
    }

    Console.Error.WriteLine("Unsupported command: " + mode);
    return 2;
}
catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException)
{
    Console.Error.WriteLine("Component check failed: " + e.Message);
    return 1;
}
