/// @desc Initialize Flexible C64 Node

// ============================================================
// obj_c64_node — Create Event additions
// GOLDEN RULE: All fields declared here with defaults.
// NEVER check with variable_instance_exists() at runtime.
// ============================================================
dbl_click_timer = 0;
dbl_click_threshold = 20;
global.drag_claim_taken = false;
// joystic macro optimisation to show all or used directions etc
show_only_used = false;
jsr_called = 1;
// Connection / chain state
is_connected      = false;
node_title        = "";
custom_title      = "";   // user-renamed header override; empty = use node_title
node_type         = "";
code_descriptor   = "";
has_ever_connected = false;
_has_jumped_label = false;
label_picker_field_idx = 0;
// When true, VAR pickers list only 16-bit ("word") encoded UVs.
// Set by COND_IF_WORD's pickers, cleared by every other VAR picker
// at open time so the filter can never leak between nodes.
label_picker_word_only = false;
// When true, VAR pickers list only 8-bit UVs (size == 1, so byte and
// sbyte but not bcd2/bcd3). Set by COND_IF's pickers.
label_picker_byte_only = false;

node_ready=false;
bmp_shadow_warn = false;
// Address / size
pc_address        = 0;
end_address       = 0;
total_node_size   = 0;

// Buffers — use buffer_exists() to check validity, NOT variable_instance_exists()
sprite_buffer     = noone;
kla_buffer        = noone;

// MACRO_CODE cache
code_seg_cache    = [];
code_cache_dirty  = true;

// Conflict state (written by scr_draw_memory_bar, never by existence-check)
is_conflicted     = false;

// Instructions array
instructions      = [];

// Org parent reference
org_parent        = noone;


// =============================================================
// 1. IDENTITY & TYPE
// =============================================================
node_type       = "NORMAL";
node_title      = "Custom Logic";
instructions    = [
    ["lda_imm", 0],
    ["sta_abs", 0xD020]
];

// =============================================================
// 1.5 CODE BLOCK EDITIING
// =============================================================

code_descriptor = "Code Block";
code_editing    = false;

// =============================================================
// 2. ADDRESS & SIZE
// =============================================================
pc_address           = 2062;        // Default $080E
end_address          = 2062;
display_address      = "$-";
total_node_size      = 0;
start_address_val    = 0x0801;
start_address_str    = "$0801";
cumulative_scanlines = 0;
node_cycles          = 0;
scanline_usage       = 0;
nest_level           = 0;
org_parent           = noone;
proxy                = true;
proxy_address        = 0;
macro_owner          = noone;

// =============================================================
// 3. CONNECTION & LAYOUT
// =============================================================
is_connected  = false;
is_draggable  = true;
is_expanded   = false;
is_dragging   = false;
was_dragged   = false;
has_dragged   = false;
exit_spawned  = false;

drag_offset_x  = 0;
drag_offset_y  = 0;
drag_start_x   = 0;
saved_x_indent = 0;
depth = -100;
pre_click_depth = depth;
is_depth_pushed = false;
x_indent       = 0;
org_parent      = noone;


// =============================================================
// 4. DIMENSIONS & VISUALS
// =============================================================
width  = variable_global_exists("node_display_width") ? global.node_display_width : 160;
height = 40;

color_header     = make_color_rgb(64, 80, 192);
latch_glow_alpha = 0;
cached_bg_color  = 0;
last_overlap_check = false;
rmb_flash          = 0;
rmb_first_click_time = -1;

// =============================================================
// 5. UI / INTERACTION STATE
// =============================================================
editing_index          = -1;
mouse_over_instruction = -1;
is_editing_origin      = false;
instruction_type       = "nop";
ascii_address_valid    = true;

// =============================================================
// 6. SPRITE (SPR64 / MACRO_SPR)
// =============================================================
sprite_buffer    = noone;
binary_blob      = "";
spr_link         = noone;
spr_link_ready   = false;
spr_pulse        = 0;
spr_surface      = -1;
spr_cached_frame = -1;
spr_cached_bytes = [];
spr_cached_mc    = false;
spr_cached_uc    = 1;
joy_label_missing = array_create(18, false);
spr_preview_dbl_click_timer = 0;

// =============================================================
// 7. BITMAP (BITMAP_KLA / MACRO_BMP)
// =============================================================
kla_buffer     = -1;
kla_surface    = -1;
kla_filename   = "";
preview_surf   = -1;
bmp_link       = noone;
bmp_link_ready = false;

// =============================================================
// 8. SID MUSIC (DATA_SID / MACRO_SID)
// =============================================================
sid_link       = noone;
sid_title      = "";
sid_author     = "";
sid_songs      = 0;
sid_load_addr  = 0;
sid_init_addr  = 0;
sid_play_addr  = 0;
sid_start_song = 0;
sid_uses_cia   = false;

is_data_node = false; // set properly in User Event 0 after node_type is assigned
is_free_node = false;
// =============================================================
// 9. PRINT (MACRO_PRINT) - legacy, kept for workspace compatibility
// =============================================================
print_link       = noone;
print_link_ready = false;

// =============================================================
// 10. LABEL LIST 
// =============================================================

label_picker_open        = false;
coll_adv_dragging_probe  = false;
label_picker_prev_depth  = depth;
label_picker_mode   = "";
label_picker_index  = 0;
label_picker_scroll = 0;
label_picker_list   = [];
label_picker_inc_code    = false;
label_picker_target = noone;
label_picker_tab    = "UV";
label_picker_group  = "LABELS";
label_picker_is_jsr = false;
// Single-character filter for the picker list — set by pressing a letter/
// number while a picker is open, cleared by Space/Backspace/Delete.
label_picker_filter_char = "";
// Edge-detect for label_picker_open, so the A0 filter block can tell the
// difference between "picker already open, user typed a letter" and
// "picker just opened this frame" — the latter must discard any stale
// keyboard_string left over from the click that opened it.
label_picker_was_open = false;
wedge_y_stored       = -1;
overlap_check_dirty  = false;
prev_height          = 40;
extra_regions        = [];
anim_alias           = "";
height_dirty         = true;

// ORG BLOCK COLLAPSE. Meaningful only on ORG nodes, but every node carries it
// so scr_node_is_hidden() can read a parent's flag without testing for the
// variable first. Never assigned by the height recompute — see scr_org_collapse.
collapsed            = false;

// Index of the saved record this node was created from, or -1 for a node made
// any other way. The loader and the undo restore use it to find their own
// record again instead of hunting for one by position — see
// scr_load_workspace_from_path for why position matching was not safe.
load_idx             = -1;
cached_height        = 40;
stats_cache_dirty    = true;
stats_str_bytes      = "";
stats_str_cyc        = "";
stats_str_hint1      = "";
stats_str_hint2      = "";
code_seg_cache       = [];
p9_parsed_cache      = [];
stats_col_hint1      = c_white;
stats_col_hint2      = c_white;
code_cached_bytes    = 0;
code_cached_cycles   = 0;
code_cached_lines    = 0;
code_cache_dirty     = true;

// SET_VAR draw cache — expensive lookups (named_loc_map, meta, hex) cached
// behind a content signature so static nodes pay almost nothing per frame.
setvar_cache_sig   = "";
setvar_cache_addr  = -1;
setvar_cache_size  = 1;
setvar_cache_enc   = "byte";
setvar_cache_isbcd = false;
setvar_cache_hex   = "";

drag_indent_stash = 0;

// Label-reference hover highlight
hover_timer      = 0;       // counts up while mouse is over this node
hover_threshold  = 9;       // ~0.15s before highlight fires
tooltip_hover_timer = 0;    // counts up while mouse is over the header tooltip zone
ref_highlight_on = false;   // true while this node is the broadcast source
ref_jump_index   = 0;       // cycle position when Enter-jumping through references
if (!variable_global_exists("ref_highlight_source")) global.ref_highlight_source = noone;
if (!variable_global_exists("ref_highlight_name"))   global.ref_highlight_name   = "";

// Display-string cache (section I header + section J opcode body)
draw_cache_dirty  = true;
draw_cache_sig    = "";
draw_cache_lines  = [];   // structs: {prefix, val, suffix, implied, illegal, jump}
hdr_cache_sig     = "";
hdr_cache_title   = "";
hdr_cache_opcode  = false;  // true when title font is fnt_C64_Angled_tiny

// ORG wire connection system
org_uid          = -1;
wire_out_target  = -1;
wire_in_source   = -1;
wire_dragging_out = false;
wire_dragging_in  = false;

// Stable UID for ignored-conflict tracking (workspace-scoped, survives reload
// only if the workspace serializer persists it; otherwise allocated fresh)
stable_uid = -1;

event_user(0);

// Assign a stable UID to every ORG node on creation
if (node_type == "ORG") {
    org_uid = global.next_org_uid;
    global.next_org_uid += 1;
}

// Assign a stable UID to every node on creation (mirrors org_uid pattern)
if (!variable_global_exists("next_stable_uid")) global.next_stable_uid = 100000;
if (stable_uid == -1) {
    stable_uid = global.next_stable_uid;
    global.next_stable_uid += 1;
}

// SYSTEM INIT draws a "+ RTS (AUTO)" row while nothing is connected below it,
// and needs one grid row of height to fit it. Cached because the height switch
// runs at the top of Draw and the marker at the bottom — the marker raises
// height_dirty when this changes, so the row is there on the next frame.
// Does this node type have a tooltip, and therefore an [INFO] badge? Resolved
// once on the first draw rather than per frame: scr_node_tooltip_text builds a
// large struct literal every call, and asking it for every node every frame is
// not something to do for a six-character label. -1 = not resolved yet.
info_badge = -1;

init_rts_marker = false;

prev_height = height; // must be last
is_conflicted = false;