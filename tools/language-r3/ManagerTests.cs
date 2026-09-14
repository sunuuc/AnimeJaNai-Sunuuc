using AnimeJaNai.Localization;
using AnimeJaNaiConfEditor;
using AnimeJaNaiConfEditor.Views;
using AnimeJaNaiConfEditor.ViewModels;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.LogicalTree;
using Avalonia.VisualTree;
using Avalonia.Headless;
using Avalonia.Threading;
using Avalonia.Media.Imaging;
using ReactiveUI.Avalonia;
string evidence=Path.GetFullPath(args[0]);Directory.CreateDirectory(evidence);
string dir=Path.Combine(evidence,"preference-test");Directory.CreateDirectory(dir);
InterfaceLanguage.SettingsPath=Path.Combine(dir,"interface-language.json");
void Check(bool ok,string what){if(!ok)throw new Exception(what);Console.WriteLine("PASS "+what);}
Check(InterfaceLanguage.Read()=="zh-CN","Chinese default without setting");
Check(InterfaceLanguage.Resolve("system","zh-TW")=="zh-CN"&&InterfaceLanguage.Resolve("system","en-US")=="en","system language resolution");
File.WriteAllText(InterfaceLanguage.SettingsPath,"{broken");
Check(InterfaceLanguage.Read()=="zh-CN","corrupt preference falls back to Chinese");
InterfaceLanguage.Save("en");Check(InterfaceLanguage.Read()=="en","persist English");
bool rejected=false;try{InterfaceLanguage.Save("bad");}catch(ArgumentException){rejected=true;}
Check(rejected&&InterfaceLanguage.Read()=="en","reject invalid selection without changing stored value");
using(var locked=new FileStream(InterfaceLanguage.SettingsPath,FileMode.Open,FileAccess.Read,FileShare.Read))
{rejected=false;try{InterfaceLanguage.Save("zh-CN");}catch(IOException){rejected=true;}Check(rejected,"locked preference refuses replacement");}
Check(InterfaceLanguage.Read()=="en"&&!Directory.EnumerateFiles(dir,"*.tmp").Any(),"failed save retains old preference and removes temporary file");
AppBuilder.Configure<AnimeJaNaiConfEditor.App>().UseHeadless(new AvaloniaHeadlessPlatformOptions{UseHeadlessDrawing=false}).UseSkia().UseReactiveUI(_=>{}).SetupWithoutStarting();
foreach(string language in new[]{"zh-CN","en","system"})
{
    InterfaceLanguage.Save(language);InterfaceLanguage.Reload();bool zh=InterfaceLanguage.IsChinese;
    Check(UiText.T("Profiles")== (zh?"配置方案":"Profiles"),"embedded resource "+language);
    Check(UiText.F($"Remove Chain {7}")==(zh?"移除处理链 7":"Remove Chain 7"),"dynamic format "+language);
    var w=new MainWindow {Width=1100,Height=800};w.Show();Dispatcher.UIThread.RunJobs();
    var logical=w.GetLogicalDescendants().OfType<Control>().ToArray();
    var tabs=logical.OfType<TabItem>().Select(t=>t.Header?.ToString()).ToArray();
    Check(tabs.Contains(zh?"配置方案":"Profiles")&&tabs.Contains(zh?"组件":"Components"),"constructed tab headers "+language);
    var selector=w.GetVisualDescendants().OfType<ComboBox>().Single(c=>c.Name=="InterfaceLanguageSelector");
    Check(selector.SelectedIndex==Array.IndexOf(InterfaceLanguage.Choices,language),"selector reflects persisted setting "+language);
    selector.SelectedIndex=zh?1:0;Dispatcher.UIThread.RunJobs();
    Check(InterfaceLanguage.Read()==(zh?"en":"zh-CN"),"selector saves correct stable language ID "+language);
    Check(InterfaceLanguage.IsChinese==zh,"selection does not partially relocalize current window "+language);
    using(var bitmap=new RenderTargetBitmap(new PixelSize(1100,800))){bitmap.Render(w);bitmap.Save(Path.Combine(evidence,"manager-"+language+".png"));}
    File.WriteAllText(Path.Combine(evidence,"manager-"+language+".txt"),string.Join("\n",logical.Select(c=>c switch{TextBlock t=>t.Text??t.Inlines?.Text,ContentControl t=>t.Content is string s?s:null,_=>null}).Where(s=>s!=null)));
    w.Close();Dispatcher.UIThread.RunJobs();
}
Console.WriteLine("PASS Manager language suite");
