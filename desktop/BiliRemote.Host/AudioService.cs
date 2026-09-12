using BiliRemote.Core;
using NAudio.CoreAudioApi;

namespace BiliRemote.Host;
public sealed class AudioService:IDisposable
{
    private readonly MMDeviceEnumerator enumerator=new();
    private MMDevice? device;
    private readonly object gate=new();
    public SystemVolume State {get;private set;}=new(0,false,"未找到输出设备",false);
    public SystemVolume Refresh()
    {
        lock(gate)
        {
            try
            {
                using var current=enumerator.GetDefaultAudioEndpoint(DataFlow.Render,Role.Multimedia);
                if(device?.ID!=current.ID){device?.Dispose();device=enumerator.GetDevice(current.ID);}
                State=new(device.AudioEndpointVolume.MasterVolumeLevelScalar,device.AudioEndpointVolume.Mute,device.FriendlyName);
            }
            catch(Exception){State=new(0,false,"未找到输出设备",false);}
            return State;
        }
    }
    public SystemVolume Set(double? value=null,bool? mute=null)
    {
        lock(gate)
        {
            Refresh();if(device==null||!State.Available)throw new RemoteException("audio_unavailable","Windows 当前没有可用的音频输出设备");
            if(value is double v)device.AudioEndpointVolume.MasterVolumeLevelScalar=(float)v;
            if(mute is bool m)device.AudioEndpointVolume.Mute=m;
            return Refresh();
        }
    }
    public void Dispose(){device?.Dispose();enumerator.Dispose();}
}
