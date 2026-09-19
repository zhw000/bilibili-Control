"""Validate a device IPA independently of Xcode build success."""
import plistlib
import json
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
    assert info.get("CFBundleDevelopmentRegion") == "zh-Hans", "Siri phrases require the correct development language"
    assert "zh-Hans" in info.get("CFBundleLocalizations", []), "Chinese Siri localization must be declared"
    metadata_path = infos[0][:-len("Info.plist")] + "Metadata.appintents/extract.actionsdata"
    metadata = json.loads(archive.read(metadata_path))
    assert metadata.get("autoShortcutProviderMangledName"), "App Shortcuts provider was not extracted"
    intent = metadata.get("actions", {}).get("PlaybackIntent")
    assert intent and intent.get("isDiscoverable"), "Playback intent must be discoverable"
    shortcuts = [item for item in metadata.get("autoShortcuts", []) if item.get("actionIdentifier") == "PlaybackIntent"]
    assert len(shortcuts) == 1 and len(shortcuts[0].get("phraseTemplates", [])) >= 2, "Siri invocation phrases missing"
    actions = next(item for item in metadata["enums"] if item["identifier"] == "SiriPlaybackAction")
    assert {item["identifier"] for item in actions["cases"]} == {"play", "pause", "next", "previous", "forward", "backward", "volumeUp", "volumeDown"}
    nlu_path = infos[0][:-len("Info.plist")] + "Metadata.appintents/nlu/nlu.lzfse"
    assert archive.read(nlu_path), "Compiled Siri phrase assets missing; inspect AppIntentsSSUTraining"
    print("Verified Siri provider, compiled Chinese phrases, and all eight playback actions")
    watches = [name for name in archive.namelist() if name.startswith(infos[0][:-len("Info.plist")] + "Watch/") and name.endswith(".app/Info.plist")]
    assert len(watches) == 1, "Expected the embedded Apple Watch companion app"
    watch = plistlib.loads(archive.read(watches[0]))
    assert "WatchOS" in watch["CFBundleSupportedPlatforms"], "Expected a device watchOS app"
    assert watch.get("WKApplication"), "Expected a single-target watchOS application"
    assert watch["WKCompanionAppBundleIdentifier"] == info["CFBundleIdentifier"], "Watch companion ID must match iPhone app"
    assert watch["CFBundleIdentifier"].startswith(info["CFBundleIdentifier"] + ".")
    assert watch["CFBundleVersion"] == info["CFBundleVersion"]
    assert watch["MinimumOSVersion"] == "10.0"
    watch_executable = watches[0][:-len("Info.plist")] + watch["CFBundleExecutable"]
    assert archive.read(watch_executable), "Watch executable missing"
    print(f"Verified embedded Watch companion: {watch['CFBundleIdentifier']}, watchOS {watch['MinimumOSVersion']}+")
    print(f"Verified device IPA: {info['CFBundleIdentifier']} ({info['CFBundleShortVersionString']}), arm64, iOS {info['MinimumOSVersion']}+")
