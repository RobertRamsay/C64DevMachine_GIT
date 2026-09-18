# C64 Dev Machine: MCP comment smoke test (v0.1.0)

This opt-in prototype connects an MCP client to the **running editor**. It can
read a small project, focus a node, and add one unconnected COMMENT. It does not
compile, launch VICE, edit existing code, delete nodes, import assets, load or
save a project. It is a test feature, not a production remote-control API.

Source baseline: `RobertRamsay/C64DevMachine_GIT`, main commit
`a8c5206441687feec0b6fba4255092238e636789` ("Manual language sensitive",
17 September 2026). Only the project resource list and one startup hook in the
workspace manager are changed; the implementation is in a new isolated object
and `tools/cdm-mcp/`.

## 1. Apply and rebuild

Save/commit your existing development changes first. Close GameMaker before
applying the patch. Run these commands at the repository root (the directory
containing the **folder** `C64DevMachine_win.yyp`):

```powershell
git apply --check "$env:USERPROFILE\Downloads\cdm_mcp_smoke_v1.patch"
git apply "$env:USERPROFILE\Downloads\cdm_mcp_smoke_v1.patch"
```

Stop if `--check` fails; do not force a patch across mismatched source.
Open `C64DevMachine_win.yyp/C64DevMachine_win.yyp` in GameMaker, rebuild and run.
An old, previously exported EXE will not contain this feature.

Use a **scratch project** with at most 200 existing nodes for this first test.
Close the welcome screen and any modal/text/code editor. Ensure the normal
undo history has at least two states enabled. Do not change projects during
an MCP command.

A small MCP badge appears briefly on startup. When disabled, there is no socket
and no clipboard polling; the shortcut is checked once per frame.

## 2. First test: no AI subscription or API credits required

Requires Node.js 22 or newer (`node --version`). There are no npm dependencies.
From the repository root:

```powershell
node tools/cdm-mcp/smoke.mjs --live
```

The test starts the actual MCP bridge as a child process and performs MCP
`initialize` and `tools/list`. On Windows it copies the local pairing key to
the clipboard using `clip.exe` (on macOS, `pbcopy`). If clipboard copying is
unavailable, it prints the key for you to copy manually.

In the **rebuilt Dev Machine window**, press **Ctrl+Shift+F12**. This is explicit
permission to read the clipboard once, connect to the local bridge and enable
its limited comment tools. Look for a green `MCP TEST: CONNECTED` badge. Return
to the terminal and press Enter.

The client then calls:

1. `cdm_ping` to verify the live editor is responding.
2. `cdm_project_summary` to capture the current workspace key and node count.
3. `cdm_add_comment` with the text `Hello from MCP!`.
4. `cdm_project_summary` again to verify the count increased by exactly one.

Expected result: Dev Machine displays an unconnected COMMENT containing
`Hello from MCP!` and pans to it. Use the normal **Ctrl+Z** to undo, and **Ctrl+Y**
to redo. Undo/redo is a manual acceptance check; this prototype exposes no
remote general-purpose undo tool.

The smoke client closes its bridge when finished. The editor may need up to
15 seconds to notice a closed raw TCP server via its heartbeat timeout. Press
Ctrl+Shift+F12 to disconnect immediately. Nothing reconnects automatically.

This is a **real MCP protocol test**, not an AI-model test. It verifies the
plumbing without spending model credits.

## 3. Use an AI client after the smoke test

Run **one bridge at a time**. Close the smoke test before starting Claude Desktop
or Codex with this server configured. Do not start the bridge manually as well:
the MCP host launches it. Tool use remains subject to the host's permissions
and your own approval. Pair only with a local process you trust.

### Claude Desktop (Windows)

Generate an entry with absolute paths:

```powershell
node tools/cdm-mcp/bridge.mjs --claude-config
```

Merge the printed `c64-dev-machine` entry into the `mcpServers` object in
`%APPDATA%\Claude\claude_desktop_config.json`. **Do not replace other configured
servers or other settings.** The printed `command` uses the current full path
to Node and the entry pins the same local token file and port.

Fully quit and reopen Claude Desktop. In PowerShell, copy the pairing key:

```powershell
node tools/cdm-mcp/bridge.mjs --pair | Set-Clipboard
```

Press Ctrl+Shift+F12 in Dev Machine to pair again. Start a conversation with this
server enabled and ask:

> Use C64 Dev Machine's MCP tools to inspect my scratch project, then add one
> unconnected comment saying "Hello from Claude!". Use the returned workspace
> key. Do not build, save or change anything else.

The host should offer its normal approval flow for the write tool.

### Codex CLI (Windows PowerShell)

From the repository root, with Codex CLI already installed and authenticated:

```powershell
$bridge = (Resolve-Path .\tools\cdm-mcp\bridge.mjs).Path
$node = (Get-Command node).Source
codex mcp add c64-dev-machine -- $node $bridge
codex mcp list
```

Launch a new local Codex session. Copy the same pairing key with `--pair |
Set-Clipboard`, pair in the editor with Ctrl+Shift+F12, and ask the same test
prompt using "Hello from Codex!". Do not run Claude and Codex bridges on the
same port simultaneously. The default bridge environment works for a normal
local session on the same Windows account. Custom `CDM_MCP_PORT` or
`CDM_MCP_TOKEN_FILE` values must also be supplied to Codex via its `--env` options.

This patch does **not** attach your PC to the existing hosted ChatGPT conversation.
The local MCP host is the process that can use the local editor connection.

## Tools and constraints

| Tool | Effect |
|---|---|
| `cdm_status` | Bridge status only; it does not prove the editor is responding. |
| `cdm_ping` | A live round trip to Dev Machine. |
| `cdm_project_summary` | Bounded node page; IDs, types, titles, positions and truncated comment text. |
| `cdm_focus_node` | Pan to a UID using the current `expected_workspace` key. |
| `cdm_add_comment` | Create an unconnected comment, record native undo states, mark the workspace modified and focus it. |

For paginated summaries, pass `offset: next_offset` until `has_more` is false.
A byte-size cap can shorten a page before the requested `limit`. This is not a
complete project export: asset contents, generated code and full binary blobs
are not sent. Node text is untrusted project data, not instructions to the AI.

Creation accepts one line of **1–256 printable ASCII characters** and optional
numeric `x`/`y` coordinates in the range -1,000,000 to 1,000,000. Defaults place
the comment near the current view. The <=200-node guard limits snapshot costs;
it is not a universal performance guarantee. Existing binary assets can still
make native editor operations expensive.

The `workspace_key` checks the first live node instance and the node count. It
changes on typical load/undo/add operations. It is a conservative context check,
**not a full content revision or transaction system**. Re-read the summary after
an edit and avoid simultaneous manual editing during this test.

Native undo uses disk snapshots. The test writes those undo files and marks the
project dirty. **Normal autosave remains active according to your existing
settings.** There is no explicit MCP save call, but autosave can persist the test
comment. Use a scratch project; do not assume "no save tool" means no disk writes.

## Pairing and safety

The bridge binds **127.0.0.1 only**. The editor connects outward using raw async
TCP. There is no open listening port inside GameMaker and no external service.
The bridge uses a random 32-byte key stored by default at
`~/.c64-dev-machine-mcp/token`, outside the repository. The file uses owner-only
permissions where supported; Windows inherits your user-profile permissions.
Treat this file and clipboard key as secrets. Never paste the key into AI chat.
The app only holds its copy in memory until disconnected or exited.

This is local token authentication, not TLS or a security boundary against
malicious software running as your own OS user. Only run the bridge you trust.
An AI host can send returned node text to its model service; the local bridge
itself makes no external network connection.

One editor and one pending editor command are allowed. Commands are validated
on both sides, lines and queues are bounded, incoming event buffers are copied
before they expire, requests have IDs, and a processed request is not executed
again under the same connection ID. Native editing happens on the runner's main
thread, one command per frame. This does not make the compiler non-blocking and
does not fix existing editor hangs.

On timeout/cancellation, the bridge closes the connection and does not retry.
**An edit already started may have completed.** Inspect the project or read it
again after explicitly reconnecting before asking for the same edit again.
There is no promise of remote rollback after a lost response.

## Troubleshooting

- **No MCP startup badge/shortcut:** confirm you rebuilt the patched project,
  not the old exported EXE. The startup badge intentionally disappears.
- **OFF / editor busy:** close welcome, dialogs, code/text editing and release
  the mouse. Pair or issue the tool call again only when idle.
- **Connection refused / never connected:** start the smoke test or the MCP
  host first, copy its pairing key, then pair in the application.
- **Port already in use:** exit the other smoke/client bridge. Do not kill an
  unrelated process. Another port can be selected using `CDM_MCP_PORT` (1024–65535)
  before generating the key and starting the bridge; the pairing key includes it.
- **Workspace changed:** read `cdm_project_summary` again and use its new key.
- **Timeout:** inspect the project first. Avoid large projects and modal dialogs.
  No tool can make a blocked GameMaker runner reply until it resumes.
- **Windows firewall prompt:** this prototype needs only a local loopback
  connection. Do not expose it on public networks or forward the port.

## Validation status and tests

```powershell
node --test tools/cdm-mcp/test.mjs
```

The supplied automated suite checks the Node bridge using a **simulated editor**,
including real stdio subprocess MCP traffic, authentication, framing, argument
validation, timeout, cancellation and disconnection. It does not execute GML.
GameMaker compilation, Windows/macOS UI behaviour and actual native undo/redo
must be checked with the rebuilt application. See the supplied audit for the
exact source-inspection and patch-validation scope.

## Remove the prototype

Quit the MCP client/bridge and Dev Machine. Close GameMaker. At the repository root:

```powershell
git apply -R --check "$env:USERPROFILE\Downloads\cdm_mcp_smoke_v1.patch"
git apply -R "$env:USERPROFILE\Downloads\cdm_mcp_smoke_v1.patch"
```

Do not force reversal over subsequent changes. GameMaker may reserialize the
project file, so review a failed reverse check rather than discarding unrelated
work. Remove only this server entry from your host's configuration; for Codex,
use `codex mcp remove c64-dev-machine`. Rebuild the editor after removing it.
Reverting the code does not remove comments already saved in a test workspace.
The local token file may be deleted separately once all bridges are closed.

## Primary references

- GameMaker raw async connection:
  https://manual.gamemaker.io/monthly/en/GameMaker_Language/GML_Reference/Networking/network_connect_raw_async.htm
- GameMaker network events/buffer lifetime:
  https://manual.gamemaker.io/monthly/en/The_Asset_Editors/Object_Properties/Async_Events/Networking.htm
- MCP lifecycle, stdio and tools (explicitly targeted protocol revision):
  https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
  https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
  https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- Local-host configuration:
  https://py.sdk.modelcontextprotocol.io/get-started/real-host/
  https://developers.openai.com/codex/mcp
