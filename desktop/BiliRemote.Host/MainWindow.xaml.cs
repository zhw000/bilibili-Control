using System.Diagnostics;
using System.IO;
using System.Windows.Media.Imaging;
using QRCoder;

namespace BiliRemote.Host;
public partial class MainWindow:System.Windows.Window
{
    private readonly RemoteServer server;
    private readonly System.Windows.Forms.NotifyIcon tray;
    private readonly System.Drawing.Icon appIcon;
    private string pairingLink="";
    private bool quitting;
    public MainWindow(RemoteServer server)
    {
        InitializeComponent();this.server=server;
        var iconUri = new Uri("pack://application:,,,/Assets/AppIcon.ico");
        Icon = BitmapFrame.Create(iconUri);
        using (var stream = System.Windows.Application.GetResourceStream(iconUri).Stream)
        using (var resourceIcon = new System.Drawing.Icon(stream, System.Windows.Forms.SystemInformation.SmallIconSize))
            appIcon = (System.Drawing.Icon)resourceIcon.Clone();
        tray=new(){Icon=appIcon,Visible=true,Text="哔哩遥控 · 电脑助手"};
        var menu=new System.Windows.Forms.ContextMenuStrip();menu.Items.Add("打开电脑助手",null,(_,_)=>Dispatcher.Invoke(()=>{Show();Activate();}));menu.Items.Add("退出",null,(_,_)=>Dispatcher.Invoke(()=>Quit(null,null!)));tray.ContextMenuStrip=menu;tray.DoubleClick+=(_,_)=>Dispatcher.Invoke(()=>{Show();Activate();});
        Closing+=(_,eventArgs)=>{if(!quitting){eventArgs.Cancel=true;Hide();}};
        server.Changed+=()=>Dispatcher.BeginInvoke(UpdateStatus);UpdateStatus();RefreshPairing(null,null!);
    }
    private void UpdateStatus(){StatusText.Text=(server.BrowserConnected?"● Chrome 已连接":"○ 等待 Chrome 扩展连接")+$"    ·    {server.PhoneCount} 台手机在线"+(server.Security.IdentityRenewed?"    ·    证书已更新，请重新扫码配对":"");AddressText.Text=$"{Environment.MachineName}  ·  {server.Address}:{server.Port}";var selected=(DevicesList.SelectedItem as PairedDevice)?.Id;DevicesList.ItemsSource=server.Security.Devices;DevicesList.SelectedItem=server.Security.Devices.FirstOrDefault(d=>d.Id==selected);}
    private void RefreshPairing(object? sender,System.Windows.RoutedEventArgs e)
    {
        pairingLink=SecurityStore.Link(server.Security.Begin(server.Address,server.Port));
        using var generator=new QRCodeGenerator();using var code=generator.CreateQrCode(pairingLink,QRCodeGenerator.ECCLevel.M);using var png=new PngByteQRCode(code);using var stream=new MemoryStream(png.GetGraphic(6));var bitmap=new BitmapImage();bitmap.BeginInit();bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.StreamSource=stream;bitmap.EndInit();QrImage.Source=bitmap;
    }
    private void CopyPairing(object? sender,System.Windows.RoutedEventArgs e)=>System.Windows.Clipboard.SetText(pairingLink);
    private void RevokeDevice(object? sender,System.Windows.RoutedEventArgs e){if(DevicesList.SelectedItem is PairedDevice device)server.Revoke(device.Id);}
    private void AllowFirewall(object? sender,System.Windows.RoutedEventArgs e)
    {
        try{Process.Start(new ProcessStartInfo("netsh",$"advfirewall firewall add rule name=\"Bili Remote LAN\" dir=in action=allow program=\"{Environment.ProcessPath}\" protocol=TCP localport={server.Port} profile=private remoteip=LocalSubnet"){UseShellExecute=true,Verb="runas",WindowStyle=ProcessWindowStyle.Hidden});}
        catch(System.ComponentModel.Win32Exception){System.Windows.MessageBox.Show("未修改防火墙。需要允许专用网络连接后，手机才能连接电脑。","哔哩遥控");}
    }
    private void OpenExtension(object? sender,System.Windows.RoutedEventArgs e){var path=Path.Combine(AppContext.BaseDirectory,"extension");if(Directory.Exists(path))Process.Start(new ProcessStartInfo("explorer.exe",$"\"{path}\""){UseShellExecute=true});else System.Windows.MessageBox.Show("开发模式下扩展位于项目的 extension/dist 文件夹。","哔哩遥控");}
    private void Quit(object? sender,System.Windows.RoutedEventArgs e){quitting=true;tray.Dispose();appIcon.Dispose();System.Windows.Application.Current.Shutdown();}
}
