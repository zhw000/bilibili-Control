namespace BiliRemote.Host;
public partial class App : System.Windows.Application
{
    private RemoteServer? server;
    protected override async void OnStartup(System.Windows.StartupEventArgs e)
    {
        base.OnStartup(e);
        try
        {
            server = new RemoteServer(); await server.Start();
            if (!e.Args.Contains("--headless")) { var window = new MainWindow(server); MainWindow = window; window.Show(); }
        }
        catch (Exception ex)
        {
            if (!e.Args.Contains("--headless")) System.Windows.MessageBox.Show("启动失败：" + ex.Message, "哔哩遥控");
            else { Directory.CreateDirectory(BiliRemote.Desktop.DesktopPaths.DataDirectory); File.WriteAllText(Path.Combine(BiliRemote.Desktop.DesktopPaths.DataDirectory,"startup-error.txt"),ex.ToString()); }
            Shutdown(1);
        }
    }
    protected override void OnExit(System.Windows.ExitEventArgs e) { server?.Dispose(); base.OnExit(e); }
}
