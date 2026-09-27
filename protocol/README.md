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
| `creator.videos` | `creatorId`, `order: newest / oldest / popular`, optional `keyword`, `page` | Paged videos |
| `creator.profile` | `creatorId` | Creator identity, description, verified label, followers, following, videoCount, likes, level |
| `creator.collections` | `creatorId`, `page` | Paged collections |
| `collection.videos` | `url`, `page` | Paged videos |
| `favorites.folders` | `{}` | `{accountName,items:[{id,title,count}]}` for Chrome's logged-in account |
| `favorites.videos` | `folderId`, optional `keyword`, `page` | Paged video favorites; unavailable items have `unavailableReason` |
| `comments.list` | `bvid`, `order: hot / newest`, `page`, optional `root` | `{bvid,items,total,page,totalPages,nextPage?}`; string comment IDs, plain message, author, timestamp, likes and reply previews |
| `comments.add` | `bvid`, `message` (1–1000 Unicode code points), optional `root,parent` | `{bvid,message,comment?}`; explicit user submission only; does not change playback |
| `tabs.list` | `{}` | `{id,title,url,selected}[]` |
| `tabs.select` | `tabId` | Player state; stops previous queue |
| `player.open` | `video` | Replaces queue with this video |
| `player.related` | `bvid` | `{bvid,items: VideoItem[]}` from the selected playback tab's recommendations; never navigates or changes playback |
| `player.command` | `action`, optional `value` | Player state |
| `queue.start` | `kind: manual / creator / collection / favorites`, optional `items / creatorId / url / folderId / keyword`, `order` | Queue snapshot |
| `queue.previous / queue.next / queue.resume / queue.stop` | `{}` | Queue snapshot |
| `queue.select` | `bvid` | Starts an already-loaded queue item, preserving source and pending pages; stale BVID returns `queue_changed` |
| `system.volume` | `value: 0...1` | System volume |
| `system.mute` | `value: boolean` | System volume |

Player actions: `play`, `pause`, `seek` (absolute seconds), `seekBy` (relative seconds), `volume` (0...1), `mute` (boolean), `rate` (0.5...2), `danmaku` (boolean), `fullscreen` (boolean). Time is expressed in seconds throughout. Queue navigation moves between videos; each video's parts play in order first. A queue-owned playback ID accompanies events so stale/duplicate end events cannot advance a new video.

Paged results contain `items`, `page`, `totalPages`, optional `total`, and optional `nextPage`. `page` is a logical page: oldest-first reverses the website's page order and each page's items. Video objects contain `bvid`, `title`, `url`, optional `cover`, `duration`, `creatorId`, `creatorName`, and `unavailableReason`. Creator objects contain `id,name,url,avatar?,description?`; collection objects contain `id,title,url,cover?,count?`.

Player state contains `bvid,title,url,currentTime,duration,paused,ended,part,partCount,volume,muted,rate,danmaku,fullscreen,playbackId?,errorCode?,errorMessage?,cover?,quality?`. System volume contains `value,muted,deviceName,available`. Queue state contains `source?,items,index,nextPage?,active,canResume,message?,playbackId?`.

Version 0.4.0 adds `player.command` action `quality`, with a string `value` from the player's offered quality IDs and required `bvid` and `part` identifying the selected video. The optional `quality` state is `{currentId?,currentLabel?,options:[{id,label,badge?,disabled}],width?,height?}`. IDs are opaque website values, including `"0"` for automatic; dimensions describe the currently decoded frame and may lag a switch. The extension uses the existing player's DOM menu, clicks once, and waits up to eight seconds for the selected tier to match. It rejects stale video/part requests, missing or disabled options and simultaneous switches. It does not set stream URLs, bypass account access, navigate a new tab, or claim success when the site has not confirmed the selection. Badge text alone does not establish whether an account may select a tier. Older hosts omit quality state; the iPhone shows upgrade instructions.

The iOS playback page contains one vertical scroll view. Creator/collection or multi-item manual queues appear inline; a single manually opened video displays recommendations instead. Results carry the requested BVID so responses from an earlier video cannot replace the new list. Selecting a recommendation starts that single video; it does not opt into automatic recommendation playback.

## Browser adaptation

Search, creator videos and collections run serially in one inactive, muted catalog tab, separate from the fixed playback target. Those adapters read rendered page elements and pagination. Creator profiles, favorites and comments use fixed `api.bilibili.com` endpoints from the extension service worker with Chrome's session. The extension only reads the `bili_jct` cookie locally for a comment POST; browser cookies and CSRF values are never exported. No caller-controlled API URLs are accepted. Adapter failures are surfaced explicitly; they are not silently converted into empty successful results. Tests use DOM and API fixtures; logged-in website compatibility must be checked separately.

Comment POSTs are never automatically retried. The existing request ledger also deduplicates `comments.add` within its retention window. A lost POST response returns `comment_uncertain`; transport loss after submission is also displayed as an unconfirmed result. Clients retain the draft and instruct the user to read comments before resubmitting. Hot comments deduplicate pinned entries, replies paginate by string root ID, and reads remain bound to the requested BVID even if the player changes.

Cover extraction prefers lazy data attributes and picture sources over placeholders, strips CDN resize suffixes, preserves known covers during deduplication, and gives initial DOM hydration a bounded wait. Related-video reads supplement missing covers from the first-party related API and revalidate the playback target. iOS retries missing related metadata twice and failed image downloads twice, with a Bilibili Referer, normalized HTTPS URLs and an in-memory thumbnail cache.

## Siri and Apple Watch

The iOS App Intent exposes play, pause, previous/next, ±10 seconds and ±10% player volume. Each invocation opens its own certificate-pinned, short-lived connection using the existing Keychain pairing, checks a fresh snapshot, and sends its command once. It never starts the UI socket or queues offline actions.

The watchOS 10 companion receives only a compact `WatchPlaybackState` via WatchConnectivity application context. Foreground watch refreshes and button presses use interactive messages `{id: UUID, action: RemoteAction}` with replies containing encoded state or an error. iPhone reconnects to the computer on demand; duplicate message IDs share their original result (up to 32 completed messages), and IDs reused for a different action fail. Only the fixed action enum is accepted. Credentials and certificate material never leave iPhone. Reachability, last synchronization time, timeouts and errors appear on the watch. The companion depends on iPhone connectivity and is not a standalone LAN client.

An end-event capture listener prevents the site's own end listeners from racing the host queue. Only a recognizable next-video autoplay checkbox is temporarily disabled and restored on release; the player's auto-start preference is never changed. The extension handles intermediate parts; the host handles the final part. Manual navigation to another video or part ends queue ownership and cancels pending playback for the previous video. Restarting the host restores metadata and progress but does not start playback.

From extension 0.4.1, remote fullscreen uses the site's web fullscreen only, preserving browser tabs and window controls. Escape or the website exit control returns to the page without leaving another browser fullscreen layer. Player state also recognizes native player fullscreen, and an explicit fullscreen-off command exits it. Unsupported players return an error instead of receiving a CSS fullscreen overlay.
