using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;

namespace MpvNet.Windows.WPF.Controls;

internal static class TextInputFocus
{
    public static void Focus(Window window, TextBox input, bool selectAll = false)
    {
        window.Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() =>
        {
            if (!window.IsVisible || !input.IsEnabled || !input.Focusable)
                return;

            window.Activate();
            input.Focus();
            Keyboard.Focus(input);
            if (selectAll)
                input.SelectAll();
        }));
    }
}
