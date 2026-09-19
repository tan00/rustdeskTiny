# RustDeskTiny changes from upstream RustDesk

This file is the maintenance inventory for RustDeskTiny. Update it whenever a
Tiny-specific source file is added, removed, or changes responsibility.

## Upstream baseline and policy

- Upstream repository: `https://github.com/rustdesk/rustdesk.git`
- Upstream baseline: `978e2e28b9d3e12b0d3589604bb6f04f13afdeda`
- Product branch: `rustdesk-tiny`
- License: AGPL-3.0, following upstream RustDesk (`LICENCE` file).
- Full inventory command: `git diff --name-status 978e2e28b..HEAD`.
- Per-file comparison command: `git diff 978e2e28b..HEAD -- <path>`.
- `libs/hbb_common` baseline revision: `29cf7cbe4d38ce36020749f713fb066299f02431`.
- `libs/hbb_common` Tiny revision: `37f609194804ca01fbe6ac237e70a9e4d07730a3`.
- `libs/hbb_common` is consumed from the Tiny fork
  `https://github.com/tan00/hbb_common` (single Tiny commit on top of the
  baseline above); the upstream remote is `https://github.com/rustdesk/hbb_common`.

Tiny changes should remain behind the `rustdesk-tiny` Cargo feature wherever
the file is also used by a normal RustDesk build. Keep capture, input, session,
IPC, privilege and service implementations shared with upstream; do not fork
those subsystems into copied implementations.

## Product behavior

RustDeskTiny accepts only an explicit numeric IPv4 or IPv6 address plus a
non-zero port. It does not use a RustDesk ID, rendezvous/relay registration,
NAT probing, server latency probing, account synchronization or RustDesk
software-update requests. A connection to an explicitly supplied public IP is
still allowed because it is a user-requested direct connection.

The UI hides the local ID and RustDesk-network state, keeps the one-time
password, uses an `ip:port` input, removes peer discovery/autocomplete and
multi-connection help, and hides account/network/server/proxy settings.

## Functional change map

| Changed behavior compared with upstream RustDesk | Implementing source files |
| --- | --- |
| Product identity and feature activation | `Cargo.toml`, `src/lib.rs`, `src/tiny.rs`, `src/core_main.rs`, `src/flutter_ffi.rs` |
| Numeric `ip:port`-only outgoing connections | `src/tiny.rs`, `src/client.rs`, `flutter/lib/consts.dart`, `flutter/lib/main.dart`, `flutter/lib/desktop/pages/connection_page.dart`, `flutter/lib/common/widgets/connection_page_title.dart` |
| No rendezvous, relay registration, NAT/latency probing, account synchronization or update traffic | `src/rendezvous_mediator.rs`, `src/common.rs`, `src/main.rs`, `src/platform/macos.rs`, `flutter/lib/models/peer_tab_model.dart`, `flutter/lib/desktop/pages/connection_page.dart`, `flutter/lib/desktop/pages/desktop_setting_page.dart` |
| Always-on direct server bound to `0.0.0.0:<configured-port>` | `src/tiny.rs`, `src/rendezvous_mediator.rs`, `src/ipc.rs`, `src/platform/windows.rs`, `src/platform/linux.rs`, `src/platform/macos.rs` |
| Stable one-time password, changed only by explicit refresh or password-length change | `src/tiny.rs`, `src/ipc.rs`, `src/server/connection.rs`, `flutter/lib/models/server_model.dart`, `flutter/lib/desktop/pages/desktop_setting_page.dart` |
| Tiny home page: no local ID/network status, but one-time password remains visible | `flutter/lib/common.dart`, `flutter/lib/desktop/pages/desktop_home_page.dart`, `flutter/lib/models/server_model.dart`, `src/lang/cn.rs`, `src/lang/en.rs` |
| Removes ID discovery, remote lookup, autocomplete, account and server-oriented UI | `flutter/lib/desktop/pages/connection_page.dart`, `flutter/lib/common/widgets/connection_page_title.dart`, `flutter/lib/desktop/pages/desktop_setting_page.dart`, `flutter/lib/models/peer_tab_model.dart` |
| Standalone install/service lifecycle and silent install/update | `src/tiny.rs`, `src/core_main.rs`, `src/platform/windows.rs`, `libs/portable/src/main.rs`, `scripts/build-windows-tiny.ps1` |
| Linux and macOS packaging through the upstream build pipeline | `build.py`, `scripts/build-linux-tiny.sh`, `scripts/build-macos-tiny.sh` |

## Rust source files changed from upstream

| Source file | RustDeskTiny modification |
| --- | --- |
| `Cargo.toml` | Declares the `rustdesk-tiny` Cargo feature. |
| `src/lib.rs` | Exposes the Tiny product module when the feature is enabled. |
| `src/tiny.rs` | Central Tiny policy and command implementation: branding/hard settings, stable persisted one-time password, permanently enabled direct IP access with an editable port, strict address parsing, direct-only CLI validation, listener configuration, Windows service commands, Unix listener persistence and associated unit tests. |
| `src/core_main.rs` | Initializes Tiny before platform bootstrap; consumes Tiny address/listener/host/service commands; implements validated `--silent-install`, `--silent-update` and optional `--install-dir`; returns reliable process exit codes; contains silent-install argument tests. |
| `src/client.rs` | Rejects every Tiny outgoing target that is not a validated numeric `ip:port` before entering upstream connection negotiation. |
| `src/rendezvous_mediator.rs` | Replaces the upstream rendezvous loop with a `0.0.0.0` direct TCP listener on the configured port in Tiny builds and feeds accepted streams into the shared RustDesk server connection implementation. |
| `src/server/connection.rs` | Keeps the Tiny one-time password stable across completed sessions and failed authentication attempts; normal builds retain upstream automatic rotation. |
| `src/common.rs` | Compiles NAT tests, rendezvous latency tests and both automatic and direct software-update checks into no-ops for Tiny. |
| `src/main.rs` | Skips startup rendezvous and NAT tests for Tiny. |
| `src/flutter_ffi.rs` | Initializes Tiny policy before the Flutter bridge exposes application state. |
| `src/ipc.rs` | Adds the feature-gated `TinyListen` IPC message, restricts its use to the protected service channel, applies validated listener changes and routes explicit Tiny password refreshes through persistent Tiny state. |
| `src/platform/windows.rs` | Passes the validated listener to the desktop-session server, restarts only when listener state requires it, supports embedded Tiny service commands, and prevents silent installation from launching GUI/tray processes. |
| `src/platform/linux.rs` | Restarts the shared session server after a protected Tiny listener change. |
| `src/platform/macos.rs` | Disables macOS auto-update for Tiny and restarts Tiny session servers after a protected listener change. |
| `libs/portable/src/main.rs` | Waits for silent install/update completion and propagates the embedded installer's exit code. |
| `src/lang/cn.rs` | Adds the Tiny-specific Chinese desktop/password explanation. |
| `src/lang/en.rs` | Adds the English fallback for the Tiny-specific desktop/password explanation. |
| `libs/hbb_common` | Advances the upstream submodule pointer from `29cf7cbe4` to `37f609194`; Tiny does not carry local modifications inside the submodule. |

`libs/hbb_common` is pinned as an upstream submodule and must remain free of
uncommitted Tiny-only changes. Direct-target enforcement belongs in
`src/client.rs` and `src/tiny.rs` in this repository.

## Flutter source files changed from upstream

| Source file | RustDeskTiny modification |
| --- | --- |
| `flutter/lib/common.dart` | Caches the process-wide Tiny-mode flag used by the desktop UI. |
| `flutter/lib/consts.dart` | Owns the boot-argument list so the connection page can consume a preset direct address without importing the app entrypoint. |
| `flutter/lib/main.dart` | Removes the former duplicate boot-argument declaration. |
| `flutter/lib/desktop/pages/connection_page.dart` | Uses `ip:port`, validates direct addresses, disables peer loading/online queries/autocomplete, hides RustDesk network status and hides multi-connection help in Tiny mode. |
| `flutter/lib/common/widgets/connection_page_title.dart` | Adds a caller-controlled `showHelp` flag; normal RustDesk keeps the help tooltip while Tiny removes it. |
| `flutter/lib/desktop/pages/desktop_home_page.dart` | Hides the local ID, retains the one-time-password panel and displays the Tiny-specific access explanation. |
| `flutter/lib/desktop/pages/desktop_setting_page.dart` | Hides account/network/ID-oriented settings for the product variant and rotates the one-time password only after an explicit password-length change. |
| `flutter/lib/models/server_model.dart` | Makes periodic password-model synchronization read-only so polling or transient IPC values cannot rotate the one-time password. |
| `flutter/lib/models/peer_tab_model.dart` | Disables discovery-oriented peer tabs for the direct-only custom product UI. |

## Build and packaging files changed from upstream

| File | RustDeskTiny modification |
| --- | --- |
| `build.py` | Adds `--rustdesk-tiny` and forwards the Cargo feature. |
| `scripts/build-windows-tiny.ps1` | Produces a renamed Windows application directory and standalone `RustDeskTiny-install.exe`; verifies toolchain inputs and installs the Python Brotli dependency only when absent. |
| `scripts/build-linux-tiny.sh` | Thin Linux Tiny entrypoint over upstream `build.py`; verifies and renames the generated Debian package. |
| `scripts/build-macos-tiny.sh` | Thin native-architecture macOS Tiny entrypoint over upstream `build.py`; verifies the app and embedded service, then applies Tiny bundle identity. |

`flutter/pubspec.lock` may change when Flutter resolves dependencies. Treat it
as generated dependency state, not as Tiny product logic, and review it
separately during upstream upgrades.

## Upstream upgrade checklist

1. Fetch and merge the selected upstream RustDesk commit into
   `rustdesk-tiny`; do not replace the repository with copied source files.
2. Run `git diff <new-upstream-commit> -- <path>` for every file in the tables
   above and resolve semantic conflicts, not only textual conflicts.
3. Confirm `libs/hbb_common` is clean and points at the intended upstream
   submodule revision.
4. Build with the `rustdesk-tiny` feature and verify the service listens only on
   the configured direct-access TCP port (`0.0.0.0:<port>`), with no outbound
   rendezvous, relay, NAT, latency, account or update connection and no
   unrelated UDP endpoint.
5. Verify invalid IDs/domains are rejected, explicit IPv4/IPv6 `ip:port`
   targets connect directly, and rendezvous/relay/NAT/update paths remain off.
6. Verify the local ID and network status remain hidden, the one-time password
   remains stable while focusing/typing, and explicit refresh still rotates it.
7. Test interactive install, silent install, silent update, custom install
   directory, service start/stop and upgrade over a previous Tiny version.
8. Update the baseline hash and this inventory in the same commit as the
   upstream merge.
