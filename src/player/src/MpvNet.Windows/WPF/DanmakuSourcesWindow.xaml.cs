using System.Collections.ObjectModel;
using System.Text.Json;
using System.Windows;

using MpvNet.Windows.UI;

namespace MpvNet.Windows.WPF;

public partial class DanmakuSourcesWindow : Window
{
    DanmakuSourceEditWindow? _editWindow;

    public ObservableCollection<DanmakuSource> Sources { get; } = new();
    public Theme? Theme => Theme.Current;

    public DanmakuSourcesWindow(IList<string> args)
    {
        InitializeComponent();
        DataContext = this;

        for (int i = 0; i + 1 < args.Count && Sources.Count < 20; i += 2)
        {
            string name = args[i].Trim();
            string url = args[i + 1].Trim();
            if (url.Length == 0)
                continue;

            Sources.Add(new DanmakuSource(name.Length == 0 ? $"线路 {Sources.Count + 1}" : name, url));
        }

        RefreshPriority();
        if (Sources.Count > 0) SourceGrid.SelectedItem = Sources[0];
    }

    void RefreshPriority()
    {
        for (int i = 0; i < Sources.Count; i++) Sources[i].Priority = i + 1;
        SourceGrid.Items.Refresh();
    }

    DanmakuSource? SelectedSource => SourceGrid.SelectedItem as DanmakuSource;

    void MoveSource(int direction)
    {
        if (SelectedSource is not { } selected) return;
        int index = Sources.IndexOf(selected);
        int destination = index + direction;
        if (destination < 0 || destination >= Sources.Count) return;
        Sources.Move(index, destination);
        RefreshPriority();
        SourceGrid.SelectedItem = selected;
        SourceGrid.ScrollIntoView(selected);
    }

    void MoveUp_Click(object sender, RoutedEventArgs e) => MoveSource(-1);
    void MoveDown_Click(object sender, RoutedEventArgs e) => MoveSource(1);

    void Add_Click(object sender, RoutedEventArgs e)
    {
        if (Sources.Count >= 20)
        {
            ShowStatus("最多配置 20 条弹幕线路。");
            return;
        }

        EditSource();
    }

    void Edit_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedSource is not { } selected)
            return;

        EditSource(selected);
    }

    void EditSource(DanmakuSource? source = null)
    {
        if (_editWindow is { IsVisible: true })
        {
            _editWindow.Activate();
            return;
        }

        var window = source is null
            ? new DanmakuSourceEditWindow()
            : new DanmakuSourceEditWindow(source.Name, source.Url);
        window.Owner = this;
        _editWindow = window;
        window.Closed += (_, _) => _editWindow = null;
        window.Confirmed += (name, url) =>
        {
            ShowStatus("");
            if (source is null)
            {
                Sources.Add(new DanmakuSource(name, url));
                SourceGrid.SelectedItem = Sources[^1];
            }
            else if (Sources.Contains(source))
            {
                source.Name = name;
                source.Url = url;
                SourceGrid.Items.Refresh();
            }
            RefreshPriority();
        };
        System.Windows.Forms.Integration.ElementHost.EnableModelessKeyboardInterop(window);
        window.Show();
    }

    void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedSource is not { } selected)
            return;

        int removedIndex = Sources.IndexOf(selected);
        Sources.Remove(selected);
        RefreshPriority();
        if (Sources.Count > 0)
            SourceGrid.SelectedItem = Sources[Math.Min(removedIndex, Sources.Count - 1)];
    }

    void Save_Click(object sender, RoutedEventArgs e)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (DanmakuSource source in Sources)
        {
            string name = source.Name.Trim();
            string url = source.Url.Trim();
            bool validUri = Uri.TryCreate(url, UriKind.Absolute, out Uri? parsed)
                && (parsed.Scheme == Uri.UriSchemeHttp || parsed.Scheme == Uri.UriSchemeHttps)
                && string.IsNullOrEmpty(parsed.UserInfo);
            string normalized = url.TrimEnd('/');

            if (name.Length == 0 || name.Length > 80 || name.Contains(',')
                || url.Length == 0 || url.Length > 2048 || !validUri
                || url.Any(char.IsWhiteSpace) || url.Contains(',') || url.Contains('|')
                || url.Contains('?') || url.Contains('#') || seen.Contains(normalized))
            {
                ShowStatus("请检查线路名称和地址：名称最多 80 个字符；地址需为不含查询参数的 HTTP(S) 基础地址，且不能重复。");
                return;
            }

            source.Name = name;
            source.Url = normalized;
            seen.Add(normalized);
        }

        var payload = JsonSerializer.Serialize(new
        {
            servers = Sources.Select(source => new { name = source.Name, url = source.Url })
        });

        Player.CommandV("script-message", "player_ui-danmaku-save-servers", payload);
        Close();
    }

    void Cancel_Click(object sender, RoutedEventArgs e) => Close();

    void ShowStatus(string text)
    {
        Status.Text = text;
        Status.Visibility = text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
    }
}

public sealed class DanmakuSource
{
    public string Name { get; set; }
    public string Url { get; set; }
    public int Priority { get; set; }

    public DanmakuSource(string name, string url) => (Name, Url) = (name, url);
}
