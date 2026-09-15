using System;
using System.Globalization;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Data.Converters;

namespace AnimeJaNaiConfEditor
{
    /// <summary>
    /// Returns the full text of a <see cref="TextBlock"/> regardless of whether its content
    /// was authored as the <see cref="TextBlock.Text"/> property (plain text) or as inline
    /// content such as <see cref="Bold"/>/<see cref="Run"/> (where <c>Text</c> is null and the
    /// text lives in <see cref="InlineCollection.Text"/>). Used to feed the help tooltips the
    /// untrimmed text even when <c>MaxLines</c>/<c>TextTrimming</c> truncate what is shown.
    /// </summary>
    public class HelpTextConverter : IValueConverter
    {
        public static readonly HelpTextConverter Instance = new();

        public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
            => value is TextBlock tb ? (tb.Text ?? tb.Inlines?.Text) : null;

        public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
            => null;
    }
}
