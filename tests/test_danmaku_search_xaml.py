import subprocess
import unittest
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WINDOW = ROOT / "src/player/src/MpvNet.Windows/WPF/DanmakuSearchWindow.xaml"


class DanmakuSearchXamlTests(unittest.TestCase):
    def test_blocklist_editor_uses_native_themed_multiline_text_input(self):
        window = WINDOW.with_name('DanmakuBlocklistWindow.xaml')
        source = window.read_text(encoding='utf-8')
        self.assertIn('AcceptsReturn="True"', source)
        self.assertIn('Foreground="{Binding Theme.Foreground}" Background="{Binding Theme.Background}"', source)
        code = window.with_suffix('.xaml.cs').read_text(encoding='utf-8')
        self.assertIn('TextInputFocus.Focus(this, WordsBox)', code)
        self.assertIn('player_ui-danmaku-save-words', code)
        self.assertNotIn('PreviewKeyDown', code)
        env = os.environ.copy();env['BLOCKLIST_XAML'] = str(window)
        powershell = r'''
Add-Type -AssemblyName PresentationFramework
$source = Get-Content -LiteralPath $env:BLOCKLIST_XAML -Raw -Encoding UTF8
$source = $source -replace 'x:Class="[^"]*"|Loaded="[^"]*"|Click="[^"]*"', ''
$window = [System.Windows.Markup.XamlReader]::Parse($source)
$input = $window.FindName('WordsBox')
if ($input -isnot [System.Windows.Controls.TextBox] -or -not $input.AcceptsReturn) { throw 'Invalid input' }
$input.Text = 'English 中文'
$input.Select(2, 0)
$input.SelectedText = 'abc'
if ($input.Text -ne 'Enabcglish 中文') { throw 'Native text editing failed' }
Write-Output 'Native multiline input parsed and edited.'
'''
        done = subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Sta','-Command',powershell],
            env=env,capture_output=True,text=True)
        self.assertEqual(done.returncode,0,done.stdout+done.stderr)
        self.assertIn('Native multiline input parsed and edited.',done.stdout)

    def test_group_item_template_does_not_alias_a_missing_header_property(self):
        source = WINDOW.read_text(encoding="utf-8")
        self.assertIn('<Style x:Key="ResultGroupItem" TargetType="GroupItem">', source)
        self.assertIn('<ContentPresenter />', source)
        self.assertNotIn('ContentSource="Header"', source)

    def test_wpf_can_parse_the_actual_group_item_and_header_templates(self):
        powershell = r"""
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $env:PLAYERUI_DANMAKU_SEARCH_XAML -Raw
$style = [regex]::Match($source, '<Style x:Key="ResultGroupItem"[\s\S]*?</Style>').Value
$group = [regex]::Match($source, '<GroupStyle ContainerStyle="\{StaticResource ResultGroupItem\}">[\s\S]*?</GroupStyle>').Value
if (-not $style -or -not $group) { throw 'Could not extract the production GroupItem resources.' }
$xaml = "<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'><Window.Resources>$style</Window.Resources><ListBox>$group</ListBox></Window>"
Add-Type -AssemblyName PresentationFramework
[System.Windows.Markup.XamlReader]::Parse($xaml) | Out-Null
Write-Output 'Production GroupItem XAML parsed.'
"""
        env = os.environ.copy()
        env["PLAYERUI_DANMAKU_SEARCH_XAML"] = str(WINDOW)
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Sta", "-Command", powershell],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Production GroupItem XAML parsed.", result.stdout)


if __name__ == "__main__":
    unittest.main()
