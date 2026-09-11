# NetCheck 0.1 — private-use Android diagnostic pilot

**This is a diagnostic pilot, not a VPN unblocker and not an official PCAPdroid release.**

The APK combines a small Russian diagnostic dashboard and consent-gated app scenarios with the open-source PCAPdroid capture engine, pinned to commit `dbfd5e04f560adf02f88c8fd0a8d3588e39fa71f` (2.0.1). Copyrights of Emanuele Faranda and all upstream contributors are preserved. Distribution and modifications follow GPL-3.0-or-later. The complete corresponding source snapshot (including used submodules and these build recipes) is shipped alongside the APK. Keep it when distributing the APK.

## Implemented pilot features
- Android 10+, local-only reports and ZIP share/save; no registration, VPS or upload endpoint.
- Network-bound A/AAAA DNS, direct TCP, verified TLS, bounded HTTP/1.1.
- Optional TLS 1.2 / 1.3 / omitted-SNI comparisons and repeated default handshake. These comparisons do not prove censorship by themselves.
- Capture only explicitly selected installed Telegram / YouTube / TikTok packages, using a local VPN without remote relay, root or TLS decryption. TCP and UDP forwarding use upstream PCAPdroid; QUIC traffic is not intentionally blocked.
- Metadata snapshots: destination IP/port, visible hostname, protocol, byte counts, native connection state and error; no raw application payload is exported.
- Optional Accessibility automation opens user-approved public links; a narrow YouTube known-play-control rule may click Play. No text typing, private chats, messages, calls, likes, arbitrary swipes or hidden permission granting.
- Unknown/login/challenge screens require a person. A successful UI action or received bytes is not proof of working video/audio.

## Not implemented / not claimed
- Decryption, exact packet loss attribution on the physical link, whitelist detection, automatic diagnosis of the censor's internal rules.
- DoH comparison, direct QUIC-handshake testing, ClientHello fragmentation, video-content/audio verification, automatic calls, universal adapters for arbitrary UI versions.
- This is not independent OONI control measurement; there is no remote reference server.

## Testing and privacy
A local VPN changes the TCP/DNS path, so compare applications with and without capture. The app uses the currently selected physical network and stops if it disappears. Approximate 50 MiB application-capture and 12-minute overall limits are polled once per second; a small overshoot is possible. Diagnostic HTTP bodies are capped at 64 KiB. The UI must stay unlocked. Reports are not uploaded; the user explicitly invokes Android's share sheet. No analytics, advertising, boot capture or sensitive Android permissions (contacts/SMS/microphone/location) are added. Accessibility is optional and can be disabled in Android settings after the test.

The application may inspect metadata present in unencrypted handshakes. Core capture temporarily processes traffic in memory to forward it. Reports contain no original packet payload or complete UI trees. Default upstream Android/native logs are not included in exports. Engine log files are disabled by the build integration.

## Build
`bash netcheck/build.sh` requires a Linux Android build environment, Java 21, git and GitHub-hosted-runner SDK tools. It clones the pinned upstream and its pinned submodules into an isolated temporary directory, runs `prepare.py`, builds `WithoutUsharkDebug` and an instrumentation-test APK, verifies signatures and generates source/checksum artifacts. It never builds unrelated files in the repository root.

`bash netcheck/smoke.sh` runs installation and basic integration checks on an emulator. Real Telegram/YouTube/TikTok UI behavior and Russian network conditions must be tested separately on an authorized physical device. Public CI contains only code/build metadata, never tester reports.

The debug signing key is only for testing; no production signing credentials are included. The app ID differs from PCAPdroid, allowing both apps to remain installed, but only one VPN capture can run at a time.
