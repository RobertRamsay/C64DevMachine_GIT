/// @desc Setup Workspace, Palette & C64 Environment
global.lite=0;
global.build_date = "August 27th, 2026"; // edit this string for each release
// is demo mode?
// --- GLOBAL CRASH HANDLER ---
exception_unhandled_handler(function(_ex) {
    // Log the error to the console
    show_debug_message("FATAL CRASH INTERCEPTED: " + string(_ex.message));
    show_debug_message("STACK TRACE: " + string(_ex.stacktrace));
    
    // Attempt an emergency rescue of the user's workspace
    if (variable_global_exists("autosave_dirty") && variable_global_exists("autosave_mode")) {
        if (global.autosave_dirty && global.autosave_mode != 3) {
            scr_autosave();
            show_debug_message("Emergency autosave triggered successfully.");
        }
    }
    
    // Alert the user that the app is closing but their work was saved
    show_message("C64 Dev Machine encountered a fatal error and needs to close.\n\nAn emergency autosave was attempted.\n\nError: " + string(_ex.message));
    
    // Return 0 to let the game close itself cleanly
    return 0;
});

global.question_result = "";
// Deferred RAM unlock state (used by memory bar danger zone clicks)
global.pending_unlock_type     = "";       // "BASIC" or "KERNAL"
global.pending_unlock_inject_x = 0;
global.pending_unlock_inject_y = 0;
global.pending_unlock_init_id  = noone;

global.canEditNode=1;
opcode_extra_height=1;
showPaletteHelper=1;
expert_mode = false;
hideui=false;
// =============================================================
// Version check state
// =============================================================
version_check_url       = "https://raw.githubusercontent.com/RobRam78/C64_HELPER/main/c64devmachine_version.txt";
version_check_request   = -1;     // http_get id, -1 when idle
version_check_done      = false;  // true once a result (success or fail) has come back
version_check_failed    = false;  // true if the request errored or returned junk
version_remote_string   = "";     // remote version on line 1, raw
version_remote_date     = "";     // line 2
version_remote_url      = "";     // line 3
version_remote_notes    = "";     // line 4+
version_update_available = false; // true if remote != GM_version
version_banner_visible  = false;  // user can dismiss the banner
version_banner_dismissed = false;

// ---- WELCOME SCREEN ----
// welcome_open is set from the saved "hide_welcome" ini pref further down,
// once settings are loaded. welcome_hide_checked mirrors the checkbox state.
welcome_open           = false;
welcome_hide_checked   = false;
welcome_credits_y      = 0;
welcome_whats_new = [
	"FIXED - REU macro performance hit",
	"NEW - Cyberpunk style UI",
	];
	
welcome_credits_lines = [
    "CODE and DESIGN",
    "Robert Ramsay",
    "",
    "COMMUNITY INPUT",
    "51Pegasi",
    "Analog-X64",
    "Arlasoft",
    "Balfourd",
    "CptGreenwood",
	"Deano",
    "funkygallo",
    "keefnayls",
    "markc.sherman",
    "Sch31Btyp",
	"SirWizAlot",
    "SLAXX",
    "SPEE-DEC",
    "sTERN",
    "Stuart Hurst",
    "TonyWatto",
    "VxV",
    "",
    "And...",
    "All those who are part of the Discord and those",
    "who are users and have supported the software!",
];

// Fire the check on startup, but only once per session.
version_check_request = http_get(version_check_url);

bkgImg = 1;
paletteStyle=1
showGrid=1;
badgeStyle=1
buttonStyle=1
nodeStyle=0;  // 0..spr_9s_tile1 frames, final virtual index = Cyber renderer
macroStyle=0; // 0 classic menu rows, 1 appended Cyber macro-button pair
niceSliceFrm = 0;
uiChromeStyle = 0; // 0 existing chrome, 1 appended Cyber chrome
ini_open("c64devmachine.ini");
vicedelay = ini_read_real("vice", "delay", 120) // shutdown settle delay in steps; build time is no longer part of VICE timing. Override via [vice] delay= in c64devmachine.ini on machines where taskkill/process teardown is slower.
vice_launch_phase = 0;          // 0=idle/waiting, 1=VICE killed and waiting to relaunch
vice_launch_pending = false;
vice_launch_target = "";
vice_launch_retry = 0;
vice_launch_retry_max = 600;    // safety timeout (~10s at 60fps)
global.asset_reload_in_progress = false;

trigger_build = false;
	trigger_c64u  = false;   // F6: send to C64 Ultimate after build

	// --- C64 Ultimate networking init ---
	scr_c64u_init();
trigger_export      = false;
pending_export_path = "";
autosave_last_path = "";
map_global_mixed = 1;
windowState=1;


// Restore saved window state
ini_open("c64devmachine.ini");
windowState = ini_read_real("window", "state", 0);
ini_close();

		
		
global.was_editor_open = false;

global.conflict_ranges      = [];
global.memory_bar_segments   = [];
global.memory_bar_conflicts  = [];
global.memory_bar_disk_assets = [];
global.memory_bar_dirty     = true;
global.memory_bar_hover_node  = noone;
global.memory_bar_hover_asset = -1;

// Conflict ignore system: workspace-scoped list of suppressed conflicts.
// Each entry: { range_start, range_end, owner_a_uid, owner_b_uid }
// A conflict is suppressed if EITHER (a) the range matches exactly, or
// (b) both owner UIDs match (in either order). Stale entries are pruned
// on workspace load.
global.ignored_conflicts = [];

// Conflict popup state — driven by click on the conflict label.
global.conflict_popup_open    = false;
global.conflict_popup_x       = 0;
global.conflict_popup_y       = 0;
global.conflict_popup_owner_a = noone;
global.conflict_popup_owner_b = noone;
global.conflict_popup_asset_a = "";
global.conflict_popup_asset_b = "";
global.conflict_popup_range_start = 0;
global.conflict_popup_range_end   = 0;

// scan effect when building
scan_active = false;
scan_y = 0;
scan_speed = 10; // Speed of the downward scan

code_editor_open      = false;
code_editor_node      = noone;
code_editor_text      = "";
code_editor_cursor    = 0;
code_editor_sel_start = -1;
code_editor_sel_end   = -1;
code_editor_scroll_y  = 0;
code_editor_blink     = 0;
code_editor_key_timer = 0;
code_editor_scrollbar_dragging     = false;
code_editor_scrollbar_drag_offset  = 0;
code_editor_last_cursor = 0;
code_editor_cached_text = "";
code_editor_cached_stats = [0, 0];
code_editor_cached_pcs = [];
code_editor_cached_pc = -1;
code_editor_cache_dirty = true;
code_editor_preferred_col = 0;
code_editor_fonts      = [fnt_c64, fnt_C64_Angled, fnt_C64_Angled_big, fnt_c64_code];
code_editor_font_index = 3;   // starts on fnt_c64_code
code_editor_mouse_selecting = false;
code_editor_undo_stack = [];
code_editor_redo_stack = [];
code_editor_scroll_x               = 0;
code_editor_max_line_px            = 0;
code_editor_symbol_cache_dirty     = true;
code_editor_indent_cache           = [];
code_editor_line_starts            = [];
code_editor_local_labels           = ds_map_create();
code_editor_local_consts           = ds_map_create();
code_editor_global_labels          = ds_map_create();
code_editor_hscrollbar_dragging     = false;
code_editor_hscrollbar_drag_offset  = 0;
code_editor_find_open = false;
code_editor_find_text = "";
code_editor_replace_text = "";
code_editor_find_active_field = 0; // 0: None, 1: Find, 2: Replace
code_editor_scope_depth = []; 

global.mac_x1     = 90 * 3;
global.mac_x2     = global.mac_x1 + 200;
global.sc_x_start = 1640; // safe default, updated in Step once gui_w is known0;
global.show_stats = false;
global.group_drag_active  = false;
global.group_drag_handle  = noone;
global.group_drag_nodes   = [];   // [{node, dx, dy}] sorted by Y
global.group_drag_is_clone = false;

// ---- VARIABLE DELETE REFERENCE WARNING ----
// Raised by the RMB-delete guard in obj_c64_node when a VAR node is still
// referenced. Rendered as a left-side scrollable list in this object's
// Draw GUI. Holds until first click, then fades over 3s. Rows jump camera.
global.var_del_warn_active  = false;
global.var_del_warn_clicked = false;
global.var_del_warn_fade    = 1.0;
global.var_del_warn_scroll  = 0;
global.var_del_warn_name    = "";
global.var_del_warn_refs    = [];   // [{ node, label }]
global.var_del_warn_batch   = 0;    // >1 when a multi-var batch delete was blocked

global.undo_dirty = false;
global.undo_states = 100;
alarm[2] = 10;
global.node_destroy_fx = true;
global.visual_fx       = true;

depth = 0;
global.wedge_node     = noone;
global.wedge_insert_y = -1;
global.wedge_push     = 0;


global.wedge_preview_y      = -1;
global.wedge_preview_node   = noone;
global.wedge_preview_h      = 0;
global.wedge_preview_spine  = true;
global.wedge_preview_anchor = noone;

global.code_block_labels = {};

global.macro_anim_counter = 0;
global.active_drag_node = noone;
global.drop_occurred_this_frame = false;

// one check optimisation for mouse gui
global.any_node_dragging = false;
global.gui_mouse_x = 0;
global.gui_mouse_y = 0;
global.gui_w       = 0;
global.is_any_text_active = false;
global.user_quick_menu = []; // {type, label} entries added via SHIFT+Q, max 24
global.qmenu_toast_text = "";
global.qmenu_toast_t    = 0;   // frames remaining, counts down; 0 = hidden
global.qmenu_toast_dur  = 90;  // total duration in frames (~1.5s at 60fps)
global.qmenu_toast_col  = c_white;
global.nodepad = 40
_was_entering_text = false;
box_select_active  = false;
box_select_x1      = 0;
box_select_y1      = 0;
box_select_x2      = 0;
box_select_y2      = 0;
global.selected_nodes = [];
box_next_col_idx = 0;
//  1. GRID & EXPORT CONFIG 
grid_surface   = -1;
grid_w         = room_width;
grid_h         = room_height;
export_dir     = "C:\\C64Temp\\";
file_name      = "program.prg";
full_save_path = export_dir + file_name;
readyToQuit    = 0;
cursor_pos      = 0;
input_sel_start = -1;
input_sel_end   = -1;
input_key_timer = 0;
//  2. GLOBAL CONSTANTS 
// $080E / 2062 = first byte of user code after BASIC stub
global.node_display_width = 200;
global.c64_base_addr      = 0x0801;
global.c64_header_size    = 13;
global.start_pc           = global.c64_base_addr + global.c64_header_size;
global.node_chain         = ds_list_create();
global.egg_temp_node_ids  = [];  // easter-egg: temp node ids attached for one compile pass, see build trigger
global.use_hex_display    = true;
global.input_mode_hex     = true;
global.link_pulse = 0;
global.addresses_dirty = true; // Force first update on load
global.named_loc_repack_gen = 0; // bumped every scr_c64_do_update_addresses() call — lets
                                  // per-node draw caches (e.g. SET_VAR) detect a stale address
                                  // even when the node's own name/value didn't change.
global.kernal_unlocked = false;
global.basic_unlocked = false;
global.breakdown_node = noone;
global.show_info_window = false;
global.info_node = noone;
global.current_filename = "No File Loaded"
global.show_helper_window = false;
global.helper_node = noone;
window_set_caption(game_project_name);
global.workspace_path       = "";


// initial window:

//window_set_size(1920,1000)
//window_set_position(0,28)
// Apply restored window state (do_windowSizing increments first, so pre-decrement)
windowState--;
if (windowState < 0) {
    windowState = 1;
}
do_windowSizing();

silent_build = false;
pending_dump = false;
global.last_built = false;
global.last_bytes = [];
global.sid_active = false;
global.node_link_max_dist = 500;

//  3. BUFFER & PATH PERSISTENCE 
global.vice_path_cache = "";
global.comments_visible = true;
p_buf                  = -1;

//  4. SHELF PALETTE 
// Nodes dragged from here onto the spine become part of the program.
// ORG blocks are NOT in the palette - spawn them with the O key instead.
// HEADER type entries are category dividers, not spawnable nodes.

// extra column for macros
shelf_cols       = 3;
macro_col_width  = 120;
shelf_width      = (110 * shelf_cols) + 20 + macro_col_width;

shelf_page = 0; // Current active page (0, 1, or 2)

// ---- OPCODE FINDER ----
opcode_finder_active     = false;
opcode_finder_text       = "";
opcode_finder_matches    = [];
opcode_finder_page       = -1;
opcode_finder_was_active = false;

opcode_headers_on = false;

//  PAGE 0: DATA MOVEMENT & TRANSFERS 
// PAGE 0: DATA MOVEMENT (52 Opcodes)
palette_page[0] = [
    { title: " SYSTEM ", type: "HEADER" },
    { title: "BRK", type: "NORMAL", instructions: [["brk", 0]] },
    { title: "NOP",        type: "NORMAL", instructions: [["nop", 0]] },
    { title: "", type: "SPACER" },

    { title: " LOAD GROUP (A-X-Y) ", type: "HEADER" },
    { title: "LDA_IMM", type: "NORMAL", instructions: [["lda_imm", 0]] },
    { title: "LDX_IMM", type: "NORMAL", instructions: [["ldx_imm", 0]] },
    { title: "LDY_IMM", type: "NORMAL", instructions: [["ldy_imm", 0]] },
    { title: "LDA_ZP",  type: "NORMAL", instructions: [["lda_zp",  0]] },
    { title: "LDX_ZP",  type: "NORMAL", instructions: [["ldx_zp",  0]] },
    { title: "LDY_ZP",  type: "NORMAL", instructions: [["ldy_zp",  0]] },
    { title: "LDA_ZPX", type: "NORMAL", instructions: [["lda_zpx", 0]] },
    { title: "LDX_ZPY", type: "NORMAL", instructions: [["ldx_zpy", 0]] },
    { title: "LDY_ZPX", type: "NORMAL", instructions: [["ldy_zpx", 0]] },
    { title: "LDA_ABS", type: "NORMAL", instructions: [["lda_abs", 0]] },
    { title: "LDX_ABS", type: "NORMAL", instructions: [["ldx_abs", 0]] },
    { title: "LDY_ABS", type: "NORMAL", instructions: [["ldy_abs", 0]] },
    { title: "LDA_ABX", type: "NORMAL", instructions: [["lda_abx", 0]] },
    { title: "LDX_ABY", type: "NORMAL", instructions: [["ldx_aby", 0]] },
    { title: "LDY_ABX", type: "NORMAL", instructions: [["ldy_abx", 0]] },
    { title: "LDA_ABY", type: "NORMAL", instructions: [["lda_aby", 0]] },
    { title: "LDA_IZX", type: "NORMAL", instructions: [["lda_izx", 0]] },
    { title: "LDA_IZY", type: "NORMAL", instructions: [["lda_izy", 0]] },

    { title: " LABEL LO/HI BYTE ", type: "HEADER" },
    { title: "LDA #<LAB", type: "NORMAL", instructions: [["lda_lab_lo", "label"]] },
    { title: "LDA #>LAB", type: "NORMAL", instructions: [["lda_lab_hi", "label"]] },
    { title: "LDX #<LAB", type: "NORMAL", instructions: [["ldx_lab_lo", "label"]] },
    { title: "LDX #>LAB", type: "NORMAL", instructions: [["ldx_lab_hi", "label"]] },
    { title: "LDY #<LAB", type: "NORMAL", instructions: [["ldy_lab_lo", "label"]] },
    { title: "LDY #>LAB", type: "NORMAL", instructions: [["ldy_lab_hi", "label"]] },

    { title: " STORE GROUP (A-X-Y) ", type: "HEADER" },
    { title: "STA_ZP",  type: "NORMAL", instructions: [["sta_zp",  0]] },
    { title: "STX_ZP",  type: "NORMAL", instructions: [["stx_zp",  0]] },
    { title: "STY_ZP",  type: "NORMAL", instructions: [["sty_zp",  0]] },
    { title: "STA_ZPX", type: "NORMAL", instructions: [["sta_zpx", 0]] },
    { title: "STX_ZPY", type: "NORMAL", instructions: [["stx_zpy", 0]] },
    { title: "STY_ZPX", type: "NORMAL", instructions: [["sty_zpx", 0]] },
    { title: "STA_ABS", type: "NORMAL", instructions: [["sta_abs", 0]] },
    { title: "STX_ABS", type: "NORMAL", instructions: [["stx_abs", 0]] },
    { title: "STY_ABS", type: "NORMAL", instructions: [["sty_abs", 0]] },
    { title: "STA_ABX", type: "NORMAL", instructions: [["sta_abx", 0]] },
    { title: "STA_ABY", type: "NORMAL", instructions: [["sta_aby", 0]] },
    { title: "STA_IZX", type: "NORMAL", instructions: [["sta_izx", 0]] },
    { title: "STA_IZY", type: "NORMAL", instructions: [["sta_izy", 0]] },

    { title: " TRANSFERS ", type: "HEADER" },
    { title: "TAX (A>X)", type: "NORMAL", instructions: [["tax", 0]] },
    { title: "TAY (A>Y)", type: "NORMAL", instructions: [["tay", 0]] },
    { title: "TSX (S>X)", type: "NORMAL", instructions: [["tsx", 0]] },
    { title: "TXA (X>A)", type: "NORMAL", instructions: [["txa", 0]] },
    { title: "TYA (Y>A)", type: "NORMAL", instructions: [["tya", 0]] },
    { title: "TXS (X>S)", type: "NORMAL", instructions: [["txs", 0]] }
];

// PAGE 1: ALU & MATH (52 Opcodes)
palette_page[1] = [
    { title: " ARITHMETIC (A-X-Y) ", type: "HEADER" },
    { title: "ADC_IMM", type: "NORMAL", instructions: [["adc_imm",    0]] },
    { title: "INX",     type: "NORMAL", instructions: [["inx",        0]] },
    { title: "INY",     type: "NORMAL", instructions: [["iny",        0]] },
    { title: "ADC_ZP",  type: "NORMAL", instructions: [["adc_zp",     0]] },
    { title: "DEX",     type: "NORMAL", instructions: [["dex",        0]] },
    { title: "DEY",     type: "NORMAL", instructions: [["dey",        0]] },
    { title: "ADC_ZPX", type: "NORMAL", instructions: [["adc_zp_x",   0]] },
    { title: "INC_ZP",  type: "NORMAL", instructions: [["inc_zp",     0]] },
    { title: "DEC_ZP",  type: "NORMAL", instructions: [["dec_zp",     0]] },
    { title: "INC_ZPX", type: "NORMAL", instructions: [["inc_zpx",    0]] },
    { title: "DEC_ZPX", type: "NORMAL", instructions: [["dec_zpx",    0]] },
    { title: "ADC_ABS", type: "NORMAL", instructions: [["adc_abs",    0]] },
    { title: "INC_ABS", type: "NORMAL", instructions: [["inc_abs",    0]] },
    { title: "DEC_ABS", type: "NORMAL", instructions: [["dec_abs",    0]] },
    { title: "ADC_ABX", type: "NORMAL", instructions: [["adc_abs_x",  0]] },
    { title: "INC_ABX", type: "NORMAL", instructions: [["inc_abs_x",  0]] },
    { title: "DEC_ABX", type: "NORMAL", instructions: [["dec_abs_x",  0]] },
    { title: "ADC_ABY", type: "NORMAL", instructions: [["adc_abs_y",  0]] },
    { title: "ADC_IZX", type: "NORMAL", instructions: [["adc_ind_x",  0]] },
    { title: "ADC_IZY", type: "NORMAL", instructions: [["adc_ind_y",  0]] },
    { title: "SBC_IMM", type: "NORMAL", instructions: [["sbc_imm",    0]] },
    { title: "SBC_ZP",  type: "NORMAL", instructions: [["sbc_zp",     0]] },
    { title: "SBC_ZPX", type: "NORMAL", instructions: [["sbc_zp_x",   0]] },
    { title: "SBC_ABS", type: "NORMAL", instructions: [["sbc_abs",    0]] },
    { title: "SBC_ABX", type: "NORMAL", instructions: [["sbc_abs_x",  0]] },
    { title: "SBC_ABY", type: "NORMAL", instructions: [["sbc_abs_y",  0]] },
    { title: "SBC_IZX", type: "NORMAL", instructions: [["sbc_ind_x",  0]] },
    { title: "SBC_IZY", type: "NORMAL", instructions: [["sbc_ind_y",  0]] },

    { title: " LOGIC & COMPARE ", type: "HEADER" },
    { title: "AND_IMM", type: "NORMAL", instructions: [["and_imm",    0]] },
    { title: "AND_ZP",  type: "NORMAL", instructions: [["and_zp",     0]] },
    { title: "AND_ZPX", type: "NORMAL", instructions: [["and_zp_x",   0]] },
    { title: "AND_ABS", type: "NORMAL", instructions: [["and_abs",    0]] },
    { title: "AND_ABX", type: "NORMAL", instructions: [["and_abs_x",  0]] },
    { title: "AND_ABY", type: "NORMAL", instructions: [["and_abs_y",  0]] },
    { title: "AND_IZX", type: "NORMAL", instructions: [["and_izx",    0]] },
    { title: "AND_IZY", type: "NORMAL", instructions: [["and_izy",    0]] },
    { title: "ORA_IMM", type: "NORMAL", instructions: [["ora_imm",    0]] },
    { title: "ORA_ZP",  type: "NORMAL", instructions: [["ora_zp",     0]] },
    { title: "ORA_ZPX", type: "NORMAL", instructions: [["ora_zp_x",   0]] },
    { title: "ORA_ABS", type: "NORMAL", instructions: [["ora_abs",    0]] },
    { title: "ORA_ABX", type: "NORMAL", instructions: [["ora_abs_x",  0]] },
    { title: "ORA_ABY", type: "NORMAL", instructions: [["ora_abs_y",  0]] },
    { title: "ORA_IZX", type: "NORMAL", instructions: [["ora_izx",    0]] },
    { title: "ORA_IZY", type: "NORMAL", instructions: [["ora_izy",    0]] },
    { title: "EOR_IMM", type: "NORMAL", instructions: [["eor_imm",    0]] },
    { title: "EOR_ZP",  type: "NORMAL", instructions: [["eor_zp",     0]] },
    { title: "EOR_ZPX", type: "NORMAL", instructions: [["eor_zp_x",   0]] },
    { title: "EOR_ABS", type: "NORMAL", instructions: [["eor_abs",    0]] },
    { title: "EOR_ABX", type: "NORMAL", instructions: [["eor_abs_x",  0]] },
    { title: "EOR_ABY", type: "NORMAL", instructions: [["eor_abs_y",  0]] },
    { title: "EOR_IZX", type: "NORMAL", instructions: [["eor_izx",    0]] },
    { title: "EOR_IZY", type: "NORMAL", instructions: [["eor_izy",    0]] },
    { title: "BIT_ZP",  type: "NORMAL", instructions: [["bit_zp",     0]] },
    { title: "BIT_ABS", type: "NORMAL", instructions: [["bit_abs",    0]] },
    { title: "CMP_IMM", type: "NORMAL", instructions: [["cmp_imm",    0]] },
    { title: "CMP_ZP",  type: "NORMAL", instructions: [["cmp_zp",     0]] },
    { title: "CMP_ZPX", type: "NORMAL", instructions: [["cmp_zpx",    0]] },
    { title: "CMP_ABS", type: "NORMAL", instructions: [["cmp_abs",    0]] },
    { title: "CMP_ABX", type: "NORMAL", instructions: [["cmp_abx",    0]] },
    { title: "CMP_ABY", type: "NORMAL", instructions: [["cmp_aby",    0]] },
    { title: "CMP_IZX", type: "NORMAL", instructions: [["cmp_izx",    0]] },
    { title: "CMP_IZY", type: "NORMAL", instructions: [["cmp_izy",    0]] },
    { title: "CPX_IMM", type: "NORMAL", instructions: [["cpx_imm",    0]] },
    { title: "CPX_ZP",  type: "NORMAL", instructions: [["cpx_zp",     0]] },
    { title: "CPX_ABS", type: "NORMAL", instructions: [["cpx_abs",    0]] },
    { title: "CPY_IMM", type: "NORMAL", instructions: [["cpy_imm",    0]] },
    { title: "CPY_ZP",  type: "NORMAL", instructions: [["cpy_zp",     0]] },
    { title: "CPY_ABS", type: "NORMAL", instructions: [["cpy_abs",    0]] }
];

// PAGE 2: FLOW, SHIFTS & ILLEGALS (52 Opcodes)
palette_page[2] = [
    { title: " SHIFTS & ROTATES ", type: "HEADER" },
    { title: "ASL_A",   type: "NORMAL", instructions: [["asl_a",      0]] },
    { title: "ASL_ZP",  type: "NORMAL", instructions: [["asl_zp",     0]] },
    { title: "ASL_ZPX", type: "NORMAL", instructions: [["asl_zp_x",   0]] },
    { title: "ASL_ABS", type: "NORMAL", instructions: [["asl_abs",    0]] },
    { title: "ASL_ABX", type: "NORMAL", instructions: [["asl_abs_x",  0]] },
    { title: "LSR_A",   type: "NORMAL", instructions: [["lsr_a",      0]] },
    { title: "LSR_ZP",  type: "NORMAL", instructions: [["lsr_zp",     0]] },
    { title: "LSR_ZPX", type: "NORMAL", instructions: [["lsr_zp_x",   0]] },
    { title: "LSR_ABS", type: "NORMAL", instructions: [["lsr_abs",    0]] },
    { title: "LSR_ABX", type: "NORMAL", instructions: [["lsr_abs_x",  0]] },
    { title: "ROL_A",   type: "NORMAL", instructions: [["rol_a",      0]] },
    { title: "ROL_ZP",  type: "NORMAL", instructions: [["rol_zp",     0]] },
    { title: "ROL_ZPX", type: "NORMAL", instructions: [["rol_zp_x",   0]] },
    { title: "ROL_ABS", type: "NORMAL", instructions: [["rol_abs",    0]] },
    { title: "ROL_ABX", type: "NORMAL", instructions: [["rol_abs_x",  0]] },
    { title: "ROR_A",   type: "NORMAL", instructions: [["ror_a",      0]] },
    { title: "ROR_ZP",  type: "NORMAL", instructions: [["ror_zp",     0]] },
    { title: "ROR_ZPX", type: "NORMAL", instructions: [["ror_zp_x",   0]] },
    { title: "ROR_ABS", type: "NORMAL", instructions: [["ror_abs",    0]] },
    { title: "ROR_ABX", type: "NORMAL", instructions: [["ror_abs_x",  0]] },

    { title: " JUMPS & BRANCHES ", type: "HEADER" },
    { title: "JMP_ABS",    type: "NORMAL", instructions: [["jmp_abs",  "label"]] },
    { title: "JMP_IND",    type: "NORMAL", instructions: [["jmp_ind",  0]] },
    { title: "JSR", type: "NORMAL", instructions: [["jsr",      "target"]] },
    { title: "RTS",  type: "NORMAL", instructions: [["rts",      0]] },
    { title: "RTI",        type: "NORMAL", instructions: [["rti",      0]] },
    { title: "BNE (!=)",   type: "NORMAL", instructions: [["bne",      "target"]] },
    { title: "BEQ (==)",   type: "NORMAL", instructions: [["beq",      "target"]] },
    { title: "BCC (<)",    type: "NORMAL", instructions: [["bcc",      "target"]] },
    { title: "BCS (>=)",   type: "NORMAL", instructions: [["bcs",      "target"]] },
    { title: "BPL (+)",    type: "NORMAL", instructions: [["bpl",      "target"]] },
    { title: "BMI (-)",    type: "NORMAL", instructions: [["bmi",      "target"]] },
    { title: "BVC (V=0)",  type: "NORMAL", instructions: [["bvc",      "target"]] },
    { title: "BVS (V=1)",  type: "NORMAL", instructions: [["bvs",      "target"]] },

    { title: " FLAGS ", type: "HEADER" },
    { title: "CLC", type: "NORMAL", instructions: [["clc", 0]] },
    { title: "SEC", type: "NORMAL", instructions: [["sec", 0]] },
    { title: "SEI", type: "NORMAL", instructions: [["sei", 0]] },
    { title: "CLI", type: "NORMAL", instructions: [["cli", 0]] },
    { title: "CLV", type: "NORMAL", instructions: [["clv", 0]] },
    { title: "CLD", type: "NORMAL", instructions: [["cld", 0]] },
    { title: "SED", type: "NORMAL", instructions: [["sed", 0]] },
    { title: "PHA", type: "NORMAL", instructions: [["pha", 0]] },
    { title: "PLA", type: "NORMAL", instructions: [["pla", 0]] },
    { title: "PHP", type: "NORMAL", instructions: [["php", 0]] },
    { title: "PLP", type: "NORMAL", instructions: [["plp", 0]] },

    { title: " THE ILLEGALS ", type: "HEADER" },
    { title: "LAX_ZP",  type: "NORMAL", instructions: [["lax_zp",  0]] },
    { title: "SAX_ZP",  type: "NORMAL", instructions: [["sax_zp",  0]] },
    { title: "DCP_ABS", type: "NORMAL", instructions: [["dcp_abs", 0]] },
    { title: "ISC_ABS", type: "NORMAL", instructions: [["isc_abs", 0]] },
    { title: "RLA_ABS", type: "NORMAL", instructions: [["rla_abs", 0]] },
    { title: "SLO_ABS", type: "NORMAL", instructions: [["slo_abs", 0]] },
    { title: "SRE_ABS", type: "NORMAL", instructions: [["sre_abs", 0]] }
];

// ASSETS MOVED TO PANEL ON THE RIGHT
//  PINNED ASSETS (Appended to every page) // This acts as the trigger for the compiler
common_assets = [];
/*
    { title: "", type: "SPACER" }, { title: "", type: "SPACER" }, { title: "", type: "SPACER" },
    { title: "ASSETS", type: "HEADER" },
	{ title: "OPCODES",  type: "MACRO_GAUNTLET",  instructions: [ ["gauntlet_start", 0]] },
 ];
*/

//  5. SPAWN COMPULSORY ANCHOR NODE 
// INIT anchors the top of the main spine.
// Build is triggered via F5 or the workspace manager Step event.
var spawn_x = floor(((room_width / 2) - (global.node_display_width / 2)) / 20) * 20;

var n_init = instance_create_layer(spawn_x, 60, "Layer_Nodes", obj_c64_node);
n_init.node_title   = "SYSTEM INIT";
n_init.node_type    = "INIT";
n_init.is_draggable = false;
n_init.is_connected = true;
n_init.pc_address   = global.start_pc;
n_init.instructions = [
    ["sei",     0],
    ["lda_imm", 0],
    ["sta_abs", 0xD020],
    ["sta_abs", 0xD021]
];

//  6. CAMERA & NAVIGATION 
cam_view        = view_camera[0];
cam_x           = 0//(room_width / 2) - (1920 / 2);
cam_y           = -64;
cam_zoom        = 1.0;
cam_zoom_target = 1.0;
is_panning      = false;
cam_target_x = cam_x;
cam_target_y = cam_y;

//  7. INPUT SYSTEM 
// is_entering_text gates all keyboard input through the text modal,
// preventing node shortcuts from firing while the user is typing
is_entering_text     = false;
input_target_node    = noone;
input_target_index   = 0;
current_input_string = "";

// Q QUICK-SPAWN MENU
// Hold Q for 0.2s to pop a small grid of common nodes at the cursor;
// move over one and release Q to spawn it there, ready to wire up.
qmenu_active   = false;
qmenu_open     = false;
qmenu_timer    = 0;
qmenu_anchor_x = 0;
qmenu_anchor_y = 0;
qmenu_gui_x    = 0;
qmenu_gui_y    = 0;
qmenu_hover    = -1;
qmenu_items    = [
    { label: "COPY VAR", type: "COPY_VAR" },
    { label: "GET VAR", type: "GET_VAR" },
    { label: "SET VAR", type: "SET_VAR" },
    { label: "INC VAR", type: "INC_VAR" },
    { label: "DEC VAR", type: "DEC_VAR" },
    { label: "IF BYTE", type: "COND_IF" },
    { label: "IF WORD", type: "COND_IF_WORD" },
];

// USER CUSTOM QUICK MENU (Q key)
// Built up by the user via SHIFT+Q while hovering a MACROS menu item.
// Circular layout that grows to fit up to 24 items.
uqmenu_active   = false;
uqmenu_open     = false;
uqmenu_timer    = 0;
uqmenu_anchor_x = 0;
uqmenu_anchor_y = 0;
uqmenu_gui_x    = 0;
uqmenu_gui_y    = 0;
uqmenu_hover    = -1;

// Captured every frame the MACROS dropdown is open, read by SHIFT+Q
hover_macro_type  = "";
hover_macro_title = "";


// GLOBAL FX INITIALIZATION
global.fx = 0; 
global.fx_sys = part_system_create();
part_system_depth(global.fx_sys, -1000); 

global.fx_emitter = part_emitter_create(global.fx_sys); 

global.pt_node_vapor = part_type_create();

// 1. ASSIGN THE 64x64 LOGO
// Argument 3 & 4 (false, false): No animation/stretching needed for a static logo
// Argument 5 (false): Don't start on random frames
part_type_sprite(global.pt_node_vapor, spr_c64, false, false, false);

// 2. SCALE CALIBRATION
// 1.0 = 64px. 0.5 = 32px. 
// Let's have it start at 0.4 (approx 25px) and shrink to 0 as it vanishes.
part_type_size(global.pt_node_vapor, 0.1, 0.4, -0.01, 0); 

// 3. COLOR & FADE
// Keep it c_white so the C64 rainbow/logo colors aren't tinted!
part_type_color1(global.pt_node_vapor, c_white);
part_type_alpha2(global.pt_node_vapor, 1, 0); // Solid to invisible

// 4. MOTION (The "Vapor" drift)
part_type_speed(global.pt_node_vapor, 1, 2, -0.02, 0);
part_type_direction(global.pt_node_vapor, 0, 360, 0, 10); // Expands in all directions with a slight wiggle
part_type_life(global.pt_node_vapor, 20, 50);

// 5. CAFFEINE SPIN (Optional)
// Adds a subtle rotation so the logos look like they are tumbling in space
part_type_orientation(global.pt_node_vapor, 0, 360, 2, 0, false);

// Mapping Box system
global.box_drag_active  = false;
global.show_map_nav = false;
global.map_nav_x = 0;
global.map_nav_y = 0;



box_drag_start_x       = 0;
box_drag_start_y       = 0;
box_drag_live          = false;
box_popup_open         = false;
box_popup_target       = noone;
box_popup_is_edit      = false;
box_popup_name         = "";
box_popup_name_dupe    = false;
box_popup_col_idx      = 0;
box_cursor_pos         = 0;
box_dropdown_open      = false;

// ---- LABEL SEARCH MODAL (CTRL/CMD+SHIFT+F) ----
label_search_open    = false;
label_search_query   = "";
label_search_cursor  = 0;
label_search_ready   = false;
label_search_results = [];
label_search_index   = -1;

/// =============================================================
/// ADDITIONS TO Create_0.gml of obj_workspace_manager
/// Add this block after section 5 (SPAWN COMPULSORY ANCHOR NODE)
/// =============================================================

// ---- NAMED LOCATIONS INIT ----
// Must happen before any node tries to resolve a variable name.
global.named_loc_map    = ds_map_create();
global.named_loc_meta   = [];
global.named_loc_packed = false;
global.named_loc_meta_map = ds_map_create();
global.named_loc_meta_dirty = true;
global.any_picker_open    = false;
global.next_org_uid       = 1;
global.next_stable_uid    = 100000;
global.wire_drag_node     = noone;
global.wire_drag_is_out   = false;
scr_init_named_locations();

// ---- SPAWN VARIABLES MAPPING BOX ----
// Positioned to the left of the main spine, off-screen enough to
// stay out of the way but within easy spacebar-nav reach.
// The ORG node inside it owns the UV address block at $C000.

var _var_box_x = (room_width / 2) - 400;
var _var_box_y = 40;

// Spawn the VARIABLES ORG anchor node
var _n_vars          = instance_create_layer(_var_box_x + 20, _var_box_y + 20, "Layer_Nodes", obj_c64_node);
_n_vars.node_title   = "VARIABLES";
_n_vars.node_type    = "ORG";
_n_vars.proxy        = false;
_n_vars.is_draggable = true;
with (_n_vars) { event_user(0); }
_n_vars.pc_address   = 0xC000; // some defaults will auto calc at runtime.
_n_vars.proxy_address = 0xC000;
_n_vars.end_address  = 0xC000;

// Spawn the VARIABLES ORG anchor node
var _n_org          = instance_create_layer(_var_box_x + 580, _var_box_y + 20, "Layer_Nodes", obj_c64_node);
_n_org.node_title   = "ORG BLOCK";
_n_org.node_type    = "ORG";
_n_org.proxy        = true;
_n_org.is_draggable = true;
with (_n_org) { event_user(0); }



// ---- MENU BAR STATE ----
gui_menu_open         = -1;    // -1 = closed, 0..7 = which button is open
opcode_hover_key      = "";    // mnemonic currently being hovered
opcode_hover_timer    = 0;     // frames hovered so far
opcode_hover_delay    = 30;    // frames before tooltip shows (30 = 0.5s at 60fps)

// Node header tooltip — hover the right 20% of a node's header bar with
// no mouse button held for node_tooltip_delay frames to show a floating
// description of that node/macro. Set by obj_c64_node's Step event,
// drawn here in Draw GUI so it always renders on top.
node_tooltip_node    = noone;
node_tooltip_delay   = 60;     // frames before tooltip shows (60 = 1s at 60fps)
opcode_helper_on      = true;  // toggled via OPTIONS menu
gui_menu_drag_active  = false; // true once user starts dragging a macro from the menu
gui_menu_node_spawned = false; // guard: spawn only once per drag
gui_menu_drag_type    = "";
gui_menu_drag_title   = "";

// for var buttons
uv_pending_name = "";
uv_picking_type = false;
uv_pending_size = 1;
uv_pending_enc  = "byte";

// HW REGISTER PICKER TABLE
// Categorized list of C64 hardware register aliases.
global.hw_picker_categories = [
    {
        name: "VIC: SCREEN & BORDER",
        items: [
            "HW_BORDER", "HW_BGCOLOR0", "HW_BGCOLOR1", "HW_BGCOLOR2", "HW_BGCOLOR3",
            "HW_CTRL1", "HW_CTRL2", "HW_MEM_CTRL", "HW_RASTER",
            "HW_COLORRAM", "HW_SCREEN"
        ]
    },
    {
        name: "VIC: SPRITE POSITIONS",
        items: [
            "HW_SPR0_X", "HW_SPR0_Y", "HW_SPR1_X", "HW_SPR1_Y",
            "HW_SPR2_X", "HW_SPR2_Y", "HW_SPR3_X", "HW_SPR3_Y",
            "HW_SPR4_X", "HW_SPR4_Y", "HW_SPR5_X", "HW_SPR5_Y",
            "HW_SPR6_X", "HW_SPR6_Y", "HW_SPR7_X", "HW_SPR7_Y",
            "HW_SPR_X_MSB" // $D010 - The 9th bit for X coordinates > 255
        ]
    },
    {
        name: "VIC: SPRITE CONFIG",
        items: [
            "HW_SPR_EN", "HW_SPR_MC", "HW_SPR_DBL_X", "HW_SPR_DBL_Y",
            "HW_SPR_BGPRI", "HW_SPR_COLL", "HW_SPR_BGCOL", // Priority and Collisions
            "HW_SPR_PTR0", "HW_SPR_PTR1", "HW_SPR_PTR2", "HW_SPR_PTR3",
            "HW_SPR_PTR4", "HW_SPR_PTR5", "HW_SPR_PTR6", "HW_SPR_PTR7"
        ]
    },
    {
        name: "VIC: SPRITE COLORS",
        items: [
            "HW_SPR_MC0", "HW_SPR_MC1", // Shared multicolor 0 and 1
            "HW_SPR0_COL", "HW_SPR1_COL", "HW_SPR2_COL", "HW_SPR3_COL",
            "HW_SPR4_COL", "HW_SPR5_COL", "HW_SPR6_COL", "HW_SPR7_COL"
        ]
    },
    {
        name: "SID: VOICE 1",
        items: [
            "HW_V1_FREQL", "HW_V1_FREQH", "HW_V1_PWML", "HW_V1_PWMH",
            "HW_V1_CTRL", "HW_V1_AD", "HW_V1_SR"
        ]
    },
    {
        name: "SID: VOICE 2",
        items: [
            "HW_V2_FREQL", "HW_V2_FREQH", "HW_V2_PWML", "HW_V2_PWMH",
            "HW_V2_CTRL", "HW_V2_AD", "HW_V2_SR"
        ]
    },
    {
        name: "SID: VOICE 3",
        items: [
            "HW_V3_FREQL", "HW_V3_FREQH", "HW_V3_PWML", "HW_V3_PWMH",
            "HW_V3_CTRL", "HW_V3_AD", "HW_V3_SR",
            "HW_V3_OSC", "HW_V3_ENV" // RNG and Envelope reading
        ]
    },
    {
        name: "SID: FILTER & VOL",
        items: [
            "HW_FILT_LO", "HW_FILT_HI", "HW_FILT_CTRL", "HW_SID_VOL"
        ]
    },
    {
        name: "CIA & INPUT",
        items: [
            "HW_JOY1", "HW_JOY2",
            "HW_CIA2_PRA", "HW_CIA2_PRB",
            "HW_CIA1_ICR", "HW_CIA2_ICR",
            "HW_IRQ_STATUS", "HW_IRQ_MASK", "HW_IRQ_VEC_LO", "HW_IRQ_VEC_HI",
			"HW_C64U_SPEED"
        ]
    },
    {
        name: "KERNAL",
        items: [
            "HW_CHROUT", "HW_GETIN",
            "HW_JIFFIES_LO", "HW_JIFFIES_MID", "HW_JIFFIES_HI"
        ]
    }
];

// Tracking variable for the two-step menu (-1 means show categories)
global.hw_picker_active_category = -1;

// Start positioning comments below the header

/*
// Define the lines
var _hints = [
    "Right click to remove",
    "VARIABLES and click $ADDR to change it.",
	"F1 to cleanup unused nodes."
];

// Spawn just ONE comment node
var _cn = scr_spawn_comment_node(_var_box_x + 20, _var_box_y + 100);

// Join the array into a single string separated by newlines
var _combined_text = _hints[0] + "\n" + _hints[1] + "\n" + _hints[2];

// Assign properties
_cn.instructions[0][1] = _combined_text;
_cn.org_parent   = _n_vars; // Link to ORG so they move together
_cn.is_connected = true;
_cn.width        = global.node_display_width;

// Force a height recalculation for the new multi-line content
with(_cn) {
    draw_set_font(fnt_c64_code);
    height = 24 + string_height_ext(_combined_text, 18, width - 20) + 8;
}
*/
// slight delay for forced updates to nodes
alarm[1]=20;

save_pending = false;

global.isSaving=false
// ---- AUTOSAVE INIT ----
global.autosave_dirty     = false;
global.autosave_last_path = "";
global.manual_saved       = true;   // nothing to lose yet on fresh start
ini_open("c64devmachine.ini");
global.autosave_mode = clamp(ini_read_real("autosave", "mode", 1), 0, 3);
ini_close();
var _intervals = [180, 300, 600, -1];
global.autosave_interval = _intervals[global.autosave_mode];
autosave_hour = 0;
autosave_minute = 0;
last_save_hour = 0;
last_save_minute = 0;
global.node_change_dirty = false;
alarm[4] = game_get_speed(gamespeed_fps) * global.autosave_interval;
autosave_countdown = global.autosave_interval;
autosave_flash_timer = 0;
_was_panning = false;

// ---- IDLE SLEEP SYSTEM ----
global.idle_active   = false;   // true once idle threshold passed
idle_timer           = 0;       // seconds of no input
idle_threshold       = 5;      // seconds before sleep
idle_last_mx         = 0;       // last GUI mouse pos
idle_last_my         = 0;
global.idle_fade     = 1.0;     // 1 = awake, 0 = fully asleep
idle_snapshot_spr     = -1;      // sprite holding the frozen screen when idle
idle_snapshot_active  = false;   // true while the snapshot overlay is being shown


// ---- STARTUP: offer to restore latest autosave (via ini) ----
// Deferred to alarm[5] so obj_asset_manager is fully initialised first
alarm[5] = 40;

box_body_dbl_timer = 0;
box_body_dbl_target = noone;

scr_fix_vice_permissions_mac();

// ---- LOAD ALL PERSISTED SETTINGS ----
ini_open("c64devmachine.ini");

var _saved_x = ini_read_real("window", "x", 0);
var _saved_y = ini_read_real("window", "y", 28);
var _saved_w = ini_read_real("window", "w", 1920);
var _saved_h = ini_read_real("window", "h", 1000);

code_editor_font_index = clamp(ini_read_real("editor", "font_index", 3), 0, array_length(code_editor_fonts) - 1);
bkgImg       = clamp(ini_read_real("Settings", "bkgImg",       0), 0, max(0, sprite_get_number(spr_bkg) - 1));
showGrid     = ini_read_real("Settings", "showGrid",      0);
paletteStyle = clamp(ini_read_real("Settings", "paletteStyle", 0), 0, max(0, sprite_get_number(spr_palette_page) - 1));
badgeStyle   = clamp(ini_read_real("Settings", "badgeStyle",   0), 0, max(0, sprite_get_number(spr_logobadge) - 1));
buttonStyle  = clamp(ini_read_real("Settings", "buttonStyle",  0), 0, max(0, sprite_get_number(spr_opcode_button) - 2));
niceSliceFrm = clamp(ini_read_real("Settings", "niceSliceFrm", 0), 0, max(0, sprite_get_number(spr_glassSlice) - 1));
uiChromeStyle = clamp(ini_read_real("Settings", "uiChromeStyle", 0), 0, 1);
nodeStyle     = clamp(ini_read_real("Settings", "nodeStyle", 0), 0, sprite_get_number(spr_9s_tile1));
macroStyle    = clamp(ini_read_real("Settings", "macroStyle", 0), 0, 1);
expert_mode  = ini_read_real("Settings", "expert_mode", 0) == 1;
opcode_helper_on       = ini_read_real("Settings", "opcode_helper",       1) == 1;
showPaletteHelper      = ini_read_real("Settings", "palette_helper",      1) == 1;
global.visual_fx       = ini_read_real("Settings", "visual_fx",           1) == 1;
global.node_destroy_fx = global.visual_fx;
global.comments_visible = ini_read_real("Settings", "comments_visible",   1) == 1;
opcode_headers_on      = ini_read_real("Settings", "opcode_headers",      0) == 1;
opcode_extra_height    = ini_read_real("Settings", "opcode_extra_height", 1) == 1;
flow_line_style        = ini_read_real("Settings", "flow_line_style",     1);
var _hide_welcome = ini_read_real("Settings", "hide_welcome", 0);
welcome_hide_checked = (_hide_welcome != 0);
welcome_open          = !welcome_hide_checked;

// ---- SHOW CODE PANEL (floating live listing, left of the shortcuts column) ----
// -1 on x is the "never positioned" marker; the draw script parks it beside the
// shortcuts column the first time it runs, then this holds the dragged position.
showcode_x    = ini_read_real("showcode", "x",    -1);
showcode_y    = ini_read_real("showcode", "y",    50);
showcode_open = (ini_read_real("showcode", "open", 1) == 1);
showcode_mode = clamp(ini_read_real("showcode", "mode", 0), 0, 1);

ini_close();

showcode_w         = 420;   // panel width in GUI px
showcode_rows      = 20;    // visible listing rows before it scrolls
showcode_scroll    = 0;
showcode_flat      = [];    // every emitted line, unfolded
showcode_lines     = [];    // the visible rows, after macro folding
showcode_expanded  = [];    // node keys of the macro groups currently open
showcode_gen       = -1;    // named_loc_repack_gen the flat list was built from
showcode_dirty     = true;
showcode_dragging  = false;
showcode_drag_dx   = 0;
showcode_drag_dy   = 0;

// Read by obj_c64_node and the camera zoom guard so a click or a wheel over the
// panel never reaches the workspace underneath.
global.showcode_mouse_over = false;

scr_uqmenu_load();

// FLOW OVERLAY (F key) — toggleable visualization of JMP/JSR/BRANCH/IRQ-
// vector control flow across the spine. Cached and only rebuilt when
// flow_overlay_dirty is set (by node spawn/destroy) — avoids re-running a
// full compile+assemble pass on every single toggle when nothing changed.
flow_overlay_mode = 0; // 0 = Off, 1 = Local Hover, 2 = Show All
flow_overlay_edges  = [];
flow_overlay_dirty  = true;
// flow_line_style: 0 = Direct (straight lines), 1 = Angled (45-degree
// chamfered routing, current default). Set above via ini_read_real so
// it persists across sessions like the other OPTIONS menu toggles.

// Rebuilding runs a full compile+assemble pass and can take a visible
// moment on a large spine. Since the engine only presents a frame after
// Step+Draw both finish, calling scr_build_flow_graph() inline would
// freeze the screen for that whole pause with nothing shown. Instead the
// trigger sites below queue the build (flow_overlay_build_pending) and
// show "CONSTRUCTING FLOW DATA" immediately; the actual build runs first
// thing next Step, once that frame has had a chance to render.
flow_overlay_build_pending      = false;
flow_overlay_pending_toast_text = "";
flow_overlay_pending_toast_col  = c_yellow;

// Restore window position and size from last session.
// Only apply if the saved values look sane (w/h > 0).
if (_saved_w > 0 && _saved_h > 0)
{
    window_set_size(_saved_w, _saved_h);
    window_set_position(_saved_x, _saved_y);
}
