"""Build bilingual UI from pinned source. Never rewrite code identifiers or config values."""
from pathlib import Path
import json,re,shutil,struct,subprocess,sys,xml.etree.ElementTree as ET,hashlib
HERE=Path(__file__).resolve().parent
ROOT=Path.cwd();MAN=ROOT/'manager/AnimeJaNaiConfEditor';PLY=ROOT/'player'
D={};KEYS={};report={}
def cs(s):return json.loads('"'+s+'"')
def put(a,b):
    if a and b and a!=b:D[a]=b
src=(MAN/'ChineseLocalization.cs').read_text(encoding='utf-8-sig')
for a,b in re.findall(r'\["((?:\\.|[^"\\])*)"\]\s*=\s*"((?:\\.|[^"\\])*)"',src):put(cs(a),cs(b))
ps=(ROOT/'manager/scripts/ApplyNativeChinese.ps1').read_text(encoding='utf-8-sig')
fragments={}
for a,b in re.findall(r"^\s*'((?:''|[^'])*)'\s*=\s*'((?:''|[^'])*)'\s*$",ps,re.M):
    a,b=a.replace("''","'"),b.replace("''","'")
    if '"' not in a and not a.startswith('profile_name='):fragments[a]=b
    x=re.findall(r'(?<![$@])"((?:\\.|[^"\\])*)"',a)
    y=re.findall(r'(?<![$@])"((?:\\.|[^"\\])*)"',b)
    if len(x)==len(y)==1:
        try:put(cs(x[0]),cs(y[0]))
        except ValueError:pass
D.update(fragments)
D.update(json.loads((HERE/'extra.json').read_text(encoding='utf-8')))
blocks=[]
for block in (PLY/'src/MpvNet.Windows/Resources/editor_conf.txt').read_text(encoding='utf-8-sig').split('\n\n'):
    pairs={}
    for line in block.splitlines():
        if '=' in line and not line.startswith('#'):
            a,b=line.split('=',1);pairs.setdefault(a.strip(),b.strip())
    if 'name' in pairs and 'help' in pairs:blocks.append(pairs)
rows=[line.split('\t') for line in (HERE/'settings-zh.tsv').read_text(encoding='utf-8').splitlines()]
assert len(rows)==len(blocks)==150,'Settings source changed; review translations before building'
for row,block in zip(rows,blocks):
    name,label,help_zh=row
    assert name==block['name'],name
    D[name]=label;D[block['help'].replace('\\n','\n')]=help_zh

def po_read(path):
    items={};entry={};field=None
    def flush():
        if 'msgid' in entry and entry.get('msgstr'):
            key=entry['msgid'];ctx=entry.get('msgctxt')
            items[(ctx+'\x04' if ctx else '')+key]=entry['msgstr']
    for line in path.read_text(encoding='utf-8-sig').splitlines()+['']:
        line=line.strip()
        if not line:flush();entry={};field=None;continue
        m=re.match(r'^(msgid|msgstr|msgctxt) (".*")$',line)
        if m:field=m[1];entry[field]=json.loads(m[2])
        elif line.startswith('"') and field:entry[field]+=json.loads(line)
        elif line.startswith('msgid_plural'):raise ValueError('Plural catalog requires explicit handling')
    return items
catalog=po_read(PLY/'lang/po/zh_CN.po')
for a,b in catalog.items():
    if a and '\x04' not in a:D.setdefault(a,b)

def key(text):
    k='s'+hashlib.sha256(text.encode()).hexdigest()[:16];KEYS[k]=text;return k

def translated(text):
    core=text.strip()
    if not core:return text
    if core in D:return D[core]
    result=core
    for a,b in sorted(D.items(),key=lambda p:len(p[0]),reverse=True):
        if len(a)>15:result=result.replace(a,b)
    return result
AV='https://github.com/avaloniaui';WP='http://schemas.microsoft.com/winfx/2006/xaml/presentation';X='http://schemas.microsoft.com/winfx/2006/xaml'

def xaml(path,manager):
    parser=ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    root=ET.fromstring(path.read_text(encoding='utf-8-sig'),parser)
    namespaces={}
    for _,item in ET.iterparse(str(path),events=['start-ns']):namespaces[item[0]]=item[1]
    for prefix,uri in namespaces.items():ET.register_namespace(prefix,uri)
    prefix='lng'; uri='using:AnimeJaNaiConfEditor' if manager else 'clr-namespace:MpvNet.Windows.WPF'
    matching=[p for p,u in namespaces.items() if u==uri]
    prefix=matching[0] if matching else 'lng'
    if not matching:root.set('xmlns:'+prefix,uri)
    changed=0;unknown=[]
    for node in list(root.iter()):
        if not isinstance(node.tag,str):continue
        local=node.tag.split('}')[-1]
        for a,v in list(node.attrib.items()):
            an=a.split('}')[-1]
            if an not in ('Title','Header','Content','Text','Watermark','HintText','ToolTip','ToolTip.Tip'):continue
            if v.startswith('{'):
                if manager and v=='{Binding ProfileName}' and node.tag.endswith('Run'):
                    parents={c:p for p in root.iter() for c in p}
                    p=node
                    while p in parents and p.attrib.get('ItemsSource')!='{Binding DefaultUpscaleSlots}':p=parents[p]
                    if p.attrib.get('ItemsSource')=='{Binding DefaultUpscaleSlots}':node.set(a,'{Binding ProfileName, Converter={x:Static local:LocalizedTextConverter.Instance}}')
                m=re.fullmatch(r'\{Binding (.+), StringFormat=(Remove Chain|Remove Model|Chain|Model) \{0\}\}',v)
                if manager and m:
                    fmt=m[2]+' {0}';node.set(a,'{Binding '+m[1]+', Converter={x:Static local:LocalizedFormatConverter.Instance}, ConverterParameter='+key(fmt)+'}');changed+=1
                continue
            zh=translated(v)
            if zh!=v.strip():
                put(v,zh);node.set(a,'{'+prefix+':Text Key='+key(v)+'}');changed+=1
            elif manager and re.search('[A-Za-z]{3}',v) and v not in ('TensorRT','DirectML'):unknown.append(v)
        if local in ('TextBlock','Run','Bold','Span'):
            if node.text and node.text.strip():
                v=node.text;zh=translated(v)
                if zh!=v.strip():
                    put(v,zh);expr='{'+prefix+':Text Key='+key(v)+'}'
                    if local=='Run':node.set('Text',expr);node.text=None
                    else:
                        run=ET.Element('{'+(AV if manager else WP)+'}Run',Text=expr);node.text=None;node.insert(0,run)
                    changed+=1
                elif manager and re.search('[A-Za-z]{3}',v) and v.strip() not in ('TensorRT','DirectML','GPU','CPU','fps','animejanai.log'):unknown.append(v.strip())
            for child in list(node):
                if child.tail and child.tail.strip():
                    v=child.tail;zh=translated(v)
                    if zh!=v.strip():
                        put(v,zh);child.tail=None
                        node.insert(list(node).index(child)+1,ET.Element('{'+(AV if manager else WP)+'}Run',Text='{'+prefix+':Text Key='+key(v)+'}'));changed+=1
                    elif manager and re.search('[A-Za-z]{3}',v):unknown.append(v.strip())
    content=ET.tostring(root,encoding='unicode')
    for p,u in namespaces.items():
        decl='xmlns'+(':'+p if p else '')+'='
        if decl not in content:content=content.replace(' ',f' {decl}"{u}" ',1)
    path.write_text(content,encoding='utf-8')
    report[str(path.relative_to(ROOT))]={'expressions':changed,'unknown':unknown}
    if manager and unknown:raise RuntimeError('Untranslated manager XAML: '+repr(unknown))

def edit(path,old,new):
    s=path.read_text(encoding='utf-8-sig')
    if s.count(old)!=1:raise ValueError('Patch context '+str(path)+' '+repr(old))
    path.write_text(s.replace(old,new),encoding='utf-8')

edit(MAN/'Views/MainWindow.axaml.cs','            AvaloniaXamlLoader.Load(this);','            AvaloniaXamlLoader.Load(this);\n            LanguagePanel.Attach(this);')
edit(MAN/'ViewModels/MainWindowViewModel.cs','string.Create(ENGLISH_CULTURE, $"{chain.RifeEnsemble}")','chain.RifeEnsemble ? "yes" : "no"')
edit(MAN/'ViewModels/ComponentManagerViewModel.cs','private static string TranslateUpdaterText(string message)\n        {','private static string TranslateUpdaterText(string message)\n        {\n            if (!AnimeJaNai.Localization.InterfaceLanguage.IsChinese) return message;')
p=MAN/'Views/MainWindow.axaml.cs';s=p.read_text()
for n in ('OK','Cancel'):
    s=s.replace('FATaskDialogButton.'+n+'Button','new FATaskDialogButton(AnimeJaNai.Localization.UiText.T("'+n+'"), FATaskDialogStandardResult.'+n+')')
p.write_text(s,encoding='utf-8')
edit(PLY/'src/MpvNet/App.cs','    public string Language { get; set; } = "system";','    public string Language { get; set; } = AnimeJaNai.Localization.InterfaceLanguage.PlayerValue;')
edit(PLY/'src/MpvNet/App.cs','        if (DebugMode)\n','        Language = AnimeJaNai.Localization.InterfaceLanguage.PlayerValue;\n\n        if (DebugMode)\n')
edit(PLY/'src/MpvNet.Windows/WPF/ConfWindow.xaml.cs','        InitializeComponent();','        InitializeComponent();\n        _settings.RemoveAll(s => s.Name == "language");\n        LanguagePanel.Attach(this);')
edit(PLY/'src/MpvNet.Windows/WPF/ViewModels/NodeViewModel.cs','    public string Name => _node.Name;','    public string Name => _node.Name;\n    public string DisplayName => AnimeJaNai.Localization.UiText.T(_node.Name);')
edit(PLY/'src/MpvNet.Windows/WPF/ConfWindow.xaml','<TextBlock Text="{Binding Name}" />','<TextBlock Text="{Binding DisplayName}" />')
for name in ('StringSettingControl','OptionSettingControl','ComboBoxSettingControl'):
    p=PLY/f'src/MpvNet.Windows/WPF/Controls/{name}.xaml.cs';s=p.read_text(encoding='utf-8-sig')
    s=re.sub(r'TitleTextBox.Text = (\w+)\.Name;',r'TitleTextBox.Text = AnimeJaNai.Localization.UiText.T(\1.Name) == \1.Name ? \1.Name : AnimeJaNai.Localization.UiText.T(\1.Name) + " (" + \1.Name + ")";',s)
    s=re.sub(r'HelpTextBox.Text = (\w+)\.Help;',r'HelpTextBox.Text = AnimeJaNai.Localization.UiText.T(\1.Help);',s)
    p.write_text(s,encoding='utf-8')
edit(PLY/'src/MpvNet.Windows/Settings.cs', 'get => _text ?? Name;', 'get => AnimeJaNai.Localization.UiText.T(_text ?? Name);')
for old,new in [('return Translation._(msgId);','return AnimeJaNai.Localization.UiText.T(Translation._(msgId));'),('return Translation.GetParticularString(context, text);','return AnimeJaNai.Localization.UiText.T(Translation.GetParticularString(context, text));')]:
    edit(PLY/'src/MpvNet.Windows/WPF/WpfTranslator.cs',old,new)
xaml(MAN/'Views/MainWindow.axaml',True)
for p in (PLY/'src/MpvNet.Windows/WPF').rglob('*.xaml'):
    if p.name=='Resources.xaml' or 'HandyControl' in str(p):continue
    xaml(p,False)
resource={'translations':D,'keys':KEYS}
for target,proj in [(MAN,MAN/'AnimeJaNaiConfEditor.csproj'),(PLY/'src/MpvNet',PLY/'src/MpvNet/MpvNet.csproj')]:
    for name in ('InterfaceLanguage.cs','UiText.cs'):shutil.copy2(HERE/name,target/name)
    (target/'LanguageStrings.json').write_text(json.dumps(resource,ensure_ascii=False,indent=2),encoding='utf-8')
    edit(proj,'</Project>','<ItemGroup><EmbeddedResource Include="LanguageStrings.json" LogicalName="AnimeJaNai.LanguageStrings.json" /></ItemGroup>\n</Project>')
shutil.copy2(HERE/'ManagerLanguage.cs',MAN/'ManagerLanguage.cs')
shutil.copy2(HERE/'PlayerLanguage.cs',PLY/'src/MpvNet.Windows/WPF/PlayerLanguage.cs')
files=[MAN/'Views/MainWindow.axaml.cs',MAN/'ViewModels/MainWindowViewModel.cs',MAN/'ViewModels/ComponentManagerViewModel.cs',MAN/'Services/BenchmarkSubmission.cs']
subprocess.run(['dotnet','run','--project',str(HERE/'Rewriter.csproj'),'-c','Release','--',str(MAN/'LanguageStrings.json'),*map(str,files)],check=True)
catalog.update(D);catalog['']='Content-Type: text/plain; charset=UTF-8\nLanguage: zh_CN\nPlural-Forms: nplurals=1; plural=0;\n'
keys=sorted(catalog);a=b'';b=b'';ai=[];bi=[];offset=28+len(keys)*16
for k in keys:
    x=k.encode();y=catalog[k].encode();ai.append((len(x),len(a)+offset));bi.append((len(y),len(b)));a+=x+b'\0';b+=y+b'\0'
mo=struct.pack('<7I',0x950412de,0,len(keys),28,28+len(keys)*8,0,0)+b''.join(struct.pack('<2I',*i) for i in ai)+b''.join(struct.pack('<2I',n,pos+offset+len(a)) for n,pos in bi)+a+b
for locale in ('zh-CN','zh_CN','zh'):
    out=ROOT/'locale'/locale/'LC_MESSAGES/mpvnet.mo';out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(mo)
(ROOT/'language-coverage.json').write_text(json.dumps({'strings':len(D),'settings_help_entries':150,'xaml':report},ensure_ascii=False,indent=2),encoding='utf-8')
print('Generated',len(D),'bilingual strings',len(KEYS),'XAML resource bindings')
