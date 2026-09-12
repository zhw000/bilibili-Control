using System.Net;
using System.Net.Sockets;

namespace BiliRemote.Core;

public sealed record LocalNetworkAddress(IPAddress Address, string InterfaceName, bool HasGateway, bool IsWireless, bool IsVirtual);

public static class LocalNetwork
{
    public static IReadOnlyList<LocalNetworkAddress> ForPairing(IEnumerable<LocalNetworkAddress> addresses) => addresses
        .Where(candidate => !candidate.IsVirtual && IsLanCandidate(candidate.Address))
        .OrderByDescending(candidate => candidate.HasGateway)
        .ThenByDescending(candidate => candidate.IsWireless)
        .ThenByDescending(candidate => IsPrivate(candidate.Address))
        .ThenBy(candidate => candidate.InterfaceName, StringComparer.Ordinal)
        .ThenBy(candidate => candidate.Address.ToString(), StringComparer.Ordinal)
        .DistinctBy(candidate => candidate.Address)
        .ToArray();

    public static bool IsVirtualInterface(string name, string description)
    {
        var identity = (name + " " + description).ToLowerInvariant();
        string[] markers = ["virtual", "vmware", "tailscale", "wireguard", "tunnel", "loopback", "hyper-v", "vpn", "tap-windows", "tap-win32", "wintun", "docker", "vethernet"];
        return markers.Any(identity.Contains);
    }

    public static bool IsLanCandidate(IPAddress address)
    {
        if (address.AddressFamily != AddressFamily.InterNetwork) return false;
        var bytes = address.GetAddressBytes();
        // Exclude loopback, link-local, shared VPN/CGNAT addresses, proxy benchmark
        // ranges (including Clash/Meta fake IPs), and multicast/reserved space.
        return bytes[0] is > 0 and < 224 && bytes[0] != 127
            && !(bytes[0] == 169 && bytes[1] == 254)
            && !(bytes[0] == 100 && bytes[1] is >= 64 and <= 127)
            && !(bytes[0] == 198 && bytes[1] is 18 or 19);
    }

    private static bool IsPrivate(IPAddress address)
    {
        var bytes = address.GetAddressBytes();
        return bytes[0] == 10 || (bytes[0] == 172 && bytes[1] is >= 16 and <= 31) || (bytes[0] == 192 && bytes[1] == 168);
    }
}
