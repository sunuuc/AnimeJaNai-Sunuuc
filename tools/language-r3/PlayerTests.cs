using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using AnimeJaNai.Localization;
using MpvNet.Windows.WPF;
using MpvNet.Windows.UI;
class Test
{
 [STAThread] static void Main(string[] args)
 {
    var root=Path.GetFullPath(args[0]);Directory.CreateDirectory(root);
    var config=Path.Combine(root,"isolated-player");Directory.CreateDirectory(config);
    Environment.SetEnvironmentVariable("MPVNET_HOME",config);
    InterfaceLanguage.SettingsPath=Path.Combine(config,"interface-language.json");
    MpvNet.Translator.Current=new WpfTranslator();
    WpfApplication.Init();Theme.Init();
    foreach(var lang in new[]{"zh-CN","en","system"})
    {
       InterfaceLanguage.Save(lang);InterfaceLanguage.Reload();bool zh=InterfaceLanguage.IsChinese;
       MpvNet.Global.App.Language=InterfaceLanguage.PlayerValue;
       var tr=new WpfTranslator();
       Check(tr.Gettext("Settings")== (zh?"设置":"Settings"),"embedded player resource "+lang);
       var window=new ConfWindow{Width=1040,Height=760};
       window.Show();window.UpdateLayout();
       Check(window.Title==(zh?"设置":"Config Editor"),"actual settings window title "+lang);
       var dock=(DockPanel)window.Content;var top=(StackPanel)dock.Children[0];var row=(StackPanel)top.Children[0];var selector=(ComboBox)row.Children[1];
       Check(selector.SelectedIndex==Array.IndexOf(InterfaceLanguage.Choices,lang),"player selector "+lang);
       var bitmap=new RenderTargetBitmap(1040,760,96,96,PixelFormats.Pbgra32);bitmap.Render(window);
       var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
       using(var stream=File.Create(Path.Combine(root,"player-"+lang+".png")))encoder.Save(stream);
       selector.SelectedIndex=zh?1:0;
       Check(InterfaceLanguage.Read()==(zh?"en":"zh-CN"),"player saves shared preference "+lang);
       Check(!File.Exists(Path.Combine(config,"mpv.conf"))&&!File.Exists(Path.Combine(config,"mpvnet.conf")),"language choice leaves playback configs untouched "+lang);
       window.Close();
    }
    Console.WriteLine("PASS Player language suite");
 }
 static void Check(bool ok,string what){if(!ok)throw new Exception(what);Console.WriteLine("PASS "+what);}
}
