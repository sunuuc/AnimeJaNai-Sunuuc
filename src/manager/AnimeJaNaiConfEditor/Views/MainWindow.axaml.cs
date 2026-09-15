using AnimeJaNaiConfEditor.Services;
using AnimeJaNaiConfEditor.ViewModels;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Controls.Primitives;
using Avalonia.Data;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using ReactiveUI.Avalonia;
using FluentAvalonia.UI.Controls;
using FluentAvalonia.UI.Windowing;
using Material.Icons.Avalonia;
using ReactiveUI;
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reactive.Linq;
using System.Threading.Tasks;

namespace AnimeJaNaiConfEditor.Views
{
    public partial class MainWindow : FAAppWindow
    {
        public MainWindow()
        {
            AvaloniaXamlLoader.Load(this);
            LanguagePanel.Attach(this);
            Closing += MainWindow_Closing;
            Opened += MainWindow_Opened;
        }

        private void MainWindow_Opened(object? sender, EventArgs e)
        {
            if (DataContext is MainWindowViewModel vm)
            {

            }
        }

        private async void MainWindow_Closing(object? sender, WindowClosingEventArgs e)
        {
            if (DataContext is MainWindowViewModel vm)
            {

            }
        }

        private async void ImportFullConfButtonClick(object? sender, RoutedEventArgs e)
        {
            if (DataContext is MainWindowViewModel vm)
            {
                // Get top level from the current control. Alternatively, you can use Window reference instead.
                var topLevel = GetTopLevel(this);

                // Start async operation to open the dialog.
                var storageProvider = topLevel.StorageProvider;

                var files = await storageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
                {
                    Title = AnimeJaNai.Localization.UiText.T("Import Profile Conf File"),
                    AllowMultiple = false,
                    FileTypeFilter = new FilePickerFileType[] { new(AnimeJaNai.Localization.UiText.T("AnimeJaNai Conf File")) { Patterns = new[] { "*.conf" }, MimeTypes = new[] { "*/*" } }, FilePickerFileTypes.All },
                    SuggestedStartLocation = await storageProvider.TryGetFolderFromPathAsync(vm.BackupPath),
                });

                if (files.Count >= 1)
                {

                    var inPath = files[0].TryGetLocalPath();

                    if (inPath != null)
                    {
                        var td = new FATaskDialog
                        {
                            Title = AnimeJaNai.Localization.UiText.T("Confirm Full Conf Import"),
                            ShowProgressBar = false,
                            Content = AnimeJaNai.Localization.UiText.T("The following full conf file will be imported. All configuration settings will be backed up and then all configuration settings for ALL PROFILES will be replaced with the imported conf file.\n\n") +
    inPath,
                            Buttons =
            {
                new FATaskDialogButton(AnimeJaNai.Localization.UiText.T("OK"), FATaskDialogStandardResult.OK),
                new FATaskDialogButton(AnimeJaNai.Localization.UiText.T(AnimeJaNai.Localization.UiText.T("Cancel")), FATaskDialogStandardResult.Cancel)
            }
                        };


                        td.Closing += async (s, e) =>
                        {
                            if ((FATaskDialogStandardResult)e.Result == FATaskDialogStandardResult.OK)
                            {
                                var deferral = e.GetDeferral();

                                td.ShowProgressBar = true;
                                int value = 0;


                                await Task.Run(() =>
                                {
                                    vm.CheckAndDoBackup();
                                    // autoSave: true wires the imported slots/chains/models for
                                    // persistence; the explicit write commits the import itself to
                                    // animejanai.conf (assigning AnimeJaNaiConf does not trigger a save).
                                    vm.AnimeJaNaiConf = vm.ReadAnimeJaNaiConf(inPath, true);
                                    vm.WriteAnimeJaNaiConf();
                                });

                                deferral.Complete();
                            }
                        };

                        td.XamlRoot = this;
                        _ = await td.ShowAsync();
                    }

                }
            }
        }

        private async void ImportCurrentProfileConfButtonClick(object? sender, RoutedEventArgs e)
        {
            if (DataContext is MainWindowViewModel vm)
            {
                // Get top level from the current control. Alternatively, you can use Window reference instead.
                var topLevel = GetTopLevel(this);

                // Start async operation to open the dialog.
                var storageProvider = topLevel.StorageProvider;

                var files = await storageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
                {
                    Title = AnimeJaNai.Localization.UiText.T("Import Full Conf File"),
                    AllowMultiple = false,
                    FileTypeFilter = new FilePickerFileType[] { new(AnimeJaNai.Localization.UiText.T("AnimeJaNai Profile Conf File")) { Patterns = new[] { "*.pconf" }, MimeTypes = new[] { "*/*" } }, FilePickerFileTypes.All },
                    SuggestedStartLocation = await storageProvider.TryGetFolderFromPathAsync(vm.BackupPath),
                });

                if (files.Count >= 1)
                {

                    var inPath = files[0].TryGetLocalPath();

                    if (inPath != null)
                    {
                        if (vm.CurrentSlot.Chains.Count == 0)
                        {
                            // blank slot, no need to prompt before importing and no need to do backup
                            vm.ReadAnimeJaNaiConfToCurrentSlot(inPath, true);
                        }
                        else
                        {
                            var td = new FATaskDialog
                            {
                                Title = AnimeJaNai.Localization.UiText.T("Confirm Profile Conf Import"),
                                ShowProgressBar = false,
                                Content = AnimeJaNai.Localization.UiText.F($"The following profile conf file will be imported to the current profile {vm.CurrentSlot.ProfileName}. All configuration settings will be backed up and then all configuration settings for the current profile {vm.CurrentSlot.ProfileName} will be overwritten.\n\n") +
                                inPath,
                                Buttons =
                            {
                                new FATaskDialogButton(AnimeJaNai.Localization.UiText.T("OK"), FATaskDialogStandardResult.OK),
                                new FATaskDialogButton(AnimeJaNai.Localization.UiText.T(AnimeJaNai.Localization.UiText.T("Cancel")), FATaskDialogStandardResult.Cancel)
                            }
                            };


                            td.Closing += async (s, e) =>
                            {
                                if ((FATaskDialogStandardResult)e.Result == FATaskDialogStandardResult.OK)
                                {
                                    var deferral = e.GetDeferral();

                                    td.ShowProgressBar = true;

                                    await Task.Run(() =>
                                    {
                                        vm.CheckAndDoBackup();
                                        vm.ReadAnimeJaNaiConfToCurrentSlot(inPath, true);
                                    });

                                    deferral.Complete();
                                }
                            };

                            td.XamlRoot = this;
                            _ = await td.ShowAsync();
                        }
                    }

                } 
            }
        }

        private async void CloneSelectedProfileToCurrentProfile(object? sender, RoutedEventArgs e)
        {
            if (DataContext is MainWindowViewModel vm)
            {
                if (vm.SelectedProfileToClone != null)
                {
                    if (vm.CurrentSlot.Chains.Count == 0)
                    {
                        // Current slot is blank - no need to ask user for confirmation before cloning and no need to do backup
                        vm.ReadAnimeJaNaiConfToCurrentSlot(
                            vm.ParsedAnimeJaNaiProfileConf(vm.SelectedProfileToClone),
                            true);
                    }
                    else
                    {
                        var td = new FATaskDialog
                        {
                            Title = AnimeJaNai.Localization.UiText.T("Confirm Profile Conf Import"),
                            ShowProgressBar = false,
                            Content = AnimeJaNai.Localization.UiText.F($"The profile {vm.SelectedProfileToClone.ProfileName} will be cloned to the current profile {vm.CurrentSlot.ProfileName}. All configuration settings will be backed up and then all configuration settings for the current profile {vm.CurrentSlot.ProfileName} will be overwritten."),
                            Buttons =
                        {
                            new FATaskDialogButton(AnimeJaNai.Localization.UiText.T("OK"), FATaskDialogStandardResult.OK),
                            new FATaskDialogButton(AnimeJaNai.Localization.UiText.T(AnimeJaNai.Localization.UiText.T("Cancel")), FATaskDialogStandardResult.Cancel)
                        }
                        };


                        td.Closing += async (s, e) =>
                        {
                            if ((FATaskDialogStandardResult)e.Result == FATaskDialogStandardResult.OK)
                            {
                                var deferral = e.GetDeferral();

                                td.ShowProgressBar = true;
                                int value = 0;


                                await Task.Run(() =>
                                {
                                    vm.CheckAndDoBackup();
                                    vm.ReadAnimeJaNaiConfToCurrentSlot(
                                        vm.ParsedAnimeJaNaiProfileConf(vm.SelectedProfileToClone),
                                        true);
                                });

                                deferral.Complete();
                            }
                        };

                        td.XamlRoot = this;
                        _ = await td.ShowAsync();
                    }
                }
            }
        }

        private async void ExportFullConfButtonClick(object? sender, RoutedEventArgs e)
        {
            if (DataContext is MainWindowViewModel vm)
            {
                // Get top level from the current control. Alternatively, you can use Window reference instead.
                var topLevel = GetTopLevel(this);

                var storageProvider = topLevel.StorageProvider;

                // Start async operation to open the dialog.
                var file = await storageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
                {
                    Title = AnimeJaNai.Localization.UiText.T("Export Full Conf File"),
                    DefaultExtension = "conf",
                    FileTypeChoices = new FilePickerFileType[]
                    {
                    new(AnimeJaNai.Localization.UiText.T("AnimeJaNai Conf File (*.conf)")) { Patterns = new[] { "*.conf" } },
                    },
                    SuggestedStartLocation = await storageProvider.TryGetFolderFromPathAsync(vm.BackupPath),
                });

                if (file is not null)
                {

                    //vm.OutputFilePath = file.TryGetLocalPath() ?? "";

                    var outPath = file.TryGetLocalPath();

                    if (outPath != null)
                    {
                        vm.WriteAnimeJaNaiConf(outPath);
                    }

                }
            }
        }

        private async void ExportCurrentProfileConfButtonClick(object? sender, RoutedEventArgs e)
        {
            if (DataContext is MainWindowViewModel vm)
            {
                // Get top level from the current control. Alternatively, you can use Window reference instead.
                var topLevel = GetTopLevel(this);

                var storageProvider = topLevel.StorageProvider;

                // Start async operation to open the dialog.
                var file = await storageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
                {
                    Title = AnimeJaNai.Localization.UiText.T("Export Current Profile Conf File"),
                    DefaultExtension = "conf",
                    FileTypeChoices = new FilePickerFileType[]
                    {
                    new(AnimeJaNai.Localization.UiText.T("AnimeJaNai Profile Conf File (*.pconf)")) { Patterns = new[] { "*.pconf" } },
                    },
                    SuggestedStartLocation = await storageProvider.TryGetFolderFromPathAsync(vm.BackupPath),
                });

                if (file is not null)
                {
                    var outPath = file.TryGetLocalPath();

                    if (outPath != null)
                    {
                        vm.WriteAnimeJaNaiCurrentProfileConf(outPath);
                    }
                }
            }
        }

        private async void RunBenchmarkButtonClick(object? sender, RoutedEventArgs e)
        {
            if (DataContext is not MainWindowViewModel vm) return;

            const string runResult = "run";
            var td = new FATaskDialog
            {
                Title = AnimeJaNai.Localization.UiText.T("Run playback benchmark"),
                Content = new TextBlock
                {
                    TextWrapping = TextWrapping.Wrap,
                    MaxWidth = 460,
                    Text =
                        AnimeJaNai.Localization.UiText.T("This measures your real playback fps across several resolutions for the ") +
                        AnimeJaNai.Localization.UiText.T("Balanced and Performance templates.\n\n") +
                        AnimeJaNai.Localization.UiText.T("mpv windows will open and close on their own while it runs. Do not close ") +
                        AnimeJaNai.Localization.UiText.T("or click them, or the results will be invalid.\n\n") +
                        AnimeJaNai.Localization.UiText.T("The first run builds a TensorRT engine per resolution (about a minute ") +
                        AnimeJaNai.Localization.UiText.T("each, cached afterward), so the whole benchmark can take 10+ minutes depending on your hardware."),
                },
                Buttons =
                {
                    new FATaskDialogButton(AnimeJaNai.Localization.UiText.T("Start benchmark"), runResult),
                    new FATaskDialogButton(AnimeJaNai.Localization.UiText.T(AnimeJaNai.Localization.UiText.T("Cancel")), FATaskDialogStandardResult.Cancel),
                },
            };
            td.XamlRoot = this;
            if (Equals(await td.ShowAsync(), runResult))
                vm.LaunchBenchmark();
        }

        private async void SubmitBenchmarkButtonClick(object? sender, RoutedEventArgs e)
        {
            if (DataContext is not MainWindowViewModel) return;

            var benchmarkTxt = Path.Combine(MainWindowViewModel.DataDir, "benchmark.txt");
            if (!File.Exists(benchmarkTxt))
            {
                await ShowInfoDialog(AnimeJaNai.Localization.UiText.T("No benchmark results yet"),
                    AnimeJaNai.Localization.UiText.T("Run the benchmark first (\"Run Benchmarks\"), then come back here to submit the results."));
                return;
            }

            BenchmarkSubmission sub;
            try
            {
                sub = await Task.Run(() =>
                {
                    var s = BenchmarkSubmission.FromBenchmarkFile(benchmarkTxt);
                    s.FillSystemInfo(MainWindowViewModel.DataDir);
                    return s;
                });
            }
            catch (Exception ex)
            {
                await ShowInfoDialog(AnimeJaNai.Localization.UiText.T("Couldn't read benchmark results"), ex.Message);
                return;
            }

            if (!sub.HasResults)
            {
                await ShowInfoDialog(AnimeJaNai.Localization.UiText.T("No benchmark results found"),
                    AnimeJaNai.Localization.UiText.T("benchmark.txt didn't contain any results. Try running the benchmark again."));
                return;
            }

            // The dialog's state: name/note are two-way bound; the JSON preview is derived
            // reactively from them, so it always shows exactly what will be sent.
            var model = new SubmitDialogModel(sub);

            var preview = new TextBox
            {
                IsReadOnly = true,
                AcceptsReturn = true,
                TextWrapping = TextWrapping.NoWrap,
                MaxHeight = 260,
                FontFamily = new FontFamily("Consolas, Cascadia Mono, monospace"),
                FontSize = 11,
            };
            preview.Bind(TextBox.TextProperty, new Binding(nameof(SubmitDialogModel.Preview)) { Mode = BindingMode.OneWay });

            var submittedBy = new TextBox
            {
                Watermark = AnimeJaNai.Localization.UiText.T("Optional: a name or handle to credit you (blank = anonymous)"),
                MaxLength = 60,
                Margin = new Thickness(0, 8, 0, 0),
            };
            submittedBy.Bind(TextBox.TextProperty, new Binding(nameof(SubmitDialogModel.SubmittedBy)) { Mode = BindingMode.TwoWay });

            var note = new TextBox
            {
                Watermark = AnimeJaNai.Localization.UiText.T("Optional note: anything notable not already captured above (e.g. undervolt, cooling, laptop on battery)"),
                AcceptsReturn = true,
                TextWrapping = TextWrapping.Wrap,
                MaxLength = 280,
                MinHeight = 60,
                MaxHeight = 90,
                Margin = new Thickness(0, 8, 0, 0),
            };
            note.Bind(TextBox.TextProperty, new Binding(nameof(SubmitDialogModel.Note)) { Mode = BindingMode.TwoWay });
            ScrollViewer.SetHorizontalScrollBarVisibility(note, ScrollBarVisibility.Disabled);
            ScrollViewer.SetVerticalScrollBarVisibility(note, ScrollBarVisibility.Auto);

            // Children inherit this DataContext, so the bindings above resolve against the model.
            var panel = new StackPanel { Width = 460, DataContext = model };
            panel.Children.Add(new TextBlock
            {
                TextWrapping = TextWrapping.Wrap,
                Text = AnimeJaNai.Localization.UiText.T("Below is the hardware data that will be sent to the community benchmark catalog. ") +
                       AnimeJaNai.Localization.UiText.T("No account or login is required, and nothing else leaves your machine. ") +
                       AnimeJaNai.Localization.UiText.T("You can optionally add your name and a note."),
            });
            panel.Children.Add(new HyperlinkButton
            {
                Content = AnimeJaNai.Localization.UiText.T("Browse the catalog first: ") + BenchmarkSubmission.CatalogUrl,
                NavigateUri = new Uri(BenchmarkSubmission.CatalogUrl),
                Padding = new Thickness(0),
                Margin = new Thickness(0, 4, 0, 0),
                FontSize = 12,
            });
            panel.Children.Add(new TextBlock
            {
                Margin = new Thickness(0, 8, 0, 2),
                Opacity = .6,
                FontSize = 11,
                Text = AnimeJaNai.Localization.UiText.T("Data to submit:"),
            });
            panel.Children.Add(preview);
            panel.Children.Add(submittedBy);
            panel.Children.Add(note);

            const string submitResult = "submit";
            var td = new FATaskDialog
            {
                Title = AnimeJaNai.Localization.UiText.T("Submit benchmark to community catalog"),
                Content = panel,
                ShowProgressBar = false,
                Buttons =
                {
                    new FATaskDialogButton(AnimeJaNai.Localization.UiText.T("Submit"), submitResult),
                    new FATaskDialogButton(AnimeJaNai.Localization.UiText.T(AnimeJaNai.Localization.UiText.T("Cancel")), FATaskDialogStandardResult.Cancel),
                },
            };

            (bool ok, string message)? outcome = null;
            td.Closing += async (s, ev) =>
            {
                if (!Equals(ev.Result, submitResult)) return;
                var deferral = ev.GetDeferral();
                td.ShowProgressBar = true;
                outcome = await sub.SubmitAsync();   // sub's name/note are kept current by SubmitDialogModel
                deferral.Complete();
            };

            td.XamlRoot = this;
            await td.ShowAsync();

            if (outcome is { } result)
                await ShowInfoDialog(result.ok ? AnimeJaNai.Localization.UiText.T("Submitted") : AnimeJaNai.Localization.UiText.T("Submission failed"), result.message);
        }

        // Backs the submit dialog: name/note are two-way bound; the JSON preview is an
        // ObservableAsPropertyHelper derived from them, so it stays in sync with what will be sent.
        private sealed class SubmitDialogModel : ReactiveObject
        {
            private string _submittedBy = "";
            private string _note = "";
            private readonly ObservableAsPropertyHelper<string> _preview;

            public SubmitDialogModel(BenchmarkSubmission sub)
            {
                _preview = this.WhenAnyValue(x => x.SubmittedBy, x => x.Note)
                    .Do(t =>
                    {
                        sub.SubmittedBy = (t.Item1 ?? "").Trim();
                        sub.Note = (t.Item2 ?? "").Trim();
                    })
                    .Select(_ => sub.ToPreviewJson())
                    .ToProperty(this, x => x.Preview);
            }

            public string SubmittedBy { get => _submittedBy; set => this.RaiseAndSetIfChanged(ref _submittedBy, value); }
            public string Note { get => _note; set => this.RaiseAndSetIfChanged(ref _note, value); }
            public string Preview => _preview.Value;
        }

        private async Task ShowInfoDialog(string title, string message)
        {
            var td = new FATaskDialog
            {
                Title = title,
                Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, MaxWidth = 460 },
                Buttons = { new FATaskDialogButton(AnimeJaNai.Localization.UiText.T("OK"), FATaskDialogStandardResult.OK) },
            };
            td.XamlRoot = this;
            await td.ShowAsync();
        }
    }
}