"Keep managed and native startup state consistent before publishing."
from pathlib import Path
R=Path(__file__).resolve().parents[2]

def edit(name,old,new):
    p=R/name;s=p.read_text(encoding='utf-8-sig')
    if new in s:return
    if s.count(old)!=1:raise RuntimeError('Startup patch context changed: '+name+' '+old[:80])
    p.write_text(s.replace(old,new),encoding='utf-8')

p='src/player/src/MpvNet/Player.cs'
edit(p,'if (CommandLine.Contains("config-dir"))',
     'if (CommandLine.Contains("config-dir") && !CommandLine.Contains("input-conf"))')
edit(p,'                string? mpvnet_home = Environment.GetEnvironmentVariable("MPVNET_HOME");',
     '                string explicitConfig = CommandLine.GetValue("config-dir");\n'
     '                if (explicitConfig.Length > 0)\n'
     '                    return _configFolder = System.IO.Path.GetFullPath(explicitConfig).AddSep();\n\n'
     '                string? mpvnet_home = Environment.GetEnvironmentVariable("MPVNET_HOME");')
p='src/player/src/MpvNet/App.cs'
edit(p,'            Player.SetPropertyInt("volume", Settings.Volume);\n'
       '            Player.SetPropertyString("mute", Settings.Mute);',
       '            if (!CommandLine.Contains("volume")) Player.SetPropertyInt("volume", Settings.Volume);\n'
       '            if (!CommandLine.Contains("mute")) Player.SetPropertyString("mute", Settings.Mute);')
edit(p,'if (RememberAudioDevice && Settings.AudioDevice != "")',
     'if (RememberAudioDevice && Settings.AudioDevice != "" && !CommandLine.Contains("audio-device"))')
p='src/player/src/MpvNet.Windows/Program.cs'
edit(p,'            App.Init();','            StartupDiagnostics.Begin();\n            App.Init();')
edit(p,'            Terminal.WriteError(ex);','            StartupDiagnostics.Failed();\n            Terminal.WriteError(ex);')

p='tests/test_startup_playback.py'
edit(p,"def options(uri):\n"
       "    return ['--script-opts=handoff-url='+uri,'--script-opt=handoff-tag=first','--script-opts-append','handoff-tag=ready']\n",
       "def options(uri,native=False):\n"
       "    tail=['--script-opts-append=handoff-tag=ready'] if native else ['--script-opts-append','handoff-tag=ready']\n"
       "    return ['--script-opts=handoff-url='+uri,'--script-opt=handoff-tag=first',*tail]\n")
edit(p,"    args=[flag+BOOT.name,*options(uri)]",
       "    args=[flag+BOOT.name,*options(uri,exe=='mpv.exe')]")

command=(R/'src/player/src/MpvNet/CommandLine.cs').read_text(encoding='utf-8-sig')
# --playlist must never reach mpv_set_option_string before mpv_initialize: that
# deadlocks libmpv. It has to be skipped pre-init and loaded with loadlist after
# initialization, then selected with playlist-play-index.
for marker in ('IsNativePlaylistStartupOption','loadlist','playlist-play-index',
               'pair.Name == "playlist"','SetStartupOption(pair.Name, pair.Value)'):
    if marker not in command:raise RuntimeError('Player UI playlist handoff fix missing: '+marker)
if 'mpv must receive --playlist' in command:
    raise RuntimeError('Unsafe pre-init --playlist handoff was reintroduced')
scoped=(R/'src/player/src/MpvNet/ScopedCommandLine.cs').read_text(encoding='utf-8-sig')
for marker in ('PromotedOptions','EmptyGroupCount'):
    if marker not in scoped:raise RuntimeError('Scoped handoff provenance missing: '+marker)

build=(R/'tools/standalone/build.py').read_text(encoding='utf-8-sig')
for marker in ("tests/test_startup_playback.py","tests/test_player_ui_empty_scope.py"):
    if marker not in build:raise RuntimeError('Fresh-install startup regression missing: '+marker)
publish=(R/'tools/standalone/publish.py').read_text(encoding='utf-8-sig')
if "len(result)==3" not in publish or "player_ui-handoff/results.json" not in publish:
    raise RuntimeError('Publication gate for Player UI playlist regression is missing')
print('Standalone startup sources prepared')
