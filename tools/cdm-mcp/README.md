# C64 Dev Machine MCP v0.2

Control a running C64 Dev Machine from a local MCP host, including Codex dictation. The host turns your spoken request into MCP calls; this bridge does not record or transcribe audio.

## Supported project workflow

Twenty tools cover connection status, capabilities, paginated project inspection, node inspection/focus, creating and editing nodes, connecting/disconnecting/deleting nodes, undo/redo, creating/listing byte and text assets, new/open/save, and native build/run with status polling. The 75 node factories use the editor's own defaults. MACRO_CODE supports assembly source. Specialized sprite, bitmap, map and music authoring interfaces are not exposed as MCP tools.

Use cdm_capabilities first, then cdm_project_summary. Use a fresh workspace_key as expected_workspace before every operation that requires it. Manual edits, automatic layout, loading and undo may change the key. After a timeout, inspect before retrying: a mutation may already have completed.

Create a node with after_uid to connect it after another node on its spine. An ORG anchor starts an ORG chain. Read a macro's defaults before changing its instruction rows; retain their shape and opcode. Internal macro children and INIT/ORG anchors cannot be detached or deleted. Use text for COMMENT, MACRO_CODE, LABEL and RAW_DATA. Close modal dialogs and code editors before MCP edits.

## Install and pair once

Requires Node.js 22+; no npm dependencies. Rebuild the GameMaker project or run the supplied v0.2 Windows build. Old exported executables do not gain these features from bridge updates alone.

Existing Codex configuration can keep pointing to tools/cdm-mcp/bridge.mjs. Refresh/restart its MCP connection once after upgrading so it discovers the new tools. If a v0.1 bridge is still running, stop that old connection first.

For a new Codex installation, from the repository root:

```powershell
$bridge = (Resolve-Path .\tools\cdm-mcp\bridge.mjs).Path
$node = (Get-Command node).Source
codex mcp add c64-dev-machine -- $node $bridge
```

With the MCP host enabled, copy the local key without posting it in chat:

```powershell
node tools/cdm-mcp/bridge.mjs --pair | Set-Clipboard
```

Press Ctrl+Shift+F12 in Dev Machine. Successful pairing is remembered in the editor's local cdm-mcp-pairing.ini (Windows commonly uses %LOCALAPPDATA%\C64DevMachine_win). Subsequent launches reconnect automatically; clipboard access is only used for explicit pairing. Ctrl+Shift+F12 disconnects and disables auto-connect. Ctrl+Shift+Alt+F12 replaces the saved key from the clipboard. Pairing keys are local secrets stored in the user profile, never in exported projects.

Multiple Codex tasks and terminal clients can now share one authenticated loopback broker on port 5150. Hosts start it automatically; no separate terminal is needed. It serializes editor operations and exits after 60 seconds without MCP clients. Keep only one editor paired. CDM_MCP_PORT and CDM_MCP_TOKEN_FILE must match across clients if customized. Claude configuration is available from bridge.mjs --claude-config.

## Build and run

cdm_build with run=true queues the same native pipeline used by F5. Poll cdm_build_status: queued, building, launch_pending, launch_requested, built, attention_required or failed. launch_requested means the OS launch was requested; it does not prove emulator execution. Native warnings are returned as attention_required; inspect and fix the project before building again. run=false builds without launching VICE. Native edition restrictions still apply.

For a simple green border test, connect a COMMENT containing "test is okay", a NORMAL node with [["lda_imm",5],["sta_abs",53280],["cli",0]], and a separate NORMAL node with [["rts",0]] after SYSTEM INIT. The native flow checker recognizes an RTS node by its first instruction. MACRO_CODE can alternatively contain the complete assembly block ending in RTS. Save, build/run, then verify the green border and BASIC READY prompt in VICE.

Saving requires a .json path and explicit overwrite=true for existing files. New/open reject unsaved changes unless discard_unsaved=true is provided. A recovery project is saved before new/open, with its path returned. Project load uses the native loader; malformed projects may still require restoring that recovery copy.

Byte assets accept 1..4096 bytes; text assets accept up to 4096 characters, using native C64 text conversion. Use replace=true to overwrite an existing asset of the same type. Commands have a 28,000-byte serialized budget. Large source blocks should be split across nodes. The legacy cdm_add_comment smoke-test tool retains its original small-project restrictions; prefer cdm_create_node for normal work.

## Verification

```powershell
node --test tools/cdm-mcp/test.mjs
```

The automated bridge tests cover framing, authentication, validation, timeouts, cancellation, multiple clients and oversized commands. A rebuilt Windows editor was also tested live: node creation/editing/wiring, undo/redo, byte/text assets, save/load, new-project reconnection, native F5 and VICE. The emitted PRG bytes and the visible green border/BASIC READY prompt were checked. No claims are made about every specialized macro or asset type.
