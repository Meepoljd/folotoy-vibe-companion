**English** · [简体中文](DESIGN.zh_CN.md)

# Vibe Companion design contract

This document defines the product's interaction, visual and engineering
conventions. Use it when adding a feature or reviewing a change. The
[implementation record](implementation.md) contains historical experiments and
exact validation results; those checkpoints do not override this contract.
[AGENTS.md](../../AGENTS.md) governs repository workflows and the BSP boundary.

## 1. Product priorities

Vibe Companion is a **voice-input companion**, with useful information and
small applications around that core. Priorities, in order:

1. Reliable, quickly accessible voice input and deliberate Enter actions.
2. Legible information and predictable three-button operation.
3. Stable operation on the ESP32-C3's internal RAM.
4. Low energy use, without trading away voice reliability or stable playback.
5. Additional applications that fit the same interaction model.

Do not add an introductory showcase or launcher before Home. Do not implement
an application on top of the upstream hardware-test UI. Reuse the official BSP
and isolated library logic, and keep the product interface in `main/vibe/`.

## 2. The device's mental model

Home is the desktop: a compact voice status area remains above one active
content module. The default module displays weather. Pomodoro and radio replace
that module; **weather, Pomodoro and radio are mutually exclusive**.

Voice is an interruptible service available from Home in all three modules.
Radio is silent during voice input. Settings, provisioning and confirmation
screens are separate pages with their own key meanings; they do not inherit
Home's voice/Enter bindings.

A timer's state is independent of page navigation. Entering settings or an exit
confirmation does not pause it. Moving from an active or paused Pomodoro to
radio requires a direct confirmation that ends the timer before starting radio.
Future modules must define their own entry, active, interruption and exit states.

## 3. Physical keys and gestures

From top to bottom the physical keys are **UP, DOWN, SETTINGS**. DOWN is physically
in the middle. The BSP calls SETTINGS `OK`; product text calls it SETTINGS.
Never refer to an unexplained middle/bottom key in user-facing instructions.

| Context | UP | DOWN | SETTINGS |
| --- | --- | --- | --- |
| Home, default module | Hold: voice; release: finish | Tap: Enter; hold: Pomodoro ready | Tap: next weather page; hold: functions |
| Pomodoro ready | Hold: voice | Tap: Enter; hold: exit immediately | Tap: start; hold: functions |
| Pomodoro running | Hold: voice | Tap: Enter; hold: exit confirmation | Tap: pause; hold: functions |
| Pomodoro paused | Hold: voice | Tap: Enter; hold: exit confirmation | Tap: resume; hold: functions |
| Next phase ready | Hold: voice | Tap: Enter; hold: exit immediately | Tap: start next phase; hold: functions |
| Radio | Hold: voice, release: resume previous listening intent | Tap: Enter; hold: exit confirmation | Tap: next selected station; hold: functions |
| Timer exit/switch confirmation | Tap: cancel | Tap: exit or switch | No action |
| Radio exit confirmation | Tap: cancel, keep listening intent | Tap: stop and exit | No action |
| Functions / settings navigation | Tap: previous item | Tap: next item | Tap: enter/edit; hold: back |
| Editing a setting | Tap: increase/previous choice | Tap: decrease/next choice | Tap: finish; hold: leave editing |

A press-hold-release is **one gesture**. A long press suppresses the short action
on release. Long DOWN must never send an additional Enter or immediately leave
a page it just opened. Two short presses remain two deliberate actions; there
is no double-click vocabulary in this version. During recording, other Home
actions are suppressed until UP is released.

Home's long DOWN is an application shortcut: enter Pomodoro from the default
module; exit the current application otherwise. Its rail icon changes as soon
as the ready screen is entered. SETTINGS supplies the active application's
primary short action. Radio dedicates short SETTINGS to next station and long
DOWN to open exit confirmation. Keep the stream and current station unchanged
while the confirmation is visible and when UP cancels. Only short DOWN confirms
the stop and exit; the entry hold's release cannot confirm. Use the same narrow
key rail and direct choices as the timer's exit page. Functions contains only device settings and radio, with
no manual pause/resume entry; automatic voice preemption and resumption remain.

## 4. Pomodoro flow

```mermaid
stateDiagram-v2
    Default --> Ready: Hold DOWN
    Ready --> Running: Tap SETTINGS
    Running --> Paused: Tap SETTINGS
    Paused --> Running: Tap SETTINGS
    Running --> NextReady: Deadline and alarm
    NextReady --> Running: Tap SETTINGS
    Ready --> Default: Hold DOWN
    NextReady --> Default: Hold DOWN
```

- Entering Ready does not start time. The next short SETTINGS starts the phase.
- Show remaining time prominently, identify focus/rest and display its duration.
  Desktop editing must show focus and rest durations with equal clarity.
- Use monotonic deadlines. Screen sleep, voice, navigation and theme changes do
  not alter the countdown. Changing preferences does not reset the active phase.
- On completion, play the existing device alarm and show completion feedback
  for ten seconds. Then retain the next focus/rest phase ready for one-key
  start. It never starts automatically and does not leave Pomodoro by itself.
- Opening Exit preserves both the countdown and running/paused state. UP cancels
  without changing either; DOWN ends the timer. These are direct actions,
  not a two-item menu requiring selection and confirmation.
- Ready and NextReady can exit immediately because no countdown is active.
- Copy is short: a state, a time and an actionable choice. Avoid explanatory
  slogans and descriptions of which default content appears after exit.

## 5. Information and feedback

Voice states distinguish network unavailable, unpaired, computer unavailable,
prerequisites missing, ready, recording and retryable audio failure. An error
must not permanently disable Enter or prevent a later capture attempt. A timer
continues without a computer. Failed/disconnected voice input never becomes a local
recording waiting to be uploaded later.

Weather has four pages: current conditions; six upcoming full hours; air and
wind; three-day forecast. Short SETTINGS advances manually; time passing never
changes the page. Retain the reading page across screen sleep and wake.
Switching pages uses cached data and never causes a
network request or Flash write.

Hourly temperature, rain probability and precipitation share aligned time
columns. Do not connect missing temperature samples. Three-day rows keep text
on the left and larger weather artwork on the right. Icons cover known weather
codes, day/night variants and an unknown fallback. Wind is shown as a Beaufort
level. Label the source's **US AQI** explicitly, and PM2.5 in micrograms/m³;
missing/stale values use a dash, not zero. Maximum UV includes a textual level.
Detailed data and freshness rules are in the [usage guide](README.md).

Radio shows the station, loading/playing/stopped/error state and list position.
Centre the current name in the existing 20 px font and show the next station in
16 px, with bounded long names; list positions are not fictitious MHz values.
Draw tuning ticks directly. Only the name band slides for 200 ms on a station
change; playback itself is static, and voice/status/key rails stay fixed.
Rapid changes replace the active animation rather than queueing. Voice, sleep,
navigation and palette replacement cancel it before teardown. Reuse labels and
fonts without a raster canvas, transparent layer or task.
A Mac probe passing means recognized audio was received on Mac. Only successful
device PCM playback earns the separate device-verified mark. Neither promises
future availability. Empty lists and unsupported streams have explicit states.

## 6. Device visual system

### Canvas and information hierarchy

The screen is **240 × 320 pixels**, physically small and strongly rounded by
the enclosure. Design at native resolution and inspect on the real screen.
Large desktop previews do not establish readability or edge safety.

- Use a continuous canvas. Do not put the voice and content areas into two
  ornamental cards, and do not reserve a tall application-title area.
- The top status region is approximately 24 px high. Its 16 px text and icons
  have explicit top/side insets for the enclosure. Display Wi-Fi bars, date/time
  and a numeric battery percentage immediately to the left of the battery icon.
  Keep the icon anchored as digits change, reserve space for `100%`, and show
  `--%` if the fuel gauge is unavailable. Reuse the existing battery label and
  sampling on boot and screen wake, then at one-minute intervals while visible.
  Skip fuel-gauge reads while blanked; do not add a polling task or timer.
- Voice is a compact status row. Its approximately 28 px waveform lives to the
  left; ready state uses one vertically centred line, exceptional/recording
  states can use two lines. Never leave an empty subtitle line in the layout.
- Give the remaining area to weather, a readable countdown or radio information.
- Keep the right key rail about 16 px wide. Current Home labels begin at
  `x=221`; their positions follow physical keys, not equal thirds of the display.
  New geometry needs real-device review, including rounded-corner clipping.

### Typography and icons

Chinese body text uses the maintained **20 px** font; secondary text and key
labels use **16 px**. Use larger 36/48 px digits for primary temperature/time
where space permits. Avoid shrinking body text to fit decorative content.
Tighten spacing deliberately; current CJK labels use -1 px letter spacing, and
rail labels use their own compact vertical spacing.

Keep the compact waveform proportionate to text. Use a timer symbol for the
Pomodoro shortcut and an exit symbol inside an application. Desktop branding
uses the companion/orbit mark, not a microphone-shaped application icon.

Before adding Chinese text, validate font coverage, selected widget fonts,
symbol fallbacks and dynamic names. Never hide missing-glyph boxes. Check both
short and long labels, missing values, three-digit numbers and station names.

### Color and themes

Use semantic palette tokens rather than new per-widget colors:

| Role | Dark | Light |
| --- | --- | --- |
| Canvas | `#14232E` | `#C6C1AD` |
| Primary text | `#F0EBDD` | `#1B2529` |
| Secondary text | `#A8BBC2` | `#3F4B50` |
| Voice | `#51DFC4` | `#005749` |
| Focus | `#FFB47D` | `#8C2C0C` |
| Rest / Enter | `#8CC9FA` | `#004E96` |
| Weather emphasis | `#F2CB73` | `#654600` |

In Light, use neutral primary and secondary text rather than assigning a similar
dark hue to every value. Current temperature and ordinary settings values use
primary ink; voice, focus/rest, UV and AQI keep their semantic colours alongside
explicit labels. Keep selected settings text neutral and show editing with the
existing reversed value, arrows and outline. Font size and position carry the
hierarchy even when the LCD makes hues look similar. After RGB565 quantisation,
the text inks target at least 4.5:1 contrast on their actual backgrounds; this is
a rendered-colour check, not a measurement of the physical LCD.

Use more chromatic vector marks:
teal #00765D, blue #0965AD, orange #B54716 and ochre #936100. Apply these to the
existing voice/weather icons, key marks, tuning needle, progress and chart
strokes. Do not brighten small text to match an icon or add image surfaces.

Light means a muted warm canvas, not bright white panels. Color reinforces text
and symbols; it cannot be the only indication of state or availability. Device
LCD appearance can differ from rendered RGB previews, so validate both themes
at normal brightness on hardware.

Support dark, light and scheduled themes. Defaults are 08:00 light / 21:00 dark;
the device executes the schedule, including intervals crossing midnight.
Before valid time is available, scheduled mode uses dark. Theme does not change
brightness, timer state or playback. Evaluate the current device time on boot,
first valid clock and wake; do not wait for a boundary or persist its last colour.
If a cold boot has no valid clock, acquire UTC over SNTP after Wi-Fi obtains an
address. Client time sync remains available; use the persisted timezone until
the client updates it. Manual dark and light modes do not execute the schedule.

The device system clock is the single calendar-time authority; SNTP
and the authenticated client set that clock, rather than supplying separate UI
clocks. Use an already valid local clock immediately. After calibration,
re-evaluate calendar-dependent displays and themes without restarting the
device, applications or Pomodoro. Durations use the device's monotonic clock so
wall-clock corrections cannot change elapsed focus time.

Network time acquisition belongs to the existing network task and SDK TCP/IP
service. Only start while time is invalid, outside capture/provisioning, with
at least 20 KiB free heap. Each attempt has a 12-second deadline and one server;
rotate among Aliyun, Cloudflare and pool.ntp.org on failure, with 5-second,
1-minute, 5-minute and capped 15-minute retry delays. An active attempt briefly
checks completion at most once per second while the screen is off. A valid
clock, loss of Wi-Fi or capture/setup stops and releases the SNTP service.
After success no periodic SNTP request, timer or completion polling remains.
Do not add a dedicated task, semaphore, screen wake or Flash timestamp writes.
Without internet or a client, keep the clock unavailable and scheduled mode
dark until a valid source succeeds; do not invent time from a stored timestamp.

During audio use, a validated volume-only configuration update is permitted;
other changed fields remain gated. Persist and acknowledge through the existing
revision path. The playback owner applies the new volume at the next PCM frame;
do not restart the stream or touch the muted capture output from the config path.

### Consistent key rail and editing

Use the right rail on every page, including settings and confirmations. A dot
means a short press; an elongated horizontal mark means hold. Keep the gesture
mark and short label together. Do not put another full set of key instructions
at the bottom of the page. Disabled actions are visually subdued.

Editing must change the selected value itself: visible row outline, contrasting
value background and directional arrows. A changed rail alone is insufficient.
Use concise status labels and useful errors. Avoid duplicate instructions,
marketing copy and decorative readiness dots.

## 7. Desktop interaction

Use computer/client for connection, pairing and device actions. Name an operating
system only for a platform-specific feature or requirement; this wording does
not imply support for an unimplemented platform. The current client is macOS-only.

The macOS app is primarily a menu-bar utility. Opening its window can show the
Dock icon; closing the red window button hides that icon and keeps the receiver
running. Only Quit stops the application. Sidebar rows have full-row hit areas.
Use the companion mark consistently in the app, Dock and menu bar.

Settings group related controls and show meaningful units, ranges and save
results. Put longer explanations in contextual help, including what microphone
gain changes and when to increase/decrease it. The input-method hint states
hold-to-talk compatibility and shortcut conflict risk. Do not repeat device key
tutorials below connection or timer settings, or explain window closing in a
permanent footer. Show focus and rest durations together.

Radio uses **library + selected stations**: recommendations, name search and
custom URL detection feed an ordered device list of up to 20 entries. Search
shows the name field, Chinese checkbox and Search button on one row. The fifteen
curated recommendations also form the initial station list, in the same order;
preserve any saved list, including an empty list, across firmware updates. Search
defaults to Chinese-language stations; unchecking Chinese removes the language
filter. Blank names are allowed. Requests use ten results per page, hide broken
entries and sort by votes descending, with no hidden country or bitrate limit. Users can reorder/remove entries and save an empty list. Keep
custom input on detection failure. The client manages the list, not device playback.

The macOS UI, keyboard sender and networking workers share one main-thread
PostEvent preflight snapshot. A worker must not synchronously wait on the main
thread for a permission query while shutdown waits for that worker.
After a keyboard-permission grant, recheck when the app becomes active. If the
running process retains a denied state, reload once after returning from the
explicitly requested system authorization, or when a fresh same-executable probe
confirms a stale result. Child-process probes can also inherit a cached denial.
Wait for active operations to finish; the new engine must pass the real PostEvent
check before showing ready. Preserve unsaved settings, station ordering, form inputs and navigation
in a private, short-lived, one-use recovery file. Close the old UDP listener
before relaunch and allow at most one reload to avoid a loop. Never substitute
an unrelated permission check or send test keystrokes to infer permission.

## 8. Configuration and connectivity

Phone hotspot setup configures **Wi-Fi only**, using the password-free
`Vibe-Setup-...` AP and captive portal. Successful connection and storage close
the AP automatically without another confirmation. Routine settings use the
desktop's existing Wi-Fi or BLE link and never require returning to hotspot mode.

A new device introduces Bluetooth, Wi-Fi and Later on its physical key rail.
BLE is discoverable from boot, before any transport choice or Wi-Fi setup;
computer requests may show the physical confirmation directly over the guide.
Later persists independently in NVS. Paired or previously dismissed devices
start Home. Device settings retain computer connection, Wi-Fi and unpairing.
Saving Wi-Fi does not finish computer authorization. Cancellation or expiry
restores the original page and retains existing configuration.

Keep up to five Wi-Fi profiles, managed only in the phone portal. The portal
separates saved and nearby networks, reuses saved passwords without returning
them to the browser, supports password replacement and forgetting. Same-name
updates replace credentials only after a successful connection and save.
Full capacity requires explicitly forgetting an old network; never silently
replace one. Forget removes persistence without interrupting the current link.

On every boot/outage, try the last successful profile and then every other
saved profile, including hidden/unavailable-in-scan SSIDs. Driver failure moves
to the next profile; a fifteen-second attempt timeout bounds missing callbacks.
Failed rounds back off 5/10/20/40/60 seconds. Healthy links trigger no background
scans or profile hopping. Without saved Wi-Fi, first boot leaves the Wi-Fi radio
stopped and uses BLE discovery. Only an explicit Wi-Fi choice opens the hotspot;
an unavailable saved network or later outage preserves the page and timer.
Once the setup hotspot is open, stop an
unfinished automatic connection attempt and pause background profile retries.
The phone must be able to scan without the driver simultaneously connecting
to an unavailable saved network. Test only the network explicitly submitted
in the portal; resume automatic retry when setup is closed. An already healthy
STA link may remain connected while the phone manages profiles.
Late failures for a previous SSID, or while the driver already has a newer
association, must not clear readiness or advance that connection's retry.
Select the next profile after applying timeouts, not before. Existing BLE
heartbeats must not close manual Wi-Fi setup or abort a submitted connection.
Automatic closure for first-use computer authorization is allowed only while
no submitted network is being tested.

Scan errors, driver-busy state and allocation failure must be returned as
errors, not successful empty arrays. Keep the saved list usable if scanning
fails; distinguish an actual empty 2.4 GHz scan and offer refresh/manual entry.
Drain scan records individually, retain at most sixteen results, and release
the driver's unread list on success, truncation and every post-scan failure.
Do not add a resident scan task, cache or record-array allocation.

The credential bank is 487 bytes; its versioned compact NVS value is at most
491 bytes. Reuse the old Wi-Fi key: decode/migrate the original single-network
value and replace it only after a successful write. Do not retain a second copy
that could resurrect forgotten credentials. Old single-network firmware cannot
read the new multi-profile format after downgrade; provisioning is then needed.
No new resident worker or task stack is allocated. Protect the bank separately
from controller state; network/HTTP workers own persistence, never button callbacks.

Device discovery, control and radio audio use fixed UDP 33333. The client binds port zero
and lets the OS assign an exclusive available port. Discovery, settings and audio
reuse that socket. An authenticated beacon selects its actual source IP and UDP
port; the advertised JSON port cannot redirect replies. Ordinary packets must
match both endpoint fields. A client restart or device address/boot change clears
stale requests, event deduplication and held shortcuts, then reloads device data.
Unconfirmed writes are not replayed across a reconnect; local drafts stay local.
New firmware accepts old fixed-port clients. Install the matching firmware before
this dynamic-port client; the old firmware cannot route its replies correctly.

Device values are authoritative. The client loads them on connection/reconnection;
revision notifications and existing keepalives repair missed updates. Unsaved
Client edits are drafts: unmodified fields follow the device, modified fields stay
local. Save submits only modified fields; only a successful device reply means
persisted. Storage failure must not report success. Avoid redundant NVS writes.
Station lists use a separate revisioned, authenticated atomic transaction;
compact v2 storage reads old v1 blobs. Old 16-station firmware cannot read a
newly saved v2 list after downgrade; export/record stations before downgrading.
The 24 KiB NVS is shared with Wi-Fi/pairing/preferences: twenty is the entry
ceiling, not an unlimited address-storage guarantee. If storage is exhausted,
saving fails without replacing the previous list;
partial transfers never replace the saved list.

Defaults: brightness 50%, volume 80%, screen timeout 15 s (range 3–60 s), focus
25 min, rest 5 min, scheduled theme 08:00/21:00 and Beijing weather. Weather is
always available as the default module. Existing saved values take precedence
on updates. Local settings contain basic hardware controls, theme, Wi-Fi setup
and unpairing; there is no software power-off action.

The desktop requests a connection and the device confirms it with a physical key. A SHA-256 commitment binds approval to the client and candidate token; see [Device connections](connections.md). The token is stored
in device NVS and an account-local client file (directory 0700, file 0600), with no
Keychain calls. LAN transport is not encrypted; this is a trusted-LAN design.
Audio is routed live, not saved by this project. macOS Accessibility is a separate
OS permission for synthetic keyboard events. Shortcuts are ordinary key events
and can conflict with other software or be blocked by secure input.

The desktop selects one device from a deduplicated list. Each device authorizes one computer at a time, with physical approval for handover. Wi-Fi and BLE can attach together with one business transport and automatic fallback. Remote playback control remains outside this version's contract. Agent notifications follow the integration contract below.

## 9. Resource ownership and power

Use a single audio owner for microphone, codec, chime and radio; button callbacks
only enqueue events. Preserve voice service state and its **3,200-byte PCM buffer
from startup**, including while radio plays. Keeping RAM reserved does not keep
the microphone powered. Keep the codec asleep when audio is idle.

Weather normally arrives as a compact computer cache over either paired link.
The client validates provider units, bounds the response, sends one authenticated
packet, cancels during audio, and refreshes at fifteen-minute intervals with
bounded retry. The controller rejects wrong-city, stale, malformed and busy
updates; failed updates retain the previous sample. It adds no device worker,
TLS allocation or persistent cache. Direct device weather downloads remain an
optional fallback with their existing memory admission and disposable worker.

That fallback uses a disposable worker. HTTP/TLS, response bodies and parsing
resources are released, then another task deletes the finished worker and
reclaims its **8 KiB stack**. Audio cancels and joins that worker before using its
resources. Sleeping or suspending a task alone does not reclaim its stack.

The Mac owns radio HTTP(S), HLS/ICY parsing and native audio decoding. The
device owns only a sixteen-frame ADPCM receiver and one PCM output block, allocated
for each listening session. No device radio HTTP/TLS or MP3/AAC decoder runs.
Voice ends the radio session before capture;
after voice, rebuild radio only if listening was previously requested. A paused
radio stays paused. Do not retain large radio resources merely to avoid a
reconnection unless the measured RAM and energy budget supports it.

Every allocation needs one owner, a lifetime and a failure policy:

| Resource | Owner / lifetime | Release and failure rule |
| --- | --- | --- |
| Voice PCM, 3,200 B | Audio service / application lifetime | Reserve at startup; roll back failed startup; never lend it to another module |
| Core task stacks, 33 KiB total | Main, audio, network, LVGL / application lifetime | Measure worst paths before resizing; do not add a permanent task per page |
| LVGL pool 26 KiB + display DMA 9,600 B | UI / application lifetime | Rebuild module objects inside the pool; keep DMA requirements distinct from ordinary heap |
| Weather stack 8 KiB and HTTP/TLS/body/parse workspace | Disposable weather worker / one update | Cancel, clean up, externally join/delete before audio; allocation failure defers weather |
| Radio encoded blocks 12,864 B + 96 B metadata + PCM 3,200 B | Audio owner / one radio session | Sixteen separate 804 B blocks tolerate post-voice heap fragmentation. Detach under receiver mutex, then free all blocks on voice/exit/failure; no extra reader task |
| Wi-Fi credential bank, 487 B | Network service / application lifetime | Five profiles; separate mutex; serialize at most 491 payload bytes on existing worker stacks, save before replacing; never return passwords through LAN/portal reads |
| Saved station list | Catalog / application lifetime | Allocate `12 + 306 × count` bytes (maximum 6,132), not a permanent 20-slot array; store only actual null-terminated names/URLs in NVS; accept legacy 16-slot blobs |
| Station-list transfer staging | Configuration transaction / bounded transfer | Allocate by incoming count only while audio is idle; cancel before audio starts; promote the staged list on atomic commit without another full-size copy; preserve the old list on failure; expire abandoned transfers |

For each new feature, document its **simultaneous peak**, including library
allocations, task stacks, DMA and temporary copies. Calculate overlap from actual
lifecycles, not by summing mutually exclusive states or ignoring background jobs.
Every partial initialisation path must release what it owns. Do not free another
owner's live buffers or delete a task still using them. Record free heap,
largest usable block, minimum free heap and stack high-water marks for repeated
entry/exit and voice interruption. A successful single allocation does not
establish an adequate memory budget. Resource-policy changes require lifecycle,
allocation-failure and repeated-cleanup tests plus a device regression check.

The desktop advertises `radioFormats: 3` (bit 0: legacy 24 kHz format 1; bit 1: buffered 16 kHz format 2). The device requires bit 1 before starting radio and includes `format: 2` in `radio.open`; older desktop clients show the existing update-client message. Missing `format` means legacy format 1 on the new desktop, retaining support for older devices. Format 2 lowers high-frequency detail above 8 kHz to reduce media bandwidth by about one third and fit a longer jitter cache in 752 B less receiver/PCM memory (16,160 B total on ESP32-C3, excluding ingress, I2S and allocator overhead). It does not affect voice capture.

Radio audio is 16 kHz mono, in independently decodable 100 ms IMA ADPCM
blocks (804 bytes). Packet type 5 contains a random 64-bit session ID,
a 32-bit sequence and format ID 2. The receiver validates the authenticated
endpoint, current ownership generation, session, length and codec header before
accepting a sixteen-frame sequence window. Duplicates never replay. Playback
credits and lifecycle events go over both attached links; media uses one route.
Radio uses UDP with a 1.6-second receive cache and bounded missing-block repair;
no additional TCP listener, socket or framing layer is needed. The receiver
validates the authenticated endpoint, generation and session. Delayed mirrored
receipt masks at the same playback cursor can add bits but cannot erase them.
The same receipts prune already-played or received packets from the BLE write
queue, including Wi-Fi-delivered repairs; preserve an in-flight response write
and every control fragment. A stale media backlog must not delay new audio.
A missing Wi-Fi media acknowledgement triggers repair after 350 ms at startup
and 100 ms while playing. BLE takeover requires a startup hole or one of the
next eight blocks (five in the legacy ten-frame cache) to remain missing for 350 ms; a late tail receipt cannot
divert healthy Wi-Fi into a newly established BLE queue. Once BLE carries a
session, keep it while media receipts remain healthy; Wi-Fi discovery recovery
and sparse probe receipts do not prove sustained media delivery. Physical BLE loss permits immediate Wi-Fi fallback. A missing near-playhead
BLE block is tried over Wi-Fi after 300 ms even if control still works; a
Wi-Fi hole can similarly fall back to BLE after 350 ms. This covers one-way
media failure without repeated discovery-driven migrations. When the playback
cursor stalls, alternate-link repair covers the whole missing cache prefix:
rebuffering needs twelve contiguous blocks, not only the first eight. A new listening
session chooses again.
After a media-driven route change, allow one second for queued fragments.
Advancing in-session media receipts on that chosen route renew a 600 ms hold;
unchanged, regressing or sentinel receipts cannot renew it. A slow individual
packet cannot immediately send a recovering stream back to the route that just
failed. Physical disconnection still selects the available route immediately.
Media packets are paced rather than sent as a full-window Wi-Fi burst. With
BLE available, RSSI at or below -75 dBm selects BLE at startup; recovery above
-68 dBm clears the poor-signal flag. Later routing follows actual media receipts.
Full session loss cancels playback; restored authorization
starts a fresh session only if listening is still requested.

The four static Wi-Fi RX buffers cover an explicitly configured four-frame
AMPDU RX block-ack window; the SDK default six-frame window exceeds this
reduced pool. Dynamic RX and TX are each capped at four buffers: the earlier
12/12 limits produced failed 1,700-byte Wi-Fi allocations during radio testing.
These limits bound transient consumption, rather than reserving extra SRAM;
radio/voice/control throughput and DHCP/portal behavior need device regression.
Each connection attempt scans all APs for the selected SSID and sorts by signal,
instead of stopping at the first, potentially much weaker AP. No BSSID is pinned
and a healthy connection is not scanned continuously.

BLE parameter negotiation starts after a one-second settle period on the NimBLE
host queue. It must not race the stack's initial DLE/encryption with an additional
application PHY procedure. A command return of zero is not a successful link
update: check the completion event and actual supervision timeout. Request a 15–30 ms connection interval and six
seconds of supervision, accept at least two seconds, and retry at bounded 1/2/4-second backoffs
with at most four requests per connection. Missing completion is bounded too.
A central may select 30 ms; retain the valid interval range rather than forcing
15 ms (see [Apple connection parameters](https://developer.apple.com/library/archive/qa/qa1931/)).
Each link owns independent state, disconnect/reset clears it, and no periodic
callout remains after success or exhaustion. The earlier immediate requests
collided and left this Mac's actual timeout at 360 ms.

During a radio session, the ESP32-C3 coexistence hint prefers Bluetooth so BLE
connection events and media credits survive Wi-Fi scanning/association. UDP
radio needs little Wi-Fi airtime. Every completed, cancelled or failed session
restores balanced coexistence before voice or idle; an unsupported SDK hint is
logged without turning it into a fatal playback error. No task or buffer is
added for this scheduling hint.

The Mac uses AudioFileStream and AVAudioConverter, not an external runtime.
AAC container hints require two ADTS headers at declared frame boundaries;
a coincidental sync inside MP3 payload cannot select the AAC parser. The known
legacy RFI preset path is repaired when fetching, without rewriting device lists.
A radio session holds a scoped Foundation activity for live-audio timer/I/O
precision: decode-only playback has no local speaker output to advertise its
latency needs to App Nap. Stop, voice and disconnect end the activity. It does
not prevent system idle sleep or keep a display awake.
ADTS packet descriptions can exclude header gaps: copy checked compressed
payloads into contiguous converter storage and rebase their offsets. Preserve
converter state across chunks. When an active receiver briefly lacks its next block,
it allows up to 40 ms of ingress jitter before returning to prefill, below the
60 ms I2S DMA reserve. Cancellation and ownership checks continue during this
bounded wait. Radio starts after twelve frames are ready; its sixteen-frame receive window is
negotiated in the open event. The producer queue holds at most 30 frames;
stopping wakes a blocked producer and cancels its worker. The worker alone invalidates URLSession after leaving all requests; stop-before-start and HLS request transitions must not race task creation on an invalidated session. If a close event is lost,
twelve seconds without current-session progress cancels the desktop decoder,
cache, timer and scoped activity; stale closes cannot stop a newer session. BLE radio queue limits
reserve space for control; cancelling radio discards queued media while retaining
the current GATT write and all control fragments. Radio uses paced Write
Commands, with OS flow control, packet deduplication and an independent
fragment channel. Its temporary assembly is freed after completion, disconnect
or expiry. GATT Service Changed refreshes cached properties across firmware
updates while retaining the encrypted bond; the client rediscovers invalidated
services. Keep warning/error logs, but suppress per-notification stack INFO spam.

HLS retains full playlist/segment URLs and queries, tracks media sequence numbers,
and never replays an already consumed segment. Select audio-only master variants
up to 384 kbit/s, then validate actual media through the decoder. MPEG-TS parsing
keeps PID/continuity across segments. Encrypted HLS, fMP4 maps and byte ranges
fail explicitly. Bound playlist size to 32 KiB, segments to 2 MiB, nesting to
five levels and source requests to a 12-second idle timeout. Startup has a
20-second deadline; a running device stream stops after eight seconds without
playable audio. Source errors stop with a retryable device control, rather than
remaining in Connecting forever. Never log signed URLs.

Keep optional non-ISR FreeRTOS/ring-buffer functions in Flash and disable Wi-Fi
IRAM throughput optimizations without moving required interrupt paths. Weather
retains validated HTTP(S) and disposable TLS resources. Radio TLS runs on the
Mac and does not allocate device TLS buffers. Do not change fonts, UI pools,
communication buffers or stack budgets to conceal an optional radio allocation.

New paired clients negotiate a 10-second combined readiness/time beacon and
30-second peer expiry. The installed firmware accepts 5–30 seconds; its hello
advertises the upper bound of that capability, not the chosen interval. This
client policy change needs no firmware update or additional device RAM.
Discovery remains every two seconds; peers without negotiation retain 5/15
seconds. Client 0.8.0 still chooses 30/90 seconds on the same firmware.
Audio/keyboard readiness changes send immediately.
Voice, keys, configuration and Agent notifications are event-driven and never
wait for a heartbeat. Replies replace device fallback pings, due only after the
negotiated interval plus two seconds without outgoing traffic. Passive expiry
allows three missed beacons; this interval prioritizes connection-state updates
without changing event delivery. Client
exit marks audio/keyboard unavailable immediately. Idle Wi-Fi remains MIN_MODEM;
changing listen intervals requires separate latency/reception measurements.

Standby must leave a real automatic-Light-sleep window. Three ADC keys share
one low-level GPIO interrupt: once all gestures settle, the button component
stops its 20 ms polling timer. Restore the pin's digital input only for idle
wake, without adding internal pulls to the external resistor ladder. An ISR
resumes the component; its task disables wake before sampling ADC again. Keep
the first gesture, release and long-press semantics. Arming failure resumes
polling, and ISR setup failure retains normal polling. Teardown disables wake
and removes the handler before releasing ADC. Validate all three actual keys.

Blank controller/network waits are up to 30 seconds, interrupted immediately
by queue/socket events. The controller caps its wait at a running timer's exact
deadline. Provisioning, reconnect, recording and visible UI keep short waits;
network commands and display transitions wake the socket. Receive timestamps
are taken after blocking, so fresh packets cannot look thirty seconds old.
Cached RSSI is queried while visible. Memory logs run only with a USB host.
Weather still refreshes every fifteen minutes, with at most one idle wait of
scheduling delay and no additional resident worker. Radio/voice ownership and
Wi-Fi recovery policy remain unchanged.

LVGL reads the ESP monotonic clock on demand, with a 30-second port maintenance
tick and idle task wait. Its 20 ms visible refresh is independent of that tick.
Blank pauses the refresh timer and sends LCD Sleep In; wake restores the panel
before refresh/backlight. Do not globally stop LVGL: pinned LVGL 9.5 / port 2.9.0
would busy-poll. Keep the same screens, pool, DMA buffer and timer deadlines.
Queue voice/alert work before the panel's roughly 100 ms command delay.
Hold a no-Light-sleep lock while the display is awake: the board's default LEDC
mode does not sustain backlight PWM in Light-sleep. Release it only after blank
and panel sleep succeed; reacquire before restoring the panel/backlight.

An enumerated USB host temporarily prevents automatic Light-sleep so C3 serial
monitoring and flashing remain usable; unplug USB for battery-only acceptance.
CW2017 exposes SOC and cell voltage, not measured current. SOC/time trends can
compare discharge sessions but must not be presented as instantaneous mA/mW.
On-demand authenticated power.get/power.reset returns successful/rejected sleep
counts, successful-call time (including entry/exit overhead), blank-only time,
longest call, USB/key-wake status, fresh SOC/mV and bounded lock history. No new
sampling timer/task/history ring or Flash writes. The public PM exit callback
uses the pinned SDK sleep context to exclude rejected/skipped calls. IDF PM
profiling adds per-lock counters; the SDK-private context must be revalidated
when upgrading IDF. The desktop Connection page keeps diagnostics expanded,
with manual Read, Reset and Copy actions; never poll it automatically.
Separate window totals, instantaneous readings and boot-cumulative counters.
Group identically named lock types, preserve each duration without summing
overlapping intervals, and retain raw lock records in the copied report.
Keep all reported diagnostic fields visible, including total successful sleep
time, both connected/disconnected USB states, and lock-report completeness.
The copied report targets model-assisted analysis: use original milliseconds
and bytes, raw lock records and explicit unavailable values; omit explanatory
paragraphs and derived values a reader can calculate. Counter scope, heap scope
and sleep-overhead definitions stay in code and this document; the report is
intended to accompany the matching source. Omit transport request IDs.
The two I2S locks belong to the separate capture and playback channels.
Display short sleep durations in milliseconds rather than rounding to tenths
of a second. Reading wakes CPU/Wi-Fi and current lock activity
may include the read itself. Reset clears session totals, not boot lock history.
These are sleep/lock diagnostics, not measured electrical draw.
The current C3 build adds 176 B BSS and 904 B IRAM versus the preceding battery
display/manual-weather build. PM profiling grows each allocated lock from
32 B to 56 B; GPIO ISR registration and the single PM exit callback also need
small dynamic structures. The compact lock dump is built only on request,
using a bounded stack workspace and temporary JSON/stdio allocations. Include
these costs in heap measurements; do not describe diagnostics as free.
Each explicit read also queries the existing allocator counters for the
8-bit-capable heap, before allocating the diagnostic response: allocated
bytes, available bytes, largest contiguous free block, and historical minimum.
These are runtime heap statistics, not total chip SRAM usage; firmware static
sections are excluded. The historical minimum sums per-region low watermarks
that may have occurred at different times. Reset does not clear it.
Use the largest free block when investigating failed decoder/cache allocations;
total available bytes alone do not establish whether a large allocation fits.
This adds no resident sampling buffer, task, timer or Flash writes. The request
uses one temporary `multi_heap_info_t` (28 bytes on ESP32-C3) and temporary JSON
allocations, released after transmission. Old firmware without heap fields
shows an unavailable state rather than fabricated zeros.
Against the preceding local release candidate, this addition leaves BSS,
initialized DRAM and IRAM unchanged; the merged firmware grows by 176 bytes.
Measure battery-side current separately; a USB charger meter includes charging
and conversion effects. No battery-life claim follows from a successful build.

Use notification/queue waits and cached data. Do not search/probe station
libraries on the ESP32. Radio and voice temporarily disable Wi-Fi modem sleep
for their audio sessions, then restore MIN_MODEM.
Stop retrying after bounded repeated failures. Stable radio reception takes
priority over an assumed power saving; increased Wi-Fi power alone does not fix
an upstream outage. A finite FIFO cannot conceal arbitrary network gaps.

Weather cancellation is cooperative; DNS, connection establishment and TLS
can outlast a body-read timeout. Radio reception checks cancellation between
100 ms output blocks; Mac requests are cancelled separately. Resume includes
a fresh computer decoding session and prefill. Do not claim instant voice or
instant radio recovery without device timing. Current/energy improvements need
instrument measurements, not inference from lower task counts.

## 10. Change and acceptance rules

A substantial new interaction or visual direction is first shown as native-size
static states and discussed before implementation. Preserve approved controls
and defaults. Evaluate happy paths, cancellation, missing data, disconnection,
heap pressure, sleep/wake and repeated switching, not just a screenshot.

Keep state machines and protocols host-testable. All non-LVGL-thread UI access
uses the BSP lock. Reuse the BSP for hardware and keep feature policy in the
application. Do not change pin assignments or replace the accepted UI with a
demo shell while fixing another feature.

Run the full repository gate and retain the exact merged-image/ELF identity.
Record Build, Host tests, Device tests and Unverified separately. Real tests
include voice during radio, repeated resume, timer exit/cancel state, both LCD
themes, long station/city labels and theme/screen-sleep boundaries. Follow the
owner's current flashing authorization and verify data-preserving updates.
Neither a build nor a flash proves audio stability, legibility or battery life.

## Agent notification contract

Agent adapters live on the computer. Reuse the paired transport and audio owner; use fixed bounded device state, expiry and deduplication. Never forward transcripts or interfere with approval decisions. Keep voice and physical-key semantics intact. See [integration and memory contract](agents.md).

Install only attention-seeking callbacks. The first event is immediate; suppress additional callbacks for the same Agent and known session for one second, across event kinds, without extending the window. Other sessions and Agents stay independent. Do not group missing identities or add lifecycle hooks, delayed candidates or metadata lookups. Keep exact-event retry filtering and bounded desktop bookkeeping. Generic idle and per-tool failures are not new human-action requests.

Display a compact non-modal overlay for five seconds. Preserve uncovered page
content and keep its updates running. Any physical press dismisses it and
continues that same gesture. Do not add a dedicated dismiss action, backdrop,
page snapshot, new task or larger LVGL pool. Reuse the existing fonts and draw
after page content; keep voice available and measure drawing peaks and repeated
show/hide allocation before delivery.
