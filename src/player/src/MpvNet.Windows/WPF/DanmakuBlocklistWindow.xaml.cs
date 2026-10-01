using System.Text;
using System.Windows;

using MpvNet.Windows.WPF.Controls;
using MpvNet.Windows.UI;

namespace MpvNet.Windows.WPF;

public partial class DanmakuBlocklistWindow : Window
{
    public Theme? Theme => Theme.Current;

    public DanmakuBlocklistWindow(string text)
    {
        InitializeComponent();
        DataContext = this;
        WordsBox.Text = text;
    }

    void Window_Loaded(object sender, RoutedEventArgs e) => TextInputFocus.Focus(this, WordsBox);

    void Save_Click(object sender, RoutedEventArgs e)
    {
        var words = WordsBox.Text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(word => word.Trim()).Where(word => word.Length > 0).Distinct().ToArray();
        string text = string.Join("\n", words);
        if (words.Length > 4096 || words.Any(word => Encoding.UTF8.GetByteCount(word) > 4094)
            || Encoding.UTF8.GetByteCount(text) > 65536)
        {
            Status.Text = "屏蔽词过长或过多，请减少后保存。";
            Status.Visibility = Visibility.Visible;
            return;
        }

        Player.CommandV("script-message", "player_ui-danmaku-save-words", text);
        Close();
    }

    void Cancel_Click(object sender, RoutedEventArgs e) => Close();
}
