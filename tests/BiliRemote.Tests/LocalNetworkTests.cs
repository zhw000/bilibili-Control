using System.Net;
using BiliRemote.Core;
using Xunit;

namespace BiliRemote.Tests;

public sealed class LocalNetworkTests
{
    [Fact] public void SelectsWifiInsteadOfMetaTailscaleAndVmware()
    {
        LocalNetworkAddress[] captured = [
            new(IPAddress.Parse("198.18.0.1"), "Meta", true, false, true),
            new(IPAddress.Parse("100.84.20.121"), "Tailscale", true, false, true),
            new(IPAddress.Parse("192.168.109.1"), "VMware", false, false, true),
            new(IPAddress.Parse("192.168.1.253"), "WLAN 2", true, true, false)
        ];
        Assert.Equal("192.168.1.253", Assert.Single(LocalNetwork.ForPairing(captured)).Address.ToString());
        Assert.Equal(LocalNetwork.ForPairing(captured), LocalNetwork.ForPairing(captured.Reverse()));
    }

    [Theory]
    [InlineData("198.18.0.1", false)] [InlineData("198.19.255.1", false)]
    [InlineData("100.84.20.121", false)] [InlineData("127.0.0.1", false)]
    [InlineData("169.254.1.1", false)] [InlineData("::1", false)]
    [InlineData("192.168.1.253", true)] [InlineData("10.0.0.8", true)]
    [InlineData("172.20.10.2", true)]
    public void FiltersAddressesUnavailableToLocalPhones(string value, bool expected) =>
        Assert.Equal(expected, LocalNetwork.IsLanCandidate(IPAddress.Parse(value)));

    [Theory]
    [InlineData("Meta", "Meta Tunnel", true)]
    [InlineData("Ethernet", "TAP-Windows Adapter V9", true)]
    [InlineData("WLAN 2", "Intel(R) Wi-Fi 6E AX210 160MHz", false)]
    [InlineData("Ethernet", "Realtek PCIe GbE Family Controller", false)]
    public void DetectsVirtualAdapters(string name, string description, bool expected) =>
        Assert.Equal(expected, LocalNetwork.IsVirtualInterface(name, description));
}
