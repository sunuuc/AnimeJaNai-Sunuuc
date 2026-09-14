using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using AnimeJaNai.Localization;
using MpvNet.Windows.WPF;
class Test
{
 [STAThread] static void Main(string[] args)
 {
    var root=Path.GetFullPath(args[0]);Directory.CreateDirectory(root);
    InterfaceLanguage.SettingsPath=Path.Combine(root,"player-preference.json");
    var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};
    foreach(var lang in new[]{"zh-CN","en","system"})
    {
       InterfaceLanguage.Save(lang);InterfaceLanguage.Reload();bool zh=InterfaceLanguage.IsChinese;
       MpvNet.Global.App.Language=InterfaceLanguage.PlayerValue;
       var tr=new WpfTranslator();
       Check(tr.Gettext("Settings")== (zh?"设置":"Settings"),"embedded player resource "+lang);
       var window=new Window{Content=new Grid(),Width=850,Height=300,Background=Brushes.White};
       LanguagePanel.Attach(window);window.Show();window.UpdateLayout();
       var dock=(DockPanel)window.Content;var top=(StackPanel)dock.Children[0];var row=(StackPanel)top.Children[0];var selector=(ComboBox)row.Children[1];
       Check(selector.SelectedIndex==Array.IndexOf(InterfaceLanguage.Choices,lang),"player selector "+lang);
       selector.SelectedIndex=zh?1:0;
       Check(InterfaceLanguage.Read()==(zh?"en":"zh-CN"),"player saves shared preference "+lang);
       var bitmap=new RenderTargetBitmap(850,300,96,96,PixelFormats.Pbgra32);bitmap.Render(window);
       var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
       using(var stream=File.Create(Path.Combine(root,"player-"+lang+".png")))encoder.Save(stream);
       window.Close();
    }
    Console.WriteLine("PASS Player language suite");
 }
 static void Check(bool ok,string what){if(!ok)throw new Exception(what);Console.WriteLine("PASS "+what);}
}
