/// @desc obj_asset_manager Create
global.is_any_text_active = false;
global.mouse_in_asset_panel = false;
// Multi-select state for CHAR_SET grid
chr_multi_select    = []; // array of char indices currently selected
chr_clipboard       = []; // array of structs: { bytes: [8 bytes] } per copied char
chr_clipboard_owner = ""; // asset name the clipboard was copied from (for badge display)
chr_paste_anchor    = -1; // last clicked char index (used as paste start when no selection)
// Ctrl+drag selection state
chr_drag_active     = false; // true while a Ctrl+LMB drag is in progress
chr_drag_mode       = "add"; // "add" or "remove" — set by the tile under the initial press
chr_drag_last_idx   = -1;    // last tile toggled this stroke (prevents repeat on same cell)

map_chr_btn_y         = 0;
map_chr_picker_draw_y = 0;
// bitmap editor:
bmp_ref_asset_name = "";
bmp_ref_vy1        = 0;
bmp_ref_found      = false;
bmp_ref_x          = 0;

chr_active_mc_colour = 0;

// SLICE modal result channel (published by obj_integer_box)
global.integer_result = "";
global.integer_box_open = false;

// Find the max whole-number scale that fits inside the current window size
var _scale_x = window_get_width() div 480;
var _scale_y = window_get_height() div 300;

// The base cap is the smaller of the two (so it doesn't clip off screen), minimum 1x
bmp_ui_zoom_cap_base = 3;
bmp_ui_zoom_cap      = 3;

// -------------------------------------------------------
// PANEL LAYOUT
// -------------------------------------------------------
var _gui_w      = global.gui_w;
var _gui_h      = display_get_gui_height();
panel_w         = 270;
panel_x         = _gui_w - panel_w - 30;
panel_y = 410;
panel_h         = _gui_h - panel_y + 200;
panel_scroll    = 0;
panel_max_scroll = 0;
item_h          = 36;
hover_idx       = -1;
hover_pos       = -1;
asset_sort_mode = "ADDR"; // "NAME", "TYPE", or "ADDR" (insertion order)
// Cached display order, plus the signature it was built from. The panel asks
// for the sorted order every frame, and re-sorting a few hundred assets every
// frame with a comparator that upper-cases two names per comparison is the
// most expensive thing the editor does. The order only actually changes when
// a name, type or address changes, an asset is added or removed, or the sort
// mode is switched - so that is exactly what the signature records.
// Declared here so scr_asset_sorted_indices never has to test for them.
// asset name -> asset struct, rebuilt at most once a frame. scr_reu_find_asset
// used to answer every lookup with a linear scan of the whole list, and the
// MACRO_REU node draw asks it once per linked asset, per node, per frame.
asset_name_map        = ds_map_create();
asset_name_map_tick   = -1;
asset_name_map_size   = -1;

asset_sort_cache      = [];
asset_sort_cache_mode = "";
asset_sort_sig_name   = [];
asset_sort_sig_type   = [];
asset_sort_sig_addr   = [];
// -------------------------------------------------------
// ADD ASSET DROPDOWN
// -------------------------------------------------------
add_dropdown_open   = false;
add_dropdown_hover  = -1;
asset_types = [
    "SPRITE_SET",
    "BITMAP",
    "SID_MUSIC",
	"SFX_DATA",   
    "CHAR_SET",
    "MAP_DATA",
	"TEXT_DATA",
	"BYTE_DATA",
	"VECTOR_BITMAP",
	"BITMAP_BUILDER",
	"MUSIC_MAKER",
    "SFX_MAKER",
    "LOAD_ORG",
	"LOAD_REU",
	"META_TILESET",
	"LINE_COLL",
	"HUD",
];
// -------------------------------------------------------
// ASSET VIEWER
// -------------------------------------------------------
viewer_open     = false;
viewer_asset    = -1;
// -------------------------------------------------------
// ASSET LIST
// -------------------------------------------------------
asset_list = ds_list_create();
// -------------------------------------------------------
// TYPE COLOURS
// -------------------------------------------------------
type_colours = {
    SFX_MAKER : make_color_rgb(100, 200, 220),
    SPRITE_SET : make_color_rgb(200, 120,  40),
    BITMAP     : make_color_rgb( 80, 180, 220),
    SID_MUSIC  : make_color_rgb(180,  60, 180),
    CHAR_SET   : make_color_rgb(255, 220,  50),
    MAP_DATA   : make_color_rgb( 80, 200, 120),
	SFX_DATA   : make_color_rgb(120,  60, 200),   
	TEXT_DATA  : make_color_rgb(160, 230, 160),
    BYTE_DATA  : make_color_rgb(180, 120, 255),
    VECTOR_BITMAP : make_color_rgb(120, 200, 220),
    BITMAP_BUILDER : make_color_rgb(230, 140,  90),
    LOAD_ORG      : make_color_rgb(200, 160,  40),
    LOAD_REU      : make_color_rgb(100, 200, 180),
    META_TILESET  : make_color_rgb(120, 200, 255),
    META_MAP      : make_color_rgb( 80, 140, 255),
    LINE_COLL     : make_color_rgb(255, 100, 100),
    HUD           : make_color_rgb( 90, 220, 190)
};
// -------------------------------------------------------
// NAME EDITING
// -------------------------------------------------------
editing_name     = false;
editing_idx      = -1;
editing_string   = "";
editing_cursor   = 0;
editorClosed     = 1;
// -------------------------------------------------------
// DROP DOWN PICKER
// -------------------------------------------------------
spr_picker_open      = false;
spr_picker_node      = noone;
spr_picker_x         = 0;
spr_picker_y         = 0;
spr_picker_hover     = -1;
// -------------------------------------------------------
// BITMAP_BUILDER SRC/DST PICKER
// -------------------------------------------------------
// Shared picker for the two BITMAP slots on a BITMAP_BUILDER asset. The editor
// opens it and records which field asked; Step commits the choice back.
bbuild_picker_open  = false;
bbuild_picker_field = "SRC";   // "SRC" or "DST"
bbuild_picker_x     = 0;
bbuild_picker_y     = 0;
bbuild_picker_hover = -1;

// -------------------------------------------------------
// BITMAP ASSET
// -------------------------------------------------------
bmp_picker_open  = false;
bmp_picker_node  = noone;
vbmp_picker_open = false;
vbmp_picker_node = noone;
bmp_picker_hover = -1;
// -------------------------------------------------------
// ADDRESS EDITING
// -------------------------------------------------------
editing_address      = false;
editing_address_idx  = -1;
editing_addr_string  = "";

// NEW: Required by your Step event logic
byte_data_editing    = false;
byte_data_edit_idx   = -1;
byte_data_edit_string = "";


// -------------------------------------------------------
// SID ASSET
// -------------------------------------------------------
sid_picker_open  = false;
sid_picker_node  = noone;
sid_picker_hover = -1;
// -------------------------------------------------------
// SPRITE ASSET
// -------------------------------------------------------
colour_picker_open  = false;
colour_picker_asset = -1;
colour_picker_field = 0;
// -------------------------------------------------------
// CHAR_SET ASSET
// -------------------------------------------------------
chr_picker_open  = false;
chr_picker_node  = noone;
chr_picker_hover = -1;

chr_active_mc_colour = 3;
chr_active_ecm_bg    = 0;
chr_active_ecm_target = "FG"; // "FG" or "BG" — last swatch group picked; drives ECM paint behaviour
chr_grid_draw_x      = 0;
chr_grid_draw_y      = 0;
chr_grid_cell_px     = 0;


// NEW: Support for the memory-resident charset viewer
chr_mc_mode      = false; // Global toggle for current view
chr_edit_tile    = 0;     // Currently selected tile for editing (if you add a pixel editor later)

// -------------------------------------------------------
// MAP ASSET
// -------------------------------------------------------
map_picker_open  = false;
metamap_picker_open       = false;
metamap_picker_node       = noone;
metamap_picker_hover      = -1;
metamap_picker_name_idx   = 1;   // instructions[0] index the picked tileset name writes to
metamap_picker_mapidx_idx = 2;   // instructions[0] index that gets reset to 0 on tileset change
map_picker_node  = noone;
map_picker_hover = -1;
editing_map_dim       = false;  // true while editing W or H
editing_map_field     = "";     // "W" or "H"
editing_map_string    = "";
editing_map_asset_idx = -1;

// -------------------------------------------------------
// SFX_DATA ASSET
// -------------------------------------------------------
sfx_picker_open  = false;
sfx_picker_node  = noone;
sfx_picker_hover = -1;
sfx_picker_field = "asset";

// -------------------------------------------------------
// LOAD_ORG ASSET PICKER
// -------------------------------------------------------

// LOAD_ORG ASSET PICKER (asset viewer)
	load_org_picker_open  = false;
	load_org_picker_asset = -1;
	load_org_picker_hover = -1;

	// PNG STRIP -> SPRITE_SET import confirm panel (scr_asset_spr_import_png_strip)
	pngstrip = {
		open     : false,
		asset    : -1,
		path     : "",
		spr      : -1,
		w        : 0,
		h        : 0,
		cols     : 0,
		rows     : 0,
		count    : 0,
		cell_w   : 24,
		px       : [],
		hist     : array_create(16, 0),
		order    : [0, 1, 2],
		bg       : 0,
		col1     : 1,
		col2     : 2,
		bg_i     : 0,
		col1_i   : 1,
		col2_i   : 2,
		mode     : 0,
		frame_mc : array_create(64, 0),
		frame_uc : array_create(64, 1),
		warn     : 0,
		hr_count : 0,
		mc_count : 0
	};

	// LOAD_REU manifest picker (asset viewer)
	load_reu_picker_open  = false;
	load_reu_picker_asset = -1;
	load_reu_picker_hover = -1;
	// Asset groups. A group name present in this map is OPEN; absent is
	// closed, so a newly imported group starts folded with nothing to set.
	asset_group_open      = ds_map_create();
	// Registered group names. Groups live here, never in asset_list, so the
	// compile chain, memory bar and asset pickers never see them.
	asset_groups          = [];
	// asset name -> "LOAD_ORG" / "LOAD_REU", rebuilt once per Draw. The
	// membership badge used to be worked out by rescanning every manifest's
	// linked_assets for EVERY visible row, which on a project with a few
	// hundred linked bitmaps is tens of thousands of string compares a frame.
	// Declared here so the draw event never has to test for its existence.
	tag_member_map        = ds_map_create();
	// Drag an asset row by its grip to move it between groups.
	asset_drag_idx        = -1;
	asset_drag_armed      = false;
	asset_drag_x          = 0;
	asset_drag_y          = 0;
	asset_drag_over_group = "";
	asset_drag_over_loose = false;
	asset_group_rows      = [];

	load_reu_rows_y       = 0;
	load_reu_add_y        = 0;

	// LOAD_REU manifest scrolling. A REU image can hold hundreds of frames, so
	// the row list is windowed and the ADD / AUTO PACK buttons are pinned below
	// it instead of being pushed off the bottom of the viewer panel.
	load_reu_scroll       = 0;
	load_reu_scroll_max   = 0;
	load_reu_rows_visible = 1;
	load_reu_list_y1      = 0;
	load_reu_list_y2      = 0;
	load_reu_sb_x1        = 0;
	load_reu_sb_x2        = 0;
	load_reu_sb_drag      = false;

	// LOAD_REU manifest drag-to-reorder — only allowed between rows whose
	// asset type matches the row being dragged, since MACRO_REU INDEXED
	// mode's index numbers are assigned per-type in link order.
	reu_drag_row  = -1;
	reu_drag_over = -1;
	reu_drag_type = "";

	// META_TILESET map painting — last painted cell this stroke, used to
	// interpolate a line when the mouse moves faster than the paint loop
	// polls (fast drags otherwise leave gaps between painted cells).
	// Sentinel (-999999) means "no stroke in progress".
	map_paint_last_col = -999999;
	map_paint_last_row = -999999;

	// MACRO_REU ASSET-mode pickers
	reu_manifest_picker_open  = false;
	reu_manifest_picker_node  = noone;
	reu_manifest_picker_hover = -1;
	reu_asset_picker_open     = false;
	reu_asset_picker_node     = noone;
	reu_asset_picker_hover    = -1;

	// MACRO_LOADER PICKERS (node-side)
	loader_org_picker_open  = false;   // pick which LOAD_ORG asset
	loader_org_picker_node  = noone;
	loader_org_picker_hover = -1;

	loader_file_picker_open  = false;  // pick which file inside the LOAD_ORG
	loader_file_picker_node  = noone;
	loader_file_picker_hover = -1;

	// LOAD_ORG ASSET PICKER (legacy duplicate marker — kept for next region)

// -------------------------------------------------------
// MAP VIEWER CHARSET PICKER
// -------------------------------------------------------
map_chr_picker_open  = false;
map_chr_picker_asset = -1;
map_chr_picker_hover = -1;
map_chr_btn_y = 0;

// META_TILESET picker (used by META_MAP viewer)
meta_ts_picker_open  = false;
meta_ts_picker_node  = noone;
meta_ts_picker_hover = -1;
meta_ts_btn_y        = 0;

// META_TILESET map clipboard — copymap/pastemap. Holds one map's placement
// grid in memory until replaced by a new copy. -1 = empty (paste greyed out).
// Stores cols/rows so paste can reject a mismatched stamp-size target.
metamap_clip_grid = -1;
metamap_clip_cols = 0;
metamap_clip_rows = 0;
// -------------------------------------------------------
// AUTO RELAODING
// -------------------------------------------------------
_last_focus = true;
reload_notify_names = [];
reload_notify_timer = 0;

// -------------------------------------------------------
// GUI STATE TRACKING
// -------------------------------------------------------
last_gui_w = global.gui_w;
last_gui_h = display_get_gui_height();

// -------------------------------------------------------
// TEXT ASSET
// -------------------------------------------------------

text_edit_path  = "";
text_edit_asset = -1;

// -------------------------------------------------------
// SPR ASSET
// -------------------------------------------------------

spr_edit_path  = "";
spr_edit_asset = -1;
spred64_btn_y  = 0;
spr_edit_md5 = "";
spred64_open = false;
spred64_pending_path = "";
delete_warn_timer = 0;
delete_warn_name  = "";
_ref_collect     = [];
_ref_asset_name  = "";

// -------------------------------------------------------
// SPRED64 V2 (BUILT-IN SPRITE EDITOR)
// -------------------------------------------------------
// Y position of the V2 button — stored in Draw GUI, read in Step
spred64_v2_btn_y = 0;
// Working state for the built-in sprite editor. All fields initialised
// here so the editor never has to test variable_struct_exists at runtime.
spred64_v2 = {
    active           : false,
    asset_index      : -1,
    // Pixel data — working copy, unpacked from _asset.buffer on open
    // 1 bit per pixel, 504 pixels per slot, 64 slots = 32256 entries
    bits             : array_create(64 * 504, 0),
    sprite_modes     : array_create(64, 0),      // 0 = HR, 1 = MC, per slot
    sprite_uc        : array_create(64, 1),      // unique colour pen 0-15
    bg_col           : 0,
    mc1_col          : 1,
    mc2_col          : 2,
    used_count       : 1,
    // Editor state
    selected_slot    : 0,
    active_colour    : 3,                        // 1=MC1, 2=MC2, 3=UC
    dirty            : false,
    // Multi-select for batch mode/colour edits. One boolean per slot.
    // CTRL+click a picker cell to toggle its membership. When any slot
    // is selected, the HR/MC toggle and the UC palette apply to every
    // selected slot at once. A plain (non-CTRL) click clears the set.
    // Sized to the 64-slot hardware cap; batch loops bound to used_count
    // so a stale entry on a removed slot can never refresh out of range.
    multi_select     : array_create(64, false),
    // Pixel editor surface — one slot at a time, rebuilt on edit / slot change
    edit_surface     : -1,
    // Dirty timer (mirrors bitmap editor pattern — auto-commit after idle)
    dirty_timer      : -1,
    // Compositor — 4x4 grid x 8 layers, sparse cells, frame-indexed for phase 3.
    // frames[0].cells is an array of { layer, row, col, slot, xo, yo, expand }.
    // Empty positions are absent from the array (truly sparse).
    // Mirrored to/from _asset.meta.compositor on open/close.
    compositor : {
        frames       : [ { cells : [] } ],
        active_layer : 0,
        active_frame : 0,
        active_cell  : -1
    },
    // Hover tracking for the compositor grid (updated each draw frame).
    // Used by the layer-button click handler so switching layers picks up
    // the cell at the currently-hovered (row, col) for editing.
    comp_hover_layer : -1,
    comp_hover_row   : -1,
    comp_hover_col   : -1,
    // Anchor position — the (row, col) the user last selected in the
    // compositor grid. Persists across layer switches so the COMP view
    // and pan stay locked to the user's chosen position even when the
    // new layer has no cell there. -1 means no anchor set yet.
    // Updated whenever a grid cell is clicked, and whenever a layer
    // switch lands on a cell (carries the cell's row/col forward).
    comp_anchor_row  : -1,
    comp_anchor_col  : -1,
    // Flood-fill arming state. When true, the FILL button is "armed" — the
    // next click on the pixel canvas runs the flood from the clicked pixel
    // and disarms. Re-clicking the FILL button toggles arming off.
    fill_armed       : false,
    // ROT90 source-of-truth system. Each slot keeps a pristine snapshot
    // taken on its first ROT90 click; subsequent ROT90s re-render from
    // that snapshot at the current rotation angle, so distortion never
    // accumulates across multiple rotations. Painting/flip/clear/fill
    // invalidate the snapshot so the next ROT90 takes a fresh one.
    //   rot_sot       — flat array, 64 * 504 bits, mirrors bits[] layout
    //   rot_angle     — per-slot rotation angle, 0=0°, 1=90°, 2=180°, 3=270°
    //   rot_sot_valid — per-slot, true when this slot's SOT is populated
    rot_sot          : array_create(64 * 504, 0),
    rot_angle        : array_create(64, 0),
    rot_sot_valid    : array_create(64, false),
    // Pan/wrap state. While active, mouse movement over the canvas shifts
    // the sprite bits[] with wraparound (real-time, step-based to match
    // C64 pixel granularity). Triggered by holding MMB, or SPACE + LMB.
    //   pan_active     — true while a pan drag is in progress
    //   pan_anchor_mx  — mouse X at pan start (screen pixels, unused but kept for diag)
    //   pan_anchor_my  — mouse Y at pan start
    //   pan_accum_dx   — accumulated screen-pixel mouse dX since last shift step
    //   pan_accum_dy   — accumulated screen-pixel mouse dY since last shift step
    //   pan_last_mx    — last seen mouse X (for frame-to-frame delta)
    //   pan_last_my    — last seen mouse Y
    //   pan_slot       — slot being panned (locked at start)
    pan_active       : false,
    pan_anchor_mx    : 0,
    pan_anchor_my    : 0,
    pan_accum_dx     : 0,
    pan_accum_dy     : 0,
    pan_last_mx      : 0,
    pan_last_my      : 0,
    pan_slot         : -1,
    // Animation playback state. Drives compositor.active_frame over time.
    //   anim_playing       — true if play is engaged
    //   anim_direction     — "fwd" / "rev" / "png" / "once"
    //   anim_speed         — frames per second (1..30)
    //   anim_start         — first frame in the loop range (inclusive)
    //   anim_end           — last frame in the loop range (inclusive)
    //   anim_last_step_ms  — current_time of the last frame advance
    //   anim_png_dir       — internal ping-pong direction (+1 or -1)
    anim_playing      : false,
    anim_direction    : "fwd",
    anim_speed        : 10,
    anim_start        : 0,
    anim_end          : 0,
    anim_last_step_ms : 0,
    anim_png_dir      : 1,
    // Paint cooldown — when > 0, the canvas paint handler suppresses bit
    // writes. Decremented each draw frame. Used to swallow stray clicks
    // that opened V2 from outside (e.g. picker-click in the asset viewer),
    // so the initial click doesn't bleed into a paint operation.
    paint_cooldown    : 0,
    // Sprite clipboard — holds a 504-bit array + mode + UC from CTRL+C
    // on the picker grid. Pasted via CTRL+V into the currently selected
    // sprite slot. -1 = empty.
    sprite_clipboard      : -1,
    sprite_clipboard_mode : 0,
    sprite_clipboard_uc   : 1,
    // Line tool state. Two-stage: click LINE to arm, click pixel 1 to set
    // anchor, click pixel 2 to commit. Tool stays armed for repeat lines
    // until user toggles it off or arms a different tool (FILL).
    //   line_armed    : true when LINE is the active tool
    //   line_anchor_x : -1 when no anchor set, else 0..23
    //   line_anchor_y : -1 when no anchor set, else 0..20
    line_armed    : false,
    line_anchor_x : -1,
    line_anchor_y : -1,
    // COMP preview toggle — when true, the pixel editor canvas renders
    // the OTHER layers of the active compositor cell behind the editable
    // layer, so the user can paint with full compositing context. Editing
    // is still restricted to the selected slot. Initialised here so the
    // editor never has to test variable_struct_exists at runtime.
    comp_preview  : false,
    // Floating pixel-placement marker. Tracks the sprite-canvas hover so
    // the compositor grid can float a flashing black/white rectangle over
    // the matching pixel position, sized to the stretched-pixel footprint
    // (2x wide for X-expand, 2x tall for Y-expand). Reset each frame at
    // the top of the canvas hover block in scr_spred64_v2_draw, then set
    // when the cursor is over a valid sprite pixel.
    //   canvas_pix_hover — true when the cursor is over the pixel canvas
    //   canvas_pix_x     — hovered sprite pixel X, 0..23 (MC snaps to pair)
    //   canvas_pix_y     — hovered sprite pixel Y, 0..20
    canvas_pix_hover : false,
    canvas_pix_x     : -1,
    canvas_pix_y     : -1
};
// -------------------------------------------------------
// DITHER CACHE (Draw GUI populates these each frame)
// -------------------------------------------------------
_dither_cache_mode = "";
_dither_cache_inv  = false;
_dither_cache      = array_create(1, true);


chr_edit_idx = 0; // Which tile (0 to count-1) is currently in the editor

// -------------------------------------------------------
// BITMAP EDITOR TOOLS
// -------------------------------------------------------
bmp_active_tool  = "DRAW";   // DRAW, LINE, CIRCLE, RECT, FILL, GRAB
bmp_fill_toggle  = false;    // false = No Fill (NF), true = Fill (F)
bmp_replace_mode = false;    // Global toggle for color replacement

// Color Replace slots
bmp_rep_detect_col = 0;      // Source color to find
bmp_rep_target_col = 1;      // Destination color to replace with

// Dither State
bmp_dither_mode = "NONE";    // NONE, CHECKER, INTERLACE

// -------------------------------------------------------
// VECTOR_BITMAP RECOLOUR TOOL STATE
// -------------------------------------------------------
// Dedicated colour pickers + selection anchor for the RECOL_C / RECOL_S
// tools. Editor-level state (not per-asset meta), initialised here so the
// vbmp editor never has to test variable_struct_exists at runtime.
//   vbmp_recol_c1 / vbmp_recol_c2 — SRAM overrides (screen-RAM nibbles), 0..15
//   vbmp_recol_c3                 — CRAM override (colour-RAM nibble), 0..15
//   vbmp_recol_ax / vbmp_recol_ay — selection anchor cell (-1 = no selection)
vbmp_recol_c1 = 1;
vbmp_recol_c2 = 2;
vbmp_recol_c3 = 3;
vbmp_recol_ax = -1;
vbmp_recol_ay = -1;

// Dither-fill warning: shown under the DITHER controls when a dither fill is
// blocked (colA == seed colour would self-wall the C64 flood). Timer counts
// down in the editor; 0 = no warning. Message held alongside.
vbmp_fill_warn_timer = 0;
vbmp_fill_warn_msg   = "";


// Grab / Stamp State
bmp_grab_state = 0;          // 0: Idle, 1: Waiting for Top-Left, 2: Waiting for Bottom-Right
bmp_grab_x1 = 0;
bmp_grab_y1 = 0;
bmp_grab_x2 = 0;
bmp_grab_y2 = 0;
bmp_stamp_surf = -1;         // Surface to store the grabbed tile section

// -------------------------------------------------------
// VECTOR_BITMAP COPYRGN TOOL STATE
// -------------------------------------------------------
// Two-phase copy-region tool. Phase 0: drag to mark the source cell rect.
// Phase 1: source is locked; move + click to place the dest top-left cell.
// A tool switch or view/page change resets to phase 0 (see editor guards).
//   vbmp_copy_phase — 0 = awaiting source drag, 1 = awaiting dest click
//   vbmp_copy_ax/ay — live source-drag anchor cell (-1 = no drag in progress)
//   vbmp_copy_sc/sr — locked source top-left cell (phase 1)
//   vbmp_copy_sw/sh — locked source size in cells (phase 1)
vbmp_copy_phase = 0;
vbmp_copy_ax    = -1;
vbmp_copy_ay    = -1;
vbmp_copy_sc    = 0;
vbmp_copy_sr    = 0;
vbmp_copy_sw    = 1;
vbmp_copy_sh    = 1;

// DITHER BUFFERS
// We store them in a struct for quick access
dither_data = {
    CHECKER   : buffer_create(8 * 8, buffer_fast, 1),
    INTERLACE : buffer_create(8 * 8, buffer_fast, 1)
};

// Function to "bake" sprite alpha into a buffer
var _bake_mask = function(_spr, _buf) {
    var _surf = surface_create(8, 8);
    surface_set_target(_surf);
    draw_clear_alpha(c_black, 0);
    draw_sprite(_spr, 0, 0, 0);
    surface_reset_target();
    
    buffer_seek(_buf, buffer_seek_start, 0);
    for(var _yy=0; _yy<8; _yy++) {
        for(var _xx=0; _xx<8; _xx++) {
            // If pixel is not transparent, write 1, else 0
            var _val = surface_getpixel_ext(_surf, _xx, _yy) >> 24 != 0;
            buffer_write(_buf, buffer_u8, _val);
        }
    }
    surface_free(_surf);
};

if (sprite_exists(spr_dith_checker))   _bake_mask(spr_dith_checker, dither_data.CHECKER);
if (sprite_exists(spr_dith_interlace)) _bake_mask(spr_dith_interlace, dither_data.INTERLACE);

// ---- META_TILESET glyph atlas (scr_mts_atlas) ----
mts_atlas_surf    = -1;
mts_atlas_pix     = buffer_create(520 * 128 * 4, buffer_fixed, 1);
mts_atlas_shadow  = buffer_create(2048, buffer_fixed, 1);
mts_atlas_owner   = "";
mts_atlas_src_sz  = -1;
mts_atlas_crc     = -1;
mts_atlas_next_ms = 0;
mts_atlas_upload  = true;
mts_atlas_ok      = false;
mts_atlas_tf_prev = false;

// ---- META_TILESET byte-count throttle ----
mts_bytes_owner   = "";
mts_bytes_next_ms = 0;

// ---- META_TILESET RUN VIEW (scr_mts_run_colour) ----
mts_run_view      = true;
mts_plan          = -1;
mts_plan_owner    = "";
mts_plan_map      = -1;

// ---- Deferred charset preview rebuild (scr_chr_preview_defer) ----
chr_preview_pending = noone;
chr_preview_next_ms = 0;

// ---- SID relocator (scr_sid_relocate) ----
scr_srel_optable();
sid_reloc_job    = noone;   // running / finished job struct
sid_reloc_asset  = "";      // asset the fields below belong to
sid_reloc_target = 0;       // target load address
sid_reloc_frames = 15000;   // PLAY calls per sub-song (15000 = 5 min PAL)
sid_reloc_msg    = "";
sid_reloc_ok     = false;

// Manifest column widths are viewer preferences, never asset data.
manifest_reu_split = 182;
manifest_disk_split = 152;
manifest_split_drag = false;
manifest_split_owner = -1;
manifest_split_type = "";
manifest_split_x = 0;
manifest_split_y1 = 0;
manifest_split_y2 = 0;
manifest_split_grab = 0;

// Measure with the active localized font, including the ellipsis itself.
manifest_fit_name = function(_text, _width) {
    if (string_width_l(_text) <= _width) return _text;
    if (string_width_l("...") > _width) return "";
    var _low = 0, _high = string_length(_text);
    while (_low < _high) {
        var _mid = ceil((_low + _high) / 2);
        if (string_width_l(string_copy(_text, 1, _mid) + "...") <= _width) _low = _mid;
        else _high = _mid - 1;
    }
    return string_copy(_text, 1, _low) + "...";
};

manifest_draw_divider = function(_x, _y1, _y2, _type) {
    manifest_split_owner = viewer_asset;
    manifest_split_type = _type;
    manifest_split_x = _x;
    manifest_split_y1 = _y1;
    manifest_split_y2 = _y2;
    var _hover = point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y, _x-5, _y1, _x+5, _y2);
    draw_set_color((_hover || manifest_split_drag) ? make_color_rgb(100,200,180) : make_color_rgb(70,85,95));
    draw_line(_x, _y1, _x, _y2);
    draw_line(_x-2, _y1+3, _x-2, _y1+10);
    draw_line(_x+2, _y1+3, _x+2, _y1+10);
};

// Read-only hover card: use existing GPU caches, never import or rebuild assets.
manifest_draw_preview = function(_asset, _viewer_x, _row_y) {
    if (is_undefined(_asset) || !is_struct(_asset.meta)) return;
    if (manifest_split_drag || reu_drag_row >= 0 || load_reu_sb_drag
    || load_reu_picker_open || load_org_picker_open || global.any_picker_open) return;
    var _meta = _asset.meta;
    var _surface = -1;
    var _keys = ["preview_surf", "preview_surf_clean", "preview_surf_mc"];
    for (var _k = 0; _k < array_length(_keys); _k++) {
        if (variable_struct_exists(_meta, _keys[_k])) {
            var _candidate = variable_struct_get(_meta, _keys[_k]);
            if (surface_exists(_candidate)) { _surface = _candidate; break; }
        }
    }
    var _sprites = variable_struct_exists(_meta, "spr_sprites") ? _meta.spr_sprites : [];
    var _count = is_array(_sprites) ? array_length(_sprites) : 0;
    if (variable_struct_exists(_meta, "used_count")) _count = min(_count, max(0, _meta.used_count));
    var _has_sprite = false;
    for (var _s = 0; _s < _count; _s++) {
        if (sprite_exists(_sprites[_s])) { _has_sprite = true; break; }
    }
    if (_surface == -1 && !_has_sprite) return;

    var _old_font = draw_get_font();
    var _old_color = draw_get_color();
    var _old_alpha = draw_get_alpha();
    var _old_halign = draw_get_halign();
    var _old_valign = draw_get_valign();
    var _old_filter = gpu_get_tex_filter();
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
    gpu_set_tex_filter(false);

    var _x = 16;
    var _w = min(320, _viewer_x - _x - 12);
    var _inner = max(1, _w - 16);
    var _name_h = min(64, max(14, string_height_ext_l(_asset.name, 14, _inner)));
    var _cols = max(1, ceil(sqrt(_count)));
    var _rows = max(1, ceil(_count / _cols));
    var _source_w = _has_sprite ? _cols * 52 : surface_get_width(_surface);
    var _source_h = _has_sprite ? _rows * 46 : surface_get_height(_surface);
    var _scale = min(_inner / _source_w, 300 / _source_h);
    var _image_w = _source_w * _scale;
    var _image_h = _source_h * _scale;
    var _h = _name_h + _image_h + 46;
    var _y = clamp(_row_y - _h * 0.5, 140, max(140, display_get_gui_height() - _h - 20));
    draw_set_color(make_color_rgb(16,19,29));
    draw_rectangle(_x, _y, _x + _w, _y + _h, false);
    draw_set_color(make_color_rgb(100,200,180));
    draw_rectangle(_x, _y, _x + _w, _y + _h, true);
    draw_set_color(c_white);
    // Bound unusually long names to four lines without painting into the image.
    var _name = _asset.name;
    if (string_height_ext_l(_name, 14, _inner) > 64) {
        while (string_length(_name) > 0 && string_height_ext_l(_name + "...", 14, _inner) > 64)
            _name = string_delete(_name, string_length(_name), 1);
        _name += "...";
    }
    draw_text_ext_l(_x + 8, _y + 8, _name, 14, _inner);
    draw_set_color(make_color_rgb(150,170,185));
    draw_text_l(_x + 8, _y + 10 + _name_h, manifest_fit_name(_asset.type, _inner));
    var _ix = _x + (_w - _image_w) * 0.5;
    var _iy = _y + _name_h + 30;
    draw_set_color(variable_struct_exists(_meta, "bg_col") ? scr_c64_pepto_colour(_meta.bg_col) : c_black);
    draw_rectangle(_ix, _iy, _ix + _image_w, _iy + _image_h, false);
    if (_has_sprite) {
        for (var _s = 0; _s < _count; _s++) {
            var _sprite = _sprites[_s];
            if (!sprite_exists(_sprite)) continue;
            var _sx = _ix + ((_s mod _cols) * 52 + 2) * _scale;
            var _sy = _iy + (floor(_s / _cols) * 46 + 2) * _scale;
            var _ss = min(48 / sprite_get_width(_sprite), 42 / sprite_get_height(_sprite)) * _scale;
            draw_sprite_ext(_sprite, 0, _sx + sprite_get_xoffset(_sprite) * _ss,
                _sy + sprite_get_yoffset(_sprite) * _ss, _ss, _ss, 0, c_white, 1);
        }
    } else {
        draw_set_color(c_white);
        draw_surface_stretched(_surface, _ix, _iy, _image_w, _image_h);
    }
    gpu_set_tex_filter(_old_filter);
    draw_set_font(_old_font);
    draw_set_color(_old_color);
    draw_set_alpha(_old_alpha);
    draw_set_halign(_old_halign);
    draw_set_valign(_old_valign);
};
