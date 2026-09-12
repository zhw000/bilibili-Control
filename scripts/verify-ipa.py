"""Validate a device IPA independently of Xcode build success."""
import plistlib
import struct
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    infos = [name for name in archive.namelist() if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
    assert len(infos) == 1, "Expected exactly one iOS application"
    info = plistlib.loads(archive.read(infos[0]))
    assert "iPhoneOS" in info["CFBundleSupportedPlatforms"], "Simulator app cannot be signed for a device"
    executable = infos[0][:-len("Info.plist")] + info["CFBundleExecutable"]
    header = archive.read(executable)[:8]
    magic, cpu = struct.unpack("<II", header)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C, "Expected an arm64 Mach-O executable"
    assert info["NSLocalNetworkUsageDescription"] and info["NSCameraUsageDescription"]
    assert info.get("MinimumOSVersion") == "17.0", info.get("MinimumOSVersion")
    assert not info.get("UIBackgroundModes"), "Remote playback must not require fake background audio"
    print(f"Verified device IPA: {info['CFBundleIdentifier']} ({info['CFBundleShortVersionString']}), arm64, iOS {info['MinimumOSVersion']}+")
