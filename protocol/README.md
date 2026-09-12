# Bili Remote protocol v1

The iPhone talks exclusively to the paired Windows host. The Chrome extension uses Chrome Native Messaging and a current-user-only Windows named pipe. Neither endpoint accepts arbitrary JavaScript, shell commands, arbitrary URLs, or arbitrary file access.

## Pairing and transport

The host listens on its selected IPv4 interface, default port `33391`, using TLS. The QR link is `biliremote://pair?data=<base64url JSON>`. Its descriptor contains `version`, `host`, `port`, `certificateSha256`, and a random 256-bit `pairingToken`. A QR token expires after 120 seconds and can be consumed once. An app pins the complete SHA-256 certificate fingerprint scanned from the host; certificate validity and server-auth usage are also checked. It does not install a system trust anchor.

`POST /api/v1/pair` accepts `{pairingToken, deviceName}` and returns `{deviceId, accessToken, computerName}`. The permanent token is stored in the iOS Keychain; only its hash is retained in the host's DPAPI-protected device database. `WSS /api/v1/ws` requires `Authorization: Bearer <accessToken>`. Revoking a device invalidates future connections and aborts its existing connections.

## Envelopes

WebSocket JSON requests use UTF-8 **text** frames. Binary request frames are rejected. Chrome's stdin/stdout transport separately uses length-prefixed UTF-8 bytes.

Request: `{ "v": 1, "id": "unique string", "method": "player.command", "params": { "action": "seekBy", "value": 10 } }`

Success: `{ "v": 1, "id": "same string", "ok": true, "result": {} }`

Failure: `{ "v": 1, "id": "same string", "ok": false, "error": { "code": "autoplay_blocked", "message": "Chinese user-facing explanation" } }`

Event: `{ "v": 1, "event": "snapshot", "data": { "computerName": "PC", "browserConnected": true, "player": {}, "queue": {}, "systemVolume": {} } }`

The host sends a complete snapshot immediately after connecting and when state changes. Requests are deduplicated by device and ID across socket reconnects (512 completed requests retained). An ID reused with different parameters is rejected. Clients discard pending requests when disconnected and never automatically replay playback commands. All message bodies are limited to 1 MiB. Missing optional fields are omitted rather than required to be `null`.

## Methods

| Method | Parameters | Result |
|---|---|---|
| `snapshot` | `{}` | Full state |
| `search` | `query`, `kind: videos / creators`, `page` | Paged videos or creators |
| `creator.videos` | `creatorId`, `order: newest / oldest`, `page` | Paged videos |
| `creator.collections` | `creatorId`, `page` | Paged collections |
| `collection.videos` | `url`, `page` | Paged videos |
| `tabs.list` | `{}` | `{id,title,url,selected}[]` |
| `tabs.select` | `tabId` | Player state; stops previous queue |
| `player.open` | `video` | Replaces queue with this video |
| `player.command` | `action`, optional `value` | Player state |
| `queue.start` | `kind: manual / creator / collection`, optional `items / creatorId / url`, `order` | Queue snapshot |
| `queue.previous / queue.next / queue.resume / queue.stop` | `{}` | Queue snapshot |
| `system.volume` | `value: 0...1` | System volume |
| `system.mute` | `value: boolean` | System volume |

Player actions: `play`, `pause`, `seek` (absolute seconds), `seekBy` (relative seconds), `volume` (0...1), `mute` (boolean), `rate` (0.5...2), `danmaku` (boolean), `fullscreen` (boolean). Time is expressed in seconds throughout. Queue navigation moves between videos; each video's parts play in order first. A queue-owned playback ID accompanies events so stale/duplicate end events cannot advance a new video.

Paged results contain `items`, `page`, `totalPages`, optional `total`, and optional `nextPage`. `page` is a logical page: oldest-first reverses the website's page order and each page's items. Video objects contain `bvid`, `title`, `url`, optional `cover`, `duration`, `creatorId`, `creatorName`, and `unavailableReason`. Creator objects contain `id,name,url,avatar?,description?`; collection objects contain `id,title,url,cover?,count?`.

Player state contains `bvid,title,url,currentTime,duration,paused,ended,part,partCount,volume,muted,rate,danmaku,fullscreen,playbackId?,errorCode?,errorMessage?`. System volume contains `value,muted,deviceName,available`. Queue state contains `source?,items,index,nextPage?,active,canResume,message?,playbackId?`.

## Browser adaptation

Directory reads run serially in one inactive, muted catalog tab, separate from the fixed playback target. The adapter reads rendered page elements and pagination. Browser cookies are not exported. Adapter failures are surfaced explicitly; they are not silently converted into empty successful results. Tests use DOM fixtures; live website compatibility must be checked separately.

An end-event capture listener prevents the site's own end listeners from racing the host queue. When a recognizable autoplay checkbox is present, its prior value is restored on release. The extension handles intermediate parts; the host handles the final part. Manual navigation to another video ends queue ownership. Restarting the host restores metadata and progress but does not start playback.
