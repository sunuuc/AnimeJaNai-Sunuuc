using AnimeJaNaiConfEditor.ViewModels;
using AnimeJaNaiConfEditor.Views;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using System.Threading.Tasks;

namespace AnimeJaNaiConfEditor
{
    public partial class App : Application
    {
        public override void Initialize()
        {
            AvaloniaXamlLoader.Load(this);
        }

        public override void OnFrameworkInitializationCompleted()
        {
            // Dialog handlers are `async void`, so an exception thrown from one is posted
            // to the UI dispatcher and would otherwise crash the whole app.
            Dispatcher.UIThread.UnhandledException += (_, e) => e.Handled = true;
            TaskScheduler.UnobservedTaskException += (_, e) => e.SetObserved();

            if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
            {
                // The zh-CN build is localized in source before compilation. There is no
                // runtime English UI, translation timer, opacity trick, or post-render pass.
                desktop.MainWindow = new MainWindow
                {
                    DataContext = new MainWindowViewModel(),
                };

                // When another launch (e.g. repeated Ctrl+E from mpv) signals this instance,
                // bring the existing window to the front instead of opening a new one.
                Program.ActivationRequested += () => BringToFront(desktop.MainWindow);
            }

            base.OnFrameworkInitializationCompleted();
        }

        private static void BringToFront(Window? window)
        {
            if (window is null)
            {
                return;
            }

            if (window.WindowState == WindowState.Minimized)
            {
                window.WindowState = WindowState.Normal;
            }

            window.Show();
            window.Activate();
        }
    }
}
