"""Final display-only localization and regression guards. No user files are accessed."""
from pathlib import Path
import json

def edit(p,old,new):
    p=Path(p);s=p.read_text(encoding='utf-8-sig')
    assert s.count(old)==1,(str(p),old)
    p.write_text(s.replace(old,new),encoding='utf-8')
p=Path('manager/AnimeJaNaiConfEditor/Views/MainWindow.axaml')
s=p.read_text(encoding='utf-8')
old='{Binding ProfileName, Converter={x:Static local:LocalizedTextConverter.Instance}}'
assert s.count(old)==2
s=s.replace(old,'{Binding ProfileName, Mode=OneWay, Converter={x:Static local:LocalizedTextConverter.Instance}}')
old='Text="{Binding CurrentSlot.ProfileName}" IsReadOnly="True"'
assert s.count(old)==1
s=s.replace(old,'Text="{Binding CurrentSlot.ProfileName, Mode=OneWay, Converter={x:Static local:LocalizedTextConverter.Instance}}" IsReadOnly="True"')
# Language is a global preference, so keep it inside Global Settings instead of
# permanently occupying the top of every Manager page.
marker='<!-- Global Settings -->'
assert s.count(marker)==1
head,tail=s.split(marker,1)
needle='<StackPanel Grid.Row="1">'
assert needle in tail
language='''
            <Border Classes="border" Margin="10,0,0,15">
              <Grid ColumnDefinitions="Auto,Auto,*">
                <TextBlock VerticalAlignment="Center" Margin="0,0,12,0">界面语言 / Interface language</TextBlock>
                <ComboBox Grid.Column="1" x:Name="InterfaceLanguageSelector" Width="200" />
                <TextBlock Grid.Column="2" x:Name="InterfaceLanguageHint" Classes="help" Margin="18,0,0,0">语言设置在重启播放器和管理器后生效。</TextBlock>
              </Grid>
            </Border>
'''
tail=tail.replace(needle,needle+language,1)
s=head+marker+tail
p.write_text(s,encoding='utf-8')
p=Path('manager/AnimeJaNaiConfEditor/ManagerLanguage.cs')
s=p.read_text(encoding='utf-8');s=s.replace('=> null;','=> Avalonia.AvaloniaProperty.UnsetValue;');p.write_text(s,encoding='utf-8')
edit('player/src/MpvNet.Windows/WPF/Controls/HyperlinkEx.cs','Inlines.Add("Manual");','Inlines.Add(AnimeJaNai.Localization.UiText.T("Manual"));')
edit('player/src/MpvNet.Windows/Resources/editor_conf.txt',
     'default = info\noption = info      Choose the best mode automatically.\noption = gpu',
     'default = gpu\noption = gpu')
p=Path('player/src/MpvNet.Windows/Settings.cs');s=p.read_text(encoding='utf-8')
a=s.index('public class OptionSettingOption');head,tail=s[:a],s[a:]
old='public string? Help { get; set; }'
assert tail.count(old)==1
tail=tail.replace(old,'string? _help;\n    public string? Help { get => AnimeJaNai.Localization.UiText.T(_help); set => _help = value; }')
p.write_text(head+tail,encoding='utf-8')
edit('player/src/MpvNet.Windows/Conf.cs','opt.Text = opt.Name + " (Default)";','opt.Text = AnimeJaNai.Localization.UiText.T(opt.Name) + AnimeJaNai.Localization.UiText.T(" (Default)");')
extra={
 'Render Options':'渲染选项','Program Behavior':'程序行为','Cache':'缓存','Demuxer':'解复用器',
 'Manual':'使用手册',' (Default)':'（默认）',
 'always use software decoding':'始终使用软件解码','enable best hw decoder':'自动选择适合的硬件解码器',
 'exactly the same as auto':'与 auto 相同','enable best hw decoder with copy-back':'自动选择硬件解码器并复制回系统内存',
 'enable any whitelisted hw decoder':'启用白名单中的硬件解码器',
 'General purpose, customizable, GPU-accelerated video output driver. It supports extended scaling methods, dithering, color management, custom shaders, HDR, and more.':'通用 GPU 加速视频输出，支持缩放滤镜、抖动、色彩管理、自定义着色器及 HDR。',
 'Experimental video renderer based on libplacebo. This supports almost the same set of features as --vo=gpu.':'基于 libplacebo 的视频渲染器，支持与 gpu 大体相同的功能，并有不同的实现和特性。',
 'Video output driver that uses the Direct3D interface.':'使用 Direct3D 接口的兼容视频输出。',
 'Static ONNX':'静态 ONNX','Static':'静态','Dynamic':'动态','Engine Type':'引擎类型',
 'none':'无','always':'始终','never':'从不','once':'一次','yes (Default)':'启用（默认）','no (Default)':'关闭（默认）','auto (Default)':'自动（默认）'
}
for name in ['manager/AnimeJaNaiConfEditor/LanguageStrings.json','player/src/MpvNet/LanguageStrings.json']:
    p=Path(name);data=json.loads(p.read_text(encoding='utf-8'));data['translations'].update(extra)
    p.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
p=Path('language-coverage.json');data=json.loads(p.read_text(encoding='utf-8'));data['strings']=len(json.loads(Path('manager/AnimeJaNaiConfEditor/LanguageStrings.json').read_text(encoding='utf-8'))['translations']);data['display_only_default_profile_binding']=True;data['invalid_video_driver_removed']=True;data['manager_language_location']='global-settings'
p.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
