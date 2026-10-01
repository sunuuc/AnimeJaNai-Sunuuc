using System.Windows;

using MpvNet.Windows.WPF.Controls;
using MpvNet.Windows.UI;

namespace MpvNet.Windows.WPF;

public partial class DanmakuSourceEditWindow : Window
{
    public Theme? Theme => Theme.Current;
    public string SourceName => NameBox.Text.Trim();
    public string SourceUrl => UrlBox.Text.Trim();
    public event Action<string, string>? Confirmed;

    public DanmakuSourceEditWindow() => Initialize();

    public DanmakuSourceEditWindow(string name, string url)
    {
        Initialize();
        NameBox.Text = name;
        UrlBox.Text = url;
    }

    void Initialize()
    {
        InitializeComponent();
        DataContext = this;
    }

    void Window_Loaded(object sender, RoutedEventArgs e)
    {
        TextInputFocus.Focus(this, NameBox, selectAll: true);
    }

    void Confirm_Click(object sender, RoutedEventArgs e)
    {
        if (SourceName.Length == 0)
        {
            ShowStatus("请填写线路名称。");
            NameBox.Focus();
            return;
        }

        if (SourceUrl.Length == 0)
        {
            ShowStatus("请填写线路地址。");
            UrlBox.Focus();
            return;
        }

        Confirmed?.Invoke(SourceName, SourceUrl);
        Close();
    }

    void Cancel_Click(object sender, RoutedEventArgs e) => Close();

    void ShowStatus(string text)
    {
        Status.Text = text;
        Status.Visibility = Visibility.Visible;
    }
}
