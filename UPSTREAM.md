# RustDeskTiny upstream

RustDeskTiny is a GPL-3.0-or-later product branch of RustDesk. The source tree
and Git history are intentionally kept aligned with upstream.

- Upstream repository: `https://github.com/rustdesk/rustdesk.git`
- Upstream baseline: `978e2e28b9d3e12b0d3589604bb6f04f13afdeda`
- Product branch: `rustdesk-tiny`

Product changes must remain behind the `rustdesk-tiny` Cargo feature. Upgrade
by merging the next upstream commit and replaying the small product commits;
do not copy RustDesk capture, input, session, IPC, or service code into a
parallel implementation.
