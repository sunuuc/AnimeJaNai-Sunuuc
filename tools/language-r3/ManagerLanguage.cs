using System;
using System.Globalization;
using Avalonia.Controls;
using Avalonia.Data.Converters;
using Avalonia.Layout;
using AnimeJaNai.Localization;
namespace AnimeJaNaiConfEditor;
public sealed class TextExtension
{
    public string Key { get; set; } = "";
    public string ProvideValue(IServiceProvider provider) => UiText.Key(Key);
}
public sealed class LocalizedFormatConverter : IValueConverter
{
    public static readonly LocalizedFormatConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) => string.Format(culture,UiText.Key((string)parameter!),value);
    public object? ConvertBack(object? value, Type t, object? p, CultureInfo c) => null;
}
public sealed class LocalizedTextConverter : IValueConverter
{
    public static readonly LocalizedTextConverter Instance = new();
    public object Convert(object? value, Type t, object? p, CultureInfo c) => UiText.T(value?.ToString());
    public object? ConvertBack(object? value, Type t, object? p, CultureInfo c) => null;
}
public static class LanguagePanel
{
    public static void Attach(Window window)
    {
        var original=(Control)window.Content!;window.Content=null;
        var hint=new TextBlock {Text=UiText.T("Language changes take effect after restarting both applications."),TextWrapping=Avalonia.Media.TextWrapping.Wrap,FontSize=12,Opacity=0.75};
        var select=new ComboBox {Name="InterfaceLanguageSelector",Width=215,ItemsSource=new[]{"简体中文","English","跟随系统 / System"},SelectedIndex=Array.IndexOf(InterfaceLanguage.Choices,InterfaceLanguage.Read())};
        select.SelectionChanged+=(_,_)=>{
            if(select.SelectedIndex<0)return;
            try {InterfaceLanguage.Save(InterfaceLanguage.Choices[select.SelectedIndex]);hint.Text=UiText.T("Saved. Restart the player and manager to apply the language.");}
            catch(Exception e){hint.Text=UiText.T("Could not save language: ")+e.Message;}
        };
        var top=new StackPanel {Margin=new Avalonia.Thickness(14,8),Spacing=5};
        var row=new StackPanel {Orientation=Orientation.Horizontal,Spacing=12};
        row.Children.Add(new TextBlock {Text="界面语言 / Interface language",VerticalAlignment=VerticalAlignment.Center});
        row.Children.Add(select);top.Children.Add(row);top.Children.Add(hint);
        var root=new DockPanel();DockPanel.SetDock(top,Dock.Top);root.Children.Add(top);root.Children.Add(original);window.Content=root;
    }
}
