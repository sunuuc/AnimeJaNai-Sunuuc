$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$translator = Join-Path $root 'AnimeJaNaiConfEditor/ChineseLocalization.cs'

# Personal zh-CN build: translate user-visible source before compilation.
# XAML is parsed as XML so bindings, class names and identifiers are never touched.
# C# replacements below are deliberately exact source fragments for dialogs/status text only.

function Unescape-CSharpString([string]$s) {
    $s = $s.Replace('\"', '"')
    $s = $s.Replace('\\', "`0")
    $s = $s.Replace('\r', "`r").Replace('\n', "`n").Replace('\t', "`t")
    $s = $s.Replace("`0", '\')
    return $s
}

$exact = [ordered]@{}
$phrases = [ordered]@{}
if (Test-Path $translator) {
    $src = Get-Content $translator -Raw
    $rxExact = [regex]'\[\"((?:\\.|[^\"])*)\"\]\s*=\s*\"((?:\\.|[^\"])*)\",'
    foreach ($m in $rxExact.Matches($src)) {
        $en = Unescape-CSharpString $m.Groups[1].Value
        $zh = Unescape-CSharpString $m.Groups[2].Value
        if ($en -and -not $exact.Contains($en)) { $exact[$en] = $zh }
    }
    $rxPhrase = [regex]'\(\"((?:\\.|[^\"])*)\",\s*\"((?:\\.|[^\"])*)\"\),'
    foreach ($m in $rxPhrase.Matches($src)) {
        $en = Unescape-CSharpString $m.Groups[1].Value
        $zh = Unescape-CSharpString $m.Groups[2].Value
        if ($en -and -not $phrases.Contains($en)) { $phrases[$en] = $zh }
    }
}

# XAML sentences split by inline <Bold>/<Run> nodes need fragment translations.
$visibleFragments = [ordered]@{
    'Enable logging to view which models are being used and which resolutions they are scaling from.' = '启用日志后可以查看正在使用的模型以及从什么分辨率进行超分。'
    'The log file is created at' = '日志文件会创建在'
    'in the same directory as this config editor.' = '，位于与本管理器相同的目录。'
    'Fastest option but NVIDIA only.' = '速度最快，但仅支持 NVIDIA。'
    'Supports fp16 and fp32 ONNX models.' = '支持 fp16 和 fp32 ONNX 模型。'
    'fp16 models are recommended for faster performance and reduced VRAM usage without any loss in quality.' = '推荐使用 fp16，可在不损失画质的情况下提升速度并减少显存占用。'
    'The initial engine generation may require several minutes but only needs to be done once.' = '首次生成引擎可能需要几分钟，但只需进行一次。'
    'Compatible with NVIDIA, AMD, and Intel GPUs but slower than TensorRT.' = '兼容 NVIDIA、AMD 和 Intel GPU，但速度慢于 TensorRT。'
    'Which input resolutions the engine is built for.' = '决定引擎针对哪些输入分辨率构建。'
    'uses the ONNX model''s shape.' = '使用 ONNX 模型自身的尺寸。'
    'builds for a single resolution and rebuilds when it changes.' = '针对单一分辨率构建，分辨率变化时会重新构建。'
    'builds one engine for the resolution range specified below.' = '针对下方指定的分辨率范围构建一个通用引擎。'
    'sharper subtitles.' = '字幕更清晰。'
    'Rendered at your display resolution instead of being baked into the video, so text stays crisp and isn''t distorted by upscaling.' = '字幕会按显示器分辨率单独渲染，而不是先合成进视频画面，因此文字更清晰，也不会被超分拉伸变形。'
    'Experimental: may cost some performance or have bugs.' = '实验性功能：可能会损失一些性能，或存在兼容性问题。'
    '(default): fastest and most stable.' = '（默认）：速度最快且最稳定。'
    'Subtitles are baked into the video.' = '字幕会直接合成到视频画面中。'
    'Best for most users.' = '适合大多数用户。'
}
foreach ($k in $visibleFragments.Keys) { $phrases[$k] = $visibleFragments[$k] }

$phraseEntries = $phrases.GetEnumerator() | Sort-Object { $_.Key.Length } -Descending

function Translate-VisibleText([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $value }
    $lead = [regex]::Match($value, '^\s*').Value
    $trail = [regex]::Match($value, '\s*$').Value
    $coreLen = $value.Length - $lead.Length - $trail.Length
    if ($coreLen -lt 0) { return $value }
    $core = $value.Substring($lead.Length, $coreLen)
    if ($exact.Contains($core)) {
        return $lead + [string]$exact[$core] + $trail
    }
    $result = $core
    foreach ($e in $phraseEntries) {
        $result = $result.Replace([string]$e.Key, [string]$e.Value)
    }
    return $lead + $result + $trail
}

# ---- XAML: translate only actual display text/attributes -------------------------------
$xamlPath = Join-Path $root 'AnimeJaNaiConfEditor/Views/MainWindow.axaml'
$doc = New-Object System.Xml.XmlDocument
$doc.PreserveWhitespace = $true
$doc.Load($xamlPath)
$visibleAttrs = @('Title', 'Header', 'Content', 'Text', 'Watermark')

foreach ($node in $doc.SelectNodes('//*')) {
    foreach ($attr in @($node.Attributes)) {
        if ($null -eq $attr) { continue }
        $v = $attr.Value
        # StringFormat lives inside a binding expression; only change its display template.
        if ($v.Contains('{Binding')) {
            $v = $v.Replace('StringFormat=Chain {0}', 'StringFormat=处理链 {0}')
            $v = $v.Replace('StringFormat=Model {0}', 'StringFormat=模型 {0}')
            $v = $v.Replace('StringFormat=Remove Chain {0}', 'StringFormat=移除处理链 {0}')
            $v = $v.Replace('StringFormat=Remove Model {0}', 'StringFormat=移除模型 {0}')
            $attr.Value = $v
            continue
        }
        if ($visibleAttrs -contains $attr.LocalName) {
            $attr.Value = Translate-VisibleText $v
        }
    }
    foreach ($child in @($node.ChildNodes)) {
        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Text) {
            $child.Value = Translate-VisibleText $child.Value
        }
    }
}

$settings = New-Object System.Xml.XmlWriterSettings
$settings.OmitXmlDeclaration = $true
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$settings.Indent = $false
$writer = [System.Xml.XmlWriter]::Create($xamlPath, $settings)
try { $doc.Save($writer) } finally { $writer.Dispose() }

function Apply-ExactSourceReplacements([string]$rel, [ordered]$replacements) {
    $path = Join-Path $root $rel
    $text = Get-Content $path -Raw
    foreach ($e in $replacements.GetEnumerator()) {
        if (-not $text.Contains([string]$e.Key)) {
            Write-Host "NOTE: source fragment not found in $rel : $($e.Key)"
            continue
        }
        $text = $text.Replace([string]$e.Key, [string]$e.Value)
    }
    Set-Content -Path $path -Value $text -Encoding utf8
}

# ---- C# dialogs: exact source fragments only --------------------------------------------
$windowCs = [ordered]@{
    'Title = "Import Profile Conf File"' = 'Title = "导入配置文件"'
    'new("AnimeJaNai Conf File")' = 'new("AnimeJaNai 配置文件")'
    'Title = "Confirm Full Conf Import"' = 'Title = "确认导入完整配置"'
    '"The following full conf file will be imported. All configuration settings will be backed up and then all configuration settings for ALL PROFILES will be replaced with the imported conf file.\n\n"' = '"将导入以下完整配置文件。当前全部配置会先自动备份，然后所有配置方案的设置都会被此文件替换。\n\n"'
    'Title = "Import Full Conf File"' = 'Title = "导入配置文件"'
    'new("AnimeJaNai Profile Conf File")' = 'new("AnimeJaNai 配置方案文件")'
    'Title = "Confirm Profile Conf Import"' = 'Title = "确认导入配置"'
    '$"The following profile conf file will be imported to the current profile {vm.CurrentSlot.ProfileName}. All configuration settings will be backed up and then all configuration settings for the current profile {vm.CurrentSlot.ProfileName} will be overwritten.\n\n"' = '$"将把以下配置文件导入当前配置方案“{vm.CurrentSlot.ProfileName}”。当前设置会先自动备份，然后“{vm.CurrentSlot.ProfileName}”的全部设置都会被覆盖。\n\n"'
    '$"The profile {vm.SelectedProfileToClone.ProfileName} will be cloned to the current profile {vm.CurrentSlot.ProfileName}. All configuration settings will be backed up and then all configuration settings for the current profile {vm.CurrentSlot.ProfileName} will be overwritten."' = '$"将把配置方案“{vm.SelectedProfileToClone.ProfileName}”复制到当前配置方案“{vm.CurrentSlot.ProfileName}”。当前设置会先自动备份，然后“{vm.CurrentSlot.ProfileName}”的全部设置都会被覆盖。"'
    'Title = "Export Full Conf File"' = 'Title = "导出完整配置文件"'
    'new("AnimeJaNai Conf File (*.conf)")' = 'new("AnimeJaNai 配置文件 (*.conf)")'
    'Title = "Export Current Profile Conf File"' = 'Title = "导出当前配置文件"'
    'new("AnimeJaNai Profile Conf File (*.pconf)")' = 'new("AnimeJaNai 配置方案文件 (*.pconf)")'
    'Title = "Run playback benchmark"' = 'Title = "运行播放性能测试"'
    '"This measures your real playback fps across several resolutions for the "' = '"这会测试多个分辨率下，均衡和性能模板的实际播放帧率。" +'
    '"Balanced and Performance templates.\n\n" +' = '"\n\n" +'
    '"mpv windows will open and close on their own while it runs. Do not close " +' = '"测试期间 mpv 窗口会自动打开和关闭。请不要关闭或点击这些窗口，否则测试结果会失效。" +'
    '"or click them, or the results will be invalid.\n\n" +' = '"\n\n" +'
    '"The first run builds a TensorRT engine per resolution (about a minute " +' = '"首次运行时，每个分辨率都需要构建一次 TensorRT 引擎（每个大约一分钟，之后会缓存），" +'
    '"each, cached afterward), so the whole benchmark can take 10+ minutes depending on your hardware."' = '"因此整个性能测试可能需要 10 分钟以上，具体取决于你的硬件。"'
    'new FATaskDialogButton("Start benchmark", runResult)' = 'new FATaskDialogButton("开始性能测试", runResult)'
    '"No benchmark results yet"' = '"还没有性能测试结果"'
    '"Run the benchmark first (\"Run Benchmarks\"), then come back here to submit the results."' = '"请先运行性能测试，然后再回来提交结果。"'
    '"Couldn''t read benchmark results"' = '"无法读取性能测试结果"'
    '"No benchmark results found"' = '"未找到性能测试结果"'
    '"benchmark.txt didn''t contain any results. Try running the benchmark again."' = '"benchmark.txt 中没有找到有效结果，请重新运行一次性能测试。"'
    'Watermark = "Optional: a name or handle to credit you (blank = anonymous)"' = 'Watermark = "可选：填写昵称或名称（留空则匿名）"'
    'Watermark = "Optional note: anything notable not already captured above (e.g. undervolt, cooling, laptop on battery)"' = 'Watermark = "可选备注：填写上方未记录的重要信息（例如降压、散热方式、笔记本电池供电等）"'
    '"Below is the hardware data that will be sent to the community benchmark catalog. " +' = '"下面是将发送到社区性能目录的硬件数据。" +'
    '"No account or login is required, and nothing else leaves your machine. " +' = '"不需要账号或登录，也不会发送其他本机数据。" +'
    '"You can optionally add your name and a note."' = '"你可以选择填写昵称和备注。"'
    'Content = "Browse the catalog first: " +' = 'Content = "先浏览性能目录：" +'
    'Text = "Data to submit:"' = 'Text = "将提交的数据："'
    'Title = "Submit benchmark to community catalog"' = 'Title = "将性能测试提交到社区目录"'
    'new FATaskDialogButton("Submit", submitResult)' = 'new FATaskDialogButton("提交", submitResult)'
    'result.ok ? "Submitted" : "Submission failed"' = 'result.ok ? "已提交" : "提交失败"'
    'FATaskDialogButton.OKButton' = 'new FATaskDialogButton("确定", FATaskDialogStandardResult.OK)'
    'FATaskDialogButton.CancelButton' = 'new FATaskDialogButton("取消", FATaskDialogStandardResult.Cancel)'
}
Apply-ExactSourceReplacements 'AnimeJaNaiConfEditor/Views/MainWindow.axaml.cs' $windowCs

$vmCs = [ordered]@{
    'notice = "TensorRT is installed — the backend has switched back to TensorRT.";' = 'notice = "TensorRT 已安装，超分后端已自动切换回 TensorRT。";'
    'flipped = "Switched to DirectML: ";' = 'flipped = "已切换到 DirectML：";'
    'flipped + "TensorRT requires an NVIDIA GPU."' = 'flipped + "TensorRT 需要 NVIDIA GPU。"'
    'flipped + "TensorRT is not installed — install it from the Components tab (recommended for NVIDIA GPUs); the backend switches back automatically once installed."' = 'flipped + "尚未安装 TensorRT。请在“组件”页安装（NVIDIA GPU 推荐）；安装完成后会自动切换回 TensorRT。"'
    'flipped + "TensorRT is not installed."' = 'flipped + "尚未安装 TensorRT。"'
    'Title = "Set up AnimeJaNai"' = 'Title = "设置 AnimeJaNai"'
    'Content = $"Components recommended for this PC are not installed:\n\n{lines}\n\nDownload and install them now ({totalMb:N0} MB)?"' = 'Content = $"尚未安装此电脑推荐的组件：\n\n{lines}\n\n现在下载并安装它们吗（{totalMb:N0} MB）？"'
    'PrimaryButtonText = "Install"' = 'PrimaryButtonText = "安装"'
    'CloseButtonText = "Not now"' = 'CloseButtonText = "暂不安装"'
    'DefaultUpscaleSlots[0].DescriptionText = "Minimum Suggested GPU: NVIDIA RTX 4090";' = 'DefaultUpscaleSlots[0].DescriptionText = "最低建议 GPU：NVIDIA RTX 4090";'
    'DefaultUpscaleSlots[1].DescriptionText = "Minimum Suggested GPU: NVIDIA RTX 3080";' = 'DefaultUpscaleSlots[1].DescriptionText = "最低建议 GPU：NVIDIA RTX 3080";'
    'DefaultUpscaleSlots[2].DescriptionText = "Minimum Suggested GPU: NVIDIA RTX 3060";' = 'DefaultUpscaleSlots[2].DescriptionText = "最低建议 GPU：NVIDIA RTX 3060";'
    'profile_name=Quality' = 'profile_name=质量'
    'profile_name=Balanced' = 'profile_name=均衡'
    'profile_name=Performance' = 'profile_name=性能'
    '"New Profile"' = '"新配置"'
    '$"{InputStatusText} selected for upscaling."' = '$"{InputStatusText} 已选择用于超分。"'
}
Apply-ExactSourceReplacements 'AnimeJaNaiConfEditor/ViewModels/MainWindowViewModel.cs' $vmCs

$benchmarkCs = [ordered]@{
    '$"Thanks! Your benchmark was submitted.\n\nAfter a quick review it will appear in the community catalog at {CatalogUrl}."' = '$"性能测试结果已提交。\n\n经过简单审核后，它会显示在社区性能目录：{CatalogUrl}"'
    '$"The server rejected the submission (HTTP {(int)resp.StatusCode}).\n\n{Truncate(body, 300)}"' = '$"服务器拒绝了本次提交（HTTP {(int)resp.StatusCode}）。\n\n{Truncate(body, 300)}"'
    '$"Couldn''t reach the benchmark server: {ex.Message}\n\n" +' = '$"无法连接性能测试服务器：{ex.Message}\n\n" +'
    '"Please try again later, or share your benchmark.txt on the AnimeJaNai Discord."' = '"请稍后重试，或者把 benchmark.txt 分享到 AnimeJaNai Discord。"'
    '"(no details)"' = '"（无详细信息）"'
}
Apply-ExactSourceReplacements 'AnimeJaNaiConfEditor/Services/BenchmarkSubmission.cs' $benchmarkCs

Write-Host 'Native zh-CN source localization applied safely.'

# Diagnostic: show remaining likely user-visible English in the localized XAML.
Write-Host '--- Remaining likely English in XAML (technical names such as TensorRT/RIFE/fps are allowed) ---'
$lineNo = 0
Get-Content $xamlPath | ForEach-Object {
    $lineNo++
    $line = $_
    if ($line -match '(>[^<]*[A-Za-z]{3,}[^<]*<|\b(Content|Header|Title|Watermark|Text)=\"[^\"]*[A-Za-z]{3,})') {
        Write-Host ("{0}: {1}" -f $lineNo, $line.Trim())
    }
}
