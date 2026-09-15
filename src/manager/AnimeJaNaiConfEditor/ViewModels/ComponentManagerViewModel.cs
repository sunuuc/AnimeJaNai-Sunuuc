using Avalonia.Collections;
using Avalonia.Threading;
using ReactiveUI;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace AnimeJaNaiConfEditor.ViewModels
{
    // One installable component pack (TensorRT runtime, per-GPU-generation kernels, RIFE
    // models), as reported by `AnimeJaNaiUpdater.exe --components --json`.
    public class ComponentItem : ViewModelBase
    {
        public string Name { get; init; } = "";
        public long Bytes { get; init; }
        public bool Installed { get; init; }
        public bool Recommended { get; init; }
        public bool Preselect { get; init; }

        private bool _selected;
        public bool Selected
        {
            get => _selected;
            set => this.RaiseAndSetIfChanged(ref _selected, value);
        }

        public string SizeText => $"{Bytes / 1048576:N0} MB";

        public string StateText => Installed ? AnimeJaNai.Localization.UiText.T("已安装") : AnimeJaNai.Localization.UiText.T("可选");

        // accent-tagged in the UI instead of pre-checked: recommendations should
        // be visible, not pre-decided
        public bool HighlightRecommended => Recommended && !Installed;

        public string Title => Name switch
        {
            "trt-runtime" => AnimeJaNai.Localization.UiText.T("TensorRT 运行库"),
            "rife" => AnimeJaNai.Localization.UiText.T("RIFE 补帧模型"),
            "trt-ptx" => AnimeJaNai.Localization.UiText.T("TensorRT 内核：其他 NVIDIA GPU"),
            _ when Name.StartsWith("trt-sm") => AnimeJaNai.Localization.UiText.F($"TensorRT 内核：{SmFamily(Name[6..])}"),
            _ => Name,
        };

        public string Description => Name switch
        {
            "trt-runtime" => AnimeJaNai.Localization.UiText.T("NVIDIA GPU 上最快的超分后端。未安装时，NVIDIA 用户将回退到速度更慢的 DirectML 后端。"),
            "rife" => AnimeJaNai.Localization.UiText.T("视频补帧（例如 24 → 48 fps）。如果只使用超分则不需要。"),
            "trt-ptx" => AnimeJaNai.Localization.UiText.T("用于没有专用内核包的 NVIDIA GPU 的后备内核。首次构建引擎会更慢。"),
            _ when Name.StartsWith("trt-sm") => AnimeJaNai.Localization.UiText.T("与该代 GPU 匹配的引擎构建内核，仅对应 GPU 需要安装。"),
            _ => "",
        };

        private static string SmFamily(string sm) => sm switch
        {
            "75" => AnimeJaNai.Localization.UiText.T("GeForce RTX 20 系列（Turing）"),
            "80" or "86" => AnimeJaNai.Localization.UiText.T("GeForce RTX 30 系列（Ampere）"),
            "89" => AnimeJaNai.Localization.UiText.T("GeForce RTX 40 系列（Ada）"),
            "90" => "Hopper",
            "100" or "120" => AnimeJaNai.Localization.UiText.T("GeForce RTX 50 系列（Blackwell）"),
            _ => $"sm{sm}",
        };
    }

    // Detects, installs, and removes component packs by shelling out to the updater, which
    // owns all pack logic (release lookup, NVML GPU detection, components.json bookkeeping).
    public class ComponentManagerViewModel : ViewModelBase
    {
        public static string UpdaterPath { get; } =
            Path.Combine(MainWindowViewModel.RootDir, "AnimeJaNaiUpdater.exe");

        public bool UpdaterFound => File.Exists(UpdaterPath);

        public AvaloniaList<ComponentItem> Packs { get; } = [];

        // GPU identity from the engine's NVML detection; null until a refresh
        // has completed (callers fall back to disk-state-only behavior).
        public bool? GpuNvidia { get; private set; }

        public bool TrtPackAvailable { get; private set; }

        // Raised on the UI thread after every refresh (including after Apply),
        // so the Profiles tab can re-derive its component awareness.
        public event Action? Refreshed;

        private string _gpuText = AnimeJaNai.Localization.UiText.T("正在检测硬件……");
        public string GpuText
        {
            get => _gpuText;
            set => this.RaiseAndSetIfChanged(ref _gpuText, value);
        }

        private string _statusLine = "";
        public string StatusLine
        {
            get => _statusLine;
            set => this.RaiseAndSetIfChanged(ref _statusLine, value);
        }

        private bool _setupNeeded;
        public bool SetupNeeded
        {
            get => _setupNeeded;
            set => this.RaiseAndSetIfChanged(ref _setupNeeded, value);
        }

        private bool _isBusy;
        public bool IsBusy
        {
            get => _isBusy;
            set
            {
                this.RaiseAndSetIfChanged(ref _isBusy, value);
                this.RaisePropertyChanged(nameof(NotBusy));
            }
        }

        public bool NotBusy => !IsBusy;

        private bool _loadFailed;
        public bool LoadFailed
        {
            get => _loadFailed;
            set => this.RaiseAndSetIfChanged(ref _loadFailed, value);
        }

        // Populates the pack list. Recommended-but-missing packs come back pre-checked, so
        // first-time setup is "uncheck what you don't want, click Apply".
        public async Task RefreshAsync()
        {
            if (!UpdaterFound)
            {
                GpuText = AnimeJaNai.Localization.UiText.T("安装目录中未找到 AnimeJaNaiUpdater.exe，无法管理组件。");
                LoadFailed = true;
                return;
            }

            IsBusy = true;
            StatusLine = AnimeJaNai.Localization.UiText.T("正在检查已安装组件……");
            try
            {
                var (exitCode, output) = await RunUpdaterAsync("--components --json", null);
                if (exitCode != 0)
                {
                    throw new InvalidOperationException(output.Trim());
                }

                using var doc = JsonDocument.Parse(output);
                var root = doc.RootElement;
                var gpu = root.GetProperty("gpu");
                bool nvidia = gpu.GetProperty("nvidia").GetBoolean();
                GpuText = nvidia
                    ? AnimeJaNai.Localization.UiText.F($"GPU：{gpu.GetProperty("name").GetString()}")
                    : AnimeJaNai.Localization.UiText.T("GPU：未检测到 NVIDIA 设备；内置 DirectML 后端可用于 AMD 和 Intel GPU");
                GpuNvidia = nvidia;

                Packs.Clear();
                foreach (var e in root.GetProperty("packs").EnumerateArray())
                {
                    bool installed = e.GetProperty("installed").GetBoolean();
                    bool recommended = e.GetProperty("recommended").GetBoolean();
                    var item = new ComponentItem
                    {
                        Name = e.GetProperty("name").GetString() ?? "",
                        Bytes = e.GetProperty("bytes").GetInt64(),
                        Installed = installed,
                        Recommended = recommended,
                        Preselect = e.TryGetProperty("preselect", out var pre)
                            ? pre.GetBoolean() : installed || recommended,
                    };
                    // Only what this machine uses (recommended), has (installed, so a
                    // full install can be slimmed), or can choose (rife). Kernel packs
                    // for other GPU generations and the TensorRT stack on non-NVIDIA
                    // boxes are irrelevant here; the updater CLI still lists everything.
                    if (!item.Installed && !item.Recommended && !item.Preselect &&
                        item.Name != "rife")
                    {
                        continue;
                    }
                    // checked = currently installed (the checkbox is desired state);
                    // recommended items are highlighted, never pre-checked
                    item.Selected = item.Installed;
                    Packs.Add(item);
                }

                TrtPackAvailable = Packs.Any(p => p.Name == "trt-runtime");
                SetupNeeded = Packs.Any(p => p.Recommended && !p.Installed);
                string? mismatch = root.TryGetProperty("version_mismatch", out var mm)
                    ? mm.GetString() : null;
                StatusLine = mismatch is not null
                    ? TranslateVersionMismatch(mismatch) + AnimeJaNai.Localization.UiText.T(" 请先更新，再管理组件。")
                    : "";
                LoadFailed = false;
            }
            catch (Exception ex)
            {
                GpuText = AnimeJaNai.Localization.UiText.T("无法读取组件信息。");
                StatusLine = TranslateUpdaterText(ex.Message);
                LoadFailed = true;
            }
            finally
            {
                IsBusy = false;
                Refreshed?.Invoke();
            }
        }

        // Installs every checked-but-missing pack and removes every unchecked-but-installed
        // one, streaming the updater's progress output into the status line.
        public async void Apply()
        {
            var toInstall = Packs.Where(p => p.Selected && !p.Installed).Select(p => p.Name).ToList();
            var toRemove = Packs.Where(p => !p.Selected && p.Installed).Select(p => p.Name).ToList();
            await RunChangesAsync(toInstall, toRemove);
        }

        // What the first-run dialog offers: the engine's preselect set (hardware
        // recommendations, plus RIFE on installs that never managed components).
        public List<ComponentItem> MissingPreselected =>
            Packs.Where(p => p.Preselect && !p.Installed).ToList();

        public async Task InstallMissingPreselectedAsync()
        {
            await RunChangesAsync(MissingPreselected.Select(p => p.Name).ToList(), []);
        }

        private async Task RunChangesAsync(List<string> toInstall, List<string> toRemove)
        {
            if (IsBusy)
            {
                return;
            }
            if (toInstall.Count == 0 && toRemove.Count == 0)
            {
                StatusLine = AnimeJaNai.Localization.UiText.T("没有需要更改的内容。");
                return;
            }

            IsBusy = true;
            try
            {
                foreach (var name in toInstall)
                {
                    var (exitCode, output) = await RunUpdaterAsync($"--install {name}",
                        line => StatusLine = $"{name}：{TranslateUpdaterText(line)}");
                    if (exitCode != 0)
                    {
                        StatusLine = AnimeJaNai.Localization.UiText.F($"安装 {name} 失败：{TranslateUpdaterText(LastLine(output))}");
                        return;
                    }
                }
                foreach (var name in toRemove)
                {
                    StatusLine = AnimeJaNai.Localization.UiText.F($"正在移除 {name}……");
                    var (exitCode, output) = await RunUpdaterAsync($"--remove {name}", null);
                    if (exitCode != 0)
                    {
                        StatusLine = AnimeJaNai.Localization.UiText.F($"移除 {name} 失败：{TranslateUpdaterText(LastLine(output))}");
                        return;
                    }
                }
                StatusLine = AnimeJaNai.Localization.UiText.T("完成。");
            }
            finally
            {
                IsBusy = false;
                await RefreshAsync();
            }
        }

        public async void Refresh()
        {
            await RefreshAsync();
        }

        private static string LastLine(string s) =>
            s.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
             .LastOrDefault() ?? AnimeJaNai.Localization.UiText.T("未知错误");

        private static string TranslateVersionMismatch(string message)
        {
            var match = Regex.Match(message,
                @"^Installed package is (.+?) but the published packs are for (.+?)\.?$");
            if (match.Success)
            {
                return AnimeJaNai.Localization.UiText.F($"当前安装包版本为 {match.Groups[1].Value}，但已发布的组件包对应 {match.Groups[2].Value}。");
            }
            return TranslateUpdaterText(message);
        }

        private static string TranslateUpdaterText(string message)
        {
            if (!AnimeJaNai.Localization.InterfaceLanguage.IsChinese) return message;
            if (string.IsNullOrWhiteSpace(message))
                return message;

            string translated = AnimeJaNaiConfEditor.ChineseLocalization.Translate(message);
            translated = translated.Replace("Download complete", "下载完成", StringComparison.Ordinal)
                                   .Replace("Downloading", "正在下载", StringComparison.Ordinal)
                                   .Replace("Installing", "正在安装", StringComparison.Ordinal)
                                   .Replace("Removing", "正在移除", StringComparison.Ordinal)
                                   .Replace("Done", "完成", StringComparison.Ordinal)
                                   .Replace("failed", "失败", StringComparison.OrdinalIgnoreCase)
                                   .Replace("error", "错误", StringComparison.OrdinalIgnoreCase);
            return translated;
        }

        // Runs the updater hidden; onLine (marshalled to the UI thread) sees each output
        // line live, the full output is returned for error reporting.
        private static async Task<(int ExitCode, string Output)> RunUpdaterAsync(
            string arguments, Action<string>? onLine)
        {
            var psi = new ProcessStartInfo
            {
                FileName = UpdaterPath,
                Arguments = arguments,
                WorkingDirectory = MainWindowViewModel.RootDir,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            using var process = new Process { StartInfo = psi };
            var output = new System.Text.StringBuilder();
            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data is null)
                {
                    return;
                }
                output.AppendLine(e.Data);
                if (onLine is not null && e.Data.Trim() is { Length: > 0 } line)
                {
                    Dispatcher.UIThread.Post(() => onLine(line));
                }
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                {
                    output.AppendLine(e.Data);
                }
            };
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            await process.WaitForExitAsync();
            return (process.ExitCode, output.ToString());
        }
    }
}
