
using CommunityToolkit.Mvvm.Input;
using MpvNet.Help;

namespace MpvNet.Windows.WPF.ViewModels;

public partial class AboutViewModel : ViewModelBase
{
    public Action? CloseAction { get; set; }

    public string About { get; } = AppClass.About;

    [RelayCommand]
    public void OpenSource() => ProcessHelp.ShellExecute("https://github.com/sunuuc/mpv-AnimeVE");

    [RelayCommand]
    public void OpenNotices() => ProcessHelp.ShellExecute(Path.Combine(Folder.Startup, "OPEN_SOURCE_NOTICES.md"));

    [RelayCommand]
    public void Close() => CloseAction!();
}
