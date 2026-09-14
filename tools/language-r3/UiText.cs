using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using System.Text.Json;
namespace AnimeJaNai.Localization;
public static class UiText
{
    private static readonly Dictionary<string,string> Chinese;
    private static readonly Dictionary<string,string> English = new(StringComparer.Ordinal);
    private static readonly Dictionary<string,string> Keys;
    static UiText()
    {
        // Embedded resource: a binary-only copier cannot omit the translations.
        using var stream = typeof(UiText).Assembly.GetManifestResourceStream("AnimeJaNai.LanguageStrings.json")
            ?? throw new InvalidOperationException("Missing embedded UI language resources");
        using var doc = JsonDocument.Parse(stream);
        Chinese = JsonSerializer.Deserialize<Dictionary<string,string>>(doc.RootElement.GetProperty("translations"))!;
        Keys = JsonSerializer.Deserialize<Dictionary<string,string>>(doc.RootElement.GetProperty("keys"))!;
        foreach (var item in Chinese) English.TryAdd(item.Value, item.Key);
    }
    public static string T(string? text)
    {
        if (string.IsNullOrEmpty(text)) return text ?? "";
        if (InterfaceLanguage.IsChinese && Chinese.TryGetValue(text, out var exact)) return exact;
        if (!InterfaceLanguage.IsChinese && English.TryGetValue(text, out var original)) return original;
        string core = text.Trim();
        var map = InterfaceLanguage.IsChinese ? Chinese : English;
        if (!map.TryGetValue(core, out var translated)) return text;
        int start = text.IndexOf(core, StringComparison.Ordinal);
        return text[..start] + translated + text[(start + core.Length)..];
    }
    public static string Key(string key) => T(Keys[key]);
    public static string F(FormattableString value) => string.Format(CultureInfo.CurrentCulture,T(value.Format),value.GetArguments());
}
