using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.Json;
namespace AnimeJaNai.Localization;
// Only UI preference lives here; never touch AI profiles, model names or mpv.conf.
public static class InterfaceLanguage
{
    public static string SettingsPath { get; set; } = Path.Combine(AppContext.BaseDirectory,"portable_config","interface-language.json");
    public static readonly string[] Choices = { "zh-CN", "en", "system" };
    public static string Selection { get; private set; } = Read();
    public static string Effective => Resolve(Selection, CultureInfo.CurrentUICulture.Name);
    public static bool IsChinese => Effective == "zh-CN";
    public static string PlayerValue => IsChinese ? "chinese-china" : "english";
    public static string Resolve(string value, string systemCulture) => value == "system"
        ? (systemCulture.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "zh-CN" : "en")
        : value == "en" ? "en" : "zh-CN";
    public static string Read()
    {
        try {
            using var doc = JsonDocument.Parse(File.ReadAllText(SettingsPath));
            string? value = doc.RootElement.GetProperty("language").GetString();
            return Array.IndexOf(Choices, value) >= 0 ? value! : "zh-CN";
        } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException
            or InvalidOperationException or KeyNotFoundException) { return "zh-CN"; }
    }
    public static void Reload() => Selection = Read();
    // Keep the current UI consistent; apply the new preference at next startup.
    public static void Save(string value)
    {
        if (Array.IndexOf(Choices, value) < 0) throw new ArgumentException("Unsupported language");
        string file = Path.GetFullPath(SettingsPath);
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        string pending = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            File.WriteAllText(pending, JsonSerializer.Serialize(new { language = value }), new UTF8Encoding(false));
            File.Move(pending, file, overwrite: true);
        } finally { if (File.Exists(pending)) File.Delete(pending); }
    }
}
