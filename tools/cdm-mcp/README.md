# C64 Dev Machine MCP v0.4

Pro only: MCP is enabled only when global.lite == 0. Lite does not create the MCP controller, read its saved pairing key, show its badge, or listen for its shortcut.

Control a running C64 Dev Machine from a local MCP host, including Codex dictation. The host turns your spoken request into MCP calls; this bridge does not record or transcribe audio.

## Supported project workflow

Twenty-eight tools cover asset contents for every editor and turn-taking (both below), connection status, capabilities, paginated project inspection, node inspection/focus, creating and editing nodes, connecting/disconnecting/deleting nodes, undo/redo, creating/listing byte and text assets, new/open/save, and native build/run with status polling. The 75 node factories use the editor's own defaults. MACRO_CODE supports assembly source.

Use cdm_capabilities first, then cdm_project_summary. Use a fresh workspace_key as expected_workspace before every operation that requires it. Manual edits, automatic layout, loading and undo may change the key. After a timeout, inspect before retrying: a mutation may already have completed.

Create a node with after_uid to connect it after another node on its spine. An ORG anchor starts an ORG chain. Read a macro's defaults before changing its instruction rows; retain their shape and opcode. Internal macro children and INIT/ORG anchors cannot be detached or deleted. Use text for COMMENT, MACRO_CODE, LABEL and RAW_DATA. Close modal dialogs and code editors before MCP edits.

## Editing assets (every editor)

Every asset type, including sprites, charsets, bitmaps, maps, metatile sets, music and SFX, HUDs, vector pictures and samples, can be read and changed. cdm_capabilities lists asset_types.

- cdm_read_asset returns an asset in its saved form: exactly what a project file stores, plus the buffer.
  - Small meta fields come back in full. Large ones appear under large_fields; fetch them with keys or slices (offset/limit).
  - bytes returns up to 8192 buffer bytes as hex.
  - pixels returns SPRITE_SET or CHAR_SET items as rows: '.'/'#' per hi-res pixel, or '0'-'3' per multicolour pixel.
- cdm_write_asset changes or creates an asset:
  - create_type builds a new asset with the editor's defaults, as the ADD ASSET menu does.
  - meta replaces saved fields. Only fields cdm_read_asset shows can be written, and each must keep its shape: numbers stay numbers, and array elements match the existing ones.
  - slices overwrite part of a large array, such as a map's char_grid.
  - bytes writes hex at buffer offsets; buffer_size resizes the buffer first. Raw bytes are accepted only where the bytes are the asset: SPRITE_SET, CHAR_SET, BITMAP, SAMPLE, SID_MUSIC, SFX_DATA, BMP_OBJECTS, and BYTE_DATA in save-file mode. Every other type generates its bytes from its fields, so write meta or slices instead.
  - An empty array field can only take new entries where the shape is known (for example LINE_COLL lines, VECTOR_BITMAP commands, linked_assets, and the music and HUD fields the loader repairs); otherwise add one entry in Dev Machine first.
  - pixels writes sprite or character rows.
  - address, load_later, d64_filename and linked_assets change the asset entry itself.
- cdm_delete_asset removes an asset and its LOAD_ORG/LOAD_REU links.
- cdm_revert_asset undoes the latest MCP create, write or delete of an asset. Ctrl+Z does not cover asset contents; the last 30 MCP asset changes are kept for this session.
- cdm_render_asset saves the editor's preview as a PNG and returns its path: one sprite of a SPRITE_SET, a CHAR_SET or BITMAP sheet, or another type once its preview has been drawn.

A write rebuilds the asset through the project loader, so the asset ends up exactly as if the project had been saved and reopened, with the same validation, defaults and previews. Close the asset viewer/editor in Dev Machine before writing: its working copy would otherwise overwrite the change. A CHAR_SET whose bytes are written is detached from its source file, because project load otherwise reloads charsets from disk.

Data layouts:
- **SPRITE_SET:** 64 bytes per sprite: 21 rows × 3 bytes, MSB is the leftmost pixel, then 1 pad byte. sprite_mcs[i] is 1 for multicolour; sprite_ucs[i] is the sprite colour. bg_col, mc1_col and mc2_col are shared. Change the sprite count with buffer_size (64 per sprite, at most 64 sprites).
- **CHAR_SET:** 8 bytes per char, top row first. mc_mode is 0 hi-res, 1 multicolour or 2 ECM. Colours are mc_fg, mc_bg, mc_col1, mc_col2 and ecm_bg1-3. buffer_size is 8 per char, at most 256 chars.
- **BITMAP:** Koala layout.

  | Mode | Bytes | Layout |
  |---|---|---|
  | Multicolour | 10003 | $00,$60 header, 8000 bitmap, 1000 screen RAM (high nibble %01, low nibble %10), 1000 colour RAM (%11), background |
  | Hi-res (bmp_mode HIRES) | 9002 | header, 8000 bitmap, 1000 screen RAM (high nibble ink, low nibble paper) |

  The bitmap is cell-ordered: 8 bytes per 8×8 cell, 40 cells per row. coll_types[1000] holds per-cell collision tags.
- **MAP_DATA:** char_grid, colour_grid and override_grid (0 hi-res / 1 multicolour per cell) each hold grid_w×grid_h entries, row-major. map_w/map_h is the visible map inside the grid. chr_asset names its CHAR_SET. The buffer is regenerated from the grids.
- **META_TILESET:** stamp_w×stamp_h stamps in stamp_data (char indices, stamp after stamp). char_lut[256] holds per-char colours (bit 4 = multicolour). maps[] holds metatile indices per map (-1 = empty), with sizes in map_w[]/map_h[]. Keep map_size_key equal to "WxH" of the stamp size.
- **MUSIC_MAKER / SFX_MAKER:**
  - instruments[] is `{name, text, attack, decay, sustain, release, pulse_width, ...}`. text is the instrument program, for example `"$21\nN\nD8\n---"`.
  - patterns[] is `{name, pattern_len, steps[{note "C-4"|""|"---"|"+++", instr_idx, empty, cmd, cmd_val}]}`.
  - songs[] is `{name, loop, loop_row, order[{v1, v2, v3 pattern indices or -1, t1..t3 transposes, repeat_short, force_len}]}`.
  - play_speed is frames per row. The editor normalises everything on write, as on load.
- **VECTOR_BITMAP:** pages[{commands, bg, col1, col2, col3}], where commands are `{op, ...}` primitives in 320×200 space (line, rect, ellipse, fill, plot, setcol, ...).
- **HUD:** char_grid and colour_grid hold hud_w×hud_h entries, plus fields[].
- **ANIMATION:** anim_data rows `[name, delay, loop, 8 frame lists, reserved]`.
- **Others:** LINE_COLL lines[], ROOM_MAP rooms[], PICKUP_TABLE pick, SPRITE_MASK, BMP_OBJECTS, SAMPLE, TEXT_DATA text, BYTE_DATA byte_string. Read one first and keep its shape.

## Taking turns with the assistant

The user and the assistant can edit the same project in alternating turns. The editor decides whose turn it is and shows it on the C64 DEV MACHINE badge (top left):

- YOUR TURN (green): edit as normal. When you are done, rest the pointer on the badge for 2 seconds; a yellow bar fills while you hover. The turn passes to the assistant as soon as no editor or dialog is open.
- CLAUDE EDITING (orange, with a pulsing frame round the window): node editing, palette clicks and workspace keyboard shortcuts are locked; panning and zooming still work. Click the badge to take the turn back early. Anything you still manage to change (for example in the asset panel) turns the badge red (CLAUDE EDITING!) and is reported to the assistant.

Assistant side:

1. cdm_wait_for_turn switches the editor into turn mode and blocks until the user hands over (timeout_seconds, default 300; timed_out=true means wait again). Its result has owner="claude" and changes: nodes added, deleted, edited (title, content, wiring, attached/detached, reordered in a chain) and moved, plus assets added, deleted and changed, each with uid/name, type and title. Long lists are capped at 25 entries with full counts.
2. Edit as usual (fresh workspace_key first). cdm_turn_status shows whether the user took the turn back.
3. cdm_end_turn hands the turn back, with an optional summary the user sees on the badge tooltip; stop=true leaves turn mode. It also reports any changes the user made during the assistant's turn.

While it is the user's turn, every edit, save, load, build and focus call is refused. Disconnecting (or OPTIONS > MCP off) always ends turn mode and unlocks the editor.

Agents that only act within a turn (such as Claude Code) should wait with a background command instead of the blocking tool. The command exits when the user hands over (exit code 0, the changes on stdout) or after the timeout (exit code 2, default 3600 seconds):

```powershell
node tools/cdm-mcp/bridge.mjs --wait-turn 3600
```

It connects through the shared broker like any other client and keeps the broker alive while it waits.

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

Press Ctrl+Shift+F12 in Dev Machine, or simply switch back to the editor window after hovering or clicking MCP-CON: for 15 minutes after that, returning to the window checks the clipboard once for a cdm1: pairing key and pairs with it (nothing else on the clipboard is used). Hovering MCP-CON shows step-by-step instructions for the current connection state. Successful pairing is remembered in the editor's local cdm-mcp-pairing.ini (Windows commonly uses %LOCALAPPDATA%\C64DevMachine_win). Subsequent launches reconnect automatically; clipboard access is only used for explicit pairing. Ctrl+Shift+F12 disconnects and disables auto-connect. Ctrl+Shift+Alt+F12 replaces the saved key from the clipboard. Pairing keys are local secrets stored in the user profile, never in exported projects.

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

The automated bridge tests cover framing, authentication, validation, timeouts, cancellation, multiple clients, oversized commands and turn waiting (hand-over, timeout, cancellation, disconnect). A rebuilt Windows editor was also tested live: node creation/editing/wiring, undo/redo, byte/text assets, save/load, new-project reconnection, native F5 and VICE. The emitted PRG bytes and the visible green border/BASIC READY prompt were checked. No claims are made about every specialized macro or asset type.
