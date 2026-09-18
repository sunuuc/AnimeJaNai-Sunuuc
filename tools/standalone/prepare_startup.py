"""Keep managed and native startup state consistent before publishing."""
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
'''                string explicitConfig = CommandLine.GetValue("config-dir");
                if (explicitConfig.Length > 0)
                    return _configFolder = System.IO.Path.GetFullPath(explicitConfig).AddSep();

                string? mpvnet_home = Environment.GetEnvironmentVariable("MPVNET_HOME");''')
p='src/player/src/MpvNet/App.cs'
edit(p,'            Player.SetPropertyInt("volume", Settings.Volume);\n            Player.SetPropertyString("mute", Settings.Mute);',
'''            if (!CommandLine.Contains("volume")) Player.SetPropertyInt("volume", Settings.Volume);
            if (!CommandLine.Contains("mute")) Player.SetPropertyString("mute", Settings.Mute);''')
edit(p,'if (RememberAudioDevice && Settings.AudioDevice != "")',
     'if (RememberAudioDevice && Settings.AudioDevice != "" && !CommandLine.Contains("audio-device"))')
p='src/player/src/MpvNet.Windows/Program.cs'
edit(p,'            App.Init();','            StartupDiagnostics.Begin();\n            App.Init();')
edit(p,'            Terminal.WriteError(ex);','            StartupDiagnostics.Failed();\n            Terminal.WriteError(ex);')

p='tests/test_startup_playback.py'
edit(p,"""def options(uri):
    return ['--script-opts=handoff-url='+uri,'--script-opt=handoff-tag=first','--script-opts-append','handoff-tag=ready']
""", """def options(uri,native=False):
    tail=['--script-opts-append=handoff-tag=ready'] if native else ['--script-opts-append','handoff-tag=ready']
    return ['--script-opts=handoff-url='+uri,'--script-opt=handoff-tag=first',*tail]
""")
edit(p,"    args=[flag+BOOT.name,*options(uri)]", "    args=[flag+BOOT.name,*options(uri,exe=='mpv.exe')]")

p='tools/standalone/build.py'
edit(p,'def inspect_payload():', '''def clean_session_files(app):
    for folder in ('cache','watch_later'):
        shutil.rmtree(app/'portable_config'/folder,ignore_errors=True)
    for name in ('settings.xml','saved-props.json','startup-diagnostic.json','startup-diagnostic.json.tmp','playback-diagnostic.json'):
        (app/'portable_config'/name).unlink(missing_ok=True)

def inspect_payload():
    clean_session_files(ST)''')
old="    run(sys.executable,R/'tests/test_network_playback.py',R/'clean-install',E/'fresh-install/network')"
edit(p,old,old+"\n    run(sys.executable,R/'tests/test_startup_playback.py',R/'clean-install',E/'fresh-install/startup')")
p='tools/standalone/publish.py'
old="head=api(f'repos/{REPO}/git/ref/heads/main')['object']['sha']"
edit(p,old,"""for path in (E/'startup/results.json',E/'fresh-install/startup/results.json'):
    result=json.loads(path.read_text());assert len(result)==7 and all(t['passed'] for t in result),path
"""+old)
print('Standalone startup sources prepared')
