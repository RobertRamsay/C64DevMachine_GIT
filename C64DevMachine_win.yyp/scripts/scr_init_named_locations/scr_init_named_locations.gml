/// @desc scr_init_named_locations()
/// Builds global named location tables for HW_ and UV_ variables.
/// Call once from Create_0 of obj_workspace_manager.
///
/// global.named_loc_map    — ds_map  name -> address  (for compiler)
/// global.named_loc_meta   — array   of structs        (for UI)
/// global.named_loc_packed — true once allocator has run

function scr_init_named_locations() {

    if (ds_exists(global.named_loc_map, ds_type_map)) ds_map_destroy(global.named_loc_map);
    global.named_loc_map    = ds_map_create();
    global.named_loc_meta   = [];
    global.named_loc_packed = true;

    // ---- VIC-II SPRITE POSITIONS ----
    scr_nloc_hw("HW_SPR0_X",     0xD000, "VIC",    "Sprite 0 X position");
    scr_nloc_hw("HW_SPR0_Y",     0xD001, "VIC",    "Sprite 0 Y position");
    scr_nloc_hw("HW_SPR1_X",     0xD002, "VIC",    "Sprite 1 X position");
    scr_nloc_hw("HW_SPR1_Y",     0xD003, "VIC",    "Sprite 1 Y position");
    scr_nloc_hw("HW_SPR2_X",     0xD004, "VIC",    "Sprite 2 X position");
    scr_nloc_hw("HW_SPR2_Y",     0xD005, "VIC",    "Sprite 2 Y position");
    scr_nloc_hw("HW_SPR3_X",     0xD006, "VIC",    "Sprite 3 X position");
    scr_nloc_hw("HW_SPR3_Y",     0xD007, "VIC",    "Sprite 3 Y position");
    scr_nloc_hw("HW_SPR4_X",     0xD008, "VIC",    "Sprite 4 X position");
    scr_nloc_hw("HW_SPR4_Y",     0xD009, "VIC",    "Sprite 4 Y position");
    scr_nloc_hw("HW_SPR5_X",     0xD00A, "VIC",    "Sprite 5 X position");
    scr_nloc_hw("HW_SPR5_Y",     0xD00B, "VIC",    "Sprite 5 Y position");
    scr_nloc_hw("HW_SPR6_X",     0xD00C, "VIC",    "Sprite 6 X position");
    scr_nloc_hw("HW_SPR6_Y",     0xD00D, "VIC",    "Sprite 6 Y position");
    scr_nloc_hw("HW_SPR7_X",     0xD00E, "VIC",    "Sprite 7 X position");
    scr_nloc_hw("HW_SPR7_Y",     0xD00F, "VIC",    "Sprite 7 Y position");

    // ---- VIC-II SPRITE CONTROL ----
    scr_nloc_hw("HW_SPR_X_MSB",  0xD010, "VIC",    "Sprite X MSB (bit 8 of X per sprite)");
    scr_nloc_hw("HW_SPR_EN",     0xD015, "VIC",    "Sprite enable (1 bit per sprite)");
    scr_nloc_hw("HW_SPR_DBL_Y",  0xD017, "VIC",    "Sprite double height");
    scr_nloc_hw("HW_SPR_DBL_X",  0xD01D, "VIC",    "Sprite double width");
    scr_nloc_hw("HW_SPR_BGPRI",  0xD01B, "VIC",    "Sprite vs background priority");
    scr_nloc_hw("HW_SPR_MC",     0xD01C, "VIC",    "Sprite multicolor enable");
    scr_nloc_hw("HW_SPR_COLL",   0xD01E, "VIC",    "Sprite-sprite collision (read)");
    scr_nloc_hw("HW_SPR_BGCOL",  0xD01F, "VIC",    "Sprite-background collision (read)");
    scr_nloc_hw("HW_SPR_MC0",    0xD025, "VIC",    "Sprite multicolor 0 (shared)");
    scr_nloc_hw("HW_SPR_MC1",    0xD026, "VIC",    "Sprite multicolor 1 (shared)");
    scr_nloc_hw("HW_SPR0_COL",   0xD027, "VIC",    "Sprite 0 color");
    scr_nloc_hw("HW_SPR1_COL",   0xD028, "VIC",    "Sprite 1 color");
    scr_nloc_hw("HW_SPR2_COL",   0xD029, "VIC",    "Sprite 2 color");
    scr_nloc_hw("HW_SPR3_COL",   0xD02A, "VIC",    "Sprite 3 color");
    scr_nloc_hw("HW_SPR4_COL",   0xD02B, "VIC",    "Sprite 4 color");
    scr_nloc_hw("HW_SPR5_COL",   0xD02C, "VIC",    "Sprite 5 color");
    scr_nloc_hw("HW_SPR6_COL",   0xD02D, "VIC",    "Sprite 6 color");
    scr_nloc_hw("HW_SPR7_COL",   0xD02E, "VIC",    "Sprite 7 color");

// ---- SPRITE POINTERS ----
    // Default: bank 0, screen at $0400 -> pointers at $07F8.
    // scr_update_spr_ptr_hw_locs() patches these each frame
    // to reflect the actual MACRO_BMP / MACRO_VIC configuration.
    scr_nloc_hw("HW_SPR_PTR0",   0x07F8, "VIC",    "Sprite 0 pointer");
    scr_nloc_hw("HW_SPR_PTR1",   0x07F9, "VIC",    "Sprite 1 pointer");
    scr_nloc_hw("HW_SPR_PTR2",   0x07FA, "VIC",    "Sprite 2 pointer");
    scr_nloc_hw("HW_SPR_PTR3",   0x07FB, "VIC",    "Sprite 3 pointer");
    scr_nloc_hw("HW_SPR_PTR4",   0x07FC, "VIC",    "Sprite 4 pointer");
    scr_nloc_hw("HW_SPR_PTR5",   0x07FD, "VIC",    "Sprite 5 pointer");
    scr_nloc_hw("HW_SPR_PTR6",   0x07FE, "VIC",    "Sprite 6 pointer");
    scr_nloc_hw("HW_SPR_PTR7",   0x07FF, "VIC",    "Sprite 7 pointer");

    // ---- VIC-II SCREEN CONTROL ----
    scr_nloc_hw("HW_CTRL1",      0xD011, "VIC",    "Control reg 1 (screen on, bitmap, scroll Y)");
    scr_nloc_hw("HW_RASTER",     0xD012, "VIC",    "Raster counter / IRQ trigger line");
    scr_nloc_hw("HW_CTRL2",      0xD016, "VIC",    "Control reg 2 (multicolor, scroll X, columns)");
    scr_nloc_hw("HW_MEM_CTRL",   0xD018, "VIC",    "Memory control (screen/char base addresses)");
    scr_nloc_hw("HW_IRQ_STATUS", 0xD019, "VIC",    "IRQ status (write to acknowledge)");
    scr_nloc_hw("HW_IRQ_MASK",   0xD01A, "VIC",    "IRQ enable mask");

    // ---- VIC-II COLORS ----
    scr_nloc_hw("HW_BORDER",     0xD020, "VIC",    "Border color");
    scr_nloc_hw("HW_BGCOLOR0",   0xD021, "VIC",    "Background color 0");
    scr_nloc_hw("HW_BGCOLOR1",   0xD022, "VIC",    "Background color 1 (ECM/MCM)");
    scr_nloc_hw("HW_BGCOLOR2",   0xD023, "VIC",    "Background color 2 (ECM/MCM)");
    scr_nloc_hw("HW_BGCOLOR3",   0xD024, "VIC",    "Background color 3 (ECM only)");
    scr_nloc_hw("HW_SCREEN",     0x0400, "VIC",    "Screen RAM base (default)");
    scr_nloc_hw("HW_COLORRAM",   0xD800, "VIC",    "Color RAM base");

    // ---- SID VOICE 1 ----
    scr_nloc_hw("HW_V1_FREQL",   0xD400, "SID",    "Voice 1 frequency low byte");
    scr_nloc_hw("HW_V1_FREQH",   0xD401, "SID",    "Voice 1 frequency high byte");
    scr_nloc_hw("HW_V1_PWML",    0xD402, "SID",    "Voice 1 pulse width low");
    scr_nloc_hw("HW_V1_PWMH",    0xD403, "SID",    "Voice 1 pulse width high");
    scr_nloc_hw("HW_V1_CTRL",    0xD404, "SID",    "Voice 1 control (waveform/gate/sync/ring)");
    scr_nloc_hw("HW_V1_AD",      0xD405, "SID",    "Voice 1 Attack/Decay");
    scr_nloc_hw("HW_V1_SR",      0xD406, "SID",    "Voice 1 Sustain/Release");

    // ---- SID VOICE 2 ----
    scr_nloc_hw("HW_V2_FREQL",   0xD407, "SID",    "Voice 2 frequency low byte");
    scr_nloc_hw("HW_V2_FREQH",   0xD408, "SID",    "Voice 2 frequency high byte");
    scr_nloc_hw("HW_V2_PWML",    0xD409, "SID",    "Voice 2 pulse width low");
    scr_nloc_hw("HW_V2_PWMH",    0xD40A, "SID",    "Voice 2 pulse width high");
    scr_nloc_hw("HW_V2_CTRL",    0xD40B, "SID",    "Voice 2 control");
    scr_nloc_hw("HW_V2_AD",      0xD40C, "SID",    "Voice 2 Attack/Decay");
    scr_nloc_hw("HW_V2_SR",      0xD40D, "SID",    "Voice 2 Sustain/Release");

    // ---- SID VOICE 3 ----
    scr_nloc_hw("HW_V3_FREQL",   0xD40E, "SID",    "Voice 3 frequency low byte");
    scr_nloc_hw("HW_V3_FREQH",   0xD40F, "SID",    "Voice 3 frequency high byte");
    scr_nloc_hw("HW_V3_PWML",    0xD410, "SID",    "Voice 3 pulse width low");
    scr_nloc_hw("HW_V3_PWMH",    0xD411, "SID",    "Voice 3 pulse width high");
    scr_nloc_hw("HW_V3_CTRL",    0xD412, "SID",    "Voice 3 control");
    scr_nloc_hw("HW_V3_AD",      0xD413, "SID",    "Voice 3 Attack/Decay");
    scr_nloc_hw("HW_V3_SR",      0xD414, "SID",    "Voice 3 Sustain/Release");

    // ---- SID FILTER & MASTER ----
    scr_nloc_hw("HW_FILT_LO",    0xD415, "SID",    "Filter cutoff low (bits 0-2)");
    scr_nloc_hw("HW_FILT_HI",    0xD416, "SID",    "Filter cutoff high");
    scr_nloc_hw("HW_FILT_CTRL",  0xD417, "SID",    "Filter resonance and voice routing");
    scr_nloc_hw("HW_SID_VOL",    0xD418, "SID",    "Master volume and filter mode (bits 0-3)");
    scr_nloc_hw("HW_SID_POTX",   0xD419, "SID",    "Paddle X (read only)");
    scr_nloc_hw("HW_SID_POTY",   0xD41A, "SID",    "Paddle Y (read only)");
    scr_nloc_hw("HW_V3_OSC",     0xD41B, "SID",    "Voice 3 oscillator readback (read only)");
    scr_nloc_hw("HW_V3_ENV",     0xD41C, "SID",    "Voice 3 envelope readback (read only)");

    // ---- CIA 1 ----
    scr_nloc_hw("HW_JOY2",       0xDC00, "CIA1",   "Joystick port 2 / keyboard columns");
    scr_nloc_hw("HW_JOY1",       0xDC01, "CIA1",   "Joystick port 1 / keyboard rows");
    scr_nloc_hw("HW_CIA1_TALO",  0xDC04, "CIA1",   "Timer A low byte");
    scr_nloc_hw("HW_CIA1_TAHI",  0xDC05, "CIA1",   "Timer A high byte");
    scr_nloc_hw("HW_CIA1_TBLO",  0xDC06, "CIA1",   "Timer B low byte");
    scr_nloc_hw("HW_CIA1_TBHI",  0xDC07, "CIA1",   "Timer B high byte");
    scr_nloc_hw("HW_CIA1_ICR",   0xDC0D, "CIA1",   "Interrupt control register");
    scr_nloc_hw("HW_CIA1_CRA",   0xDC0E, "CIA1",   "Control register A");
    scr_nloc_hw("HW_CIA1_CRB",   0xDC0F, "CIA1",   "Control register B");

    // ---- CIA 2 ----
    scr_nloc_hw("HW_CIA2_PRA",   0xDD00, "CIA2",   "Port A — VIC bank bits 0-1");
    scr_nloc_hw("HW_CIA2_PRB",   0xDD01, "CIA2",   "Port B — User port");
    scr_nloc_hw("HW_CIA2_ICR",   0xDD0D, "CIA2",   "Interrupt control (NMI source)");
	

    // ---- IRQ VECTORS ----
    scr_nloc_hw("HW_IRQ_VEC_LO", 0x0314, "KERNAL", "IRQ vector low byte");
    scr_nloc_hw("HW_IRQ_VEC_HI", 0x0315, "KERNAL", "IRQ vector high byte");
    scr_nloc_hw("HW_NMI_VEC_LO", 0x0318, "KERNAL", "NMI vector low byte");
    scr_nloc_hw("HW_NMI_VEC_HI", 0x0319, "KERNAL", "NMI vector high byte");
	scr_nloc_hw("HW_C64U_SPEED", 0xD031, "KERNAL", "C64U Speed byte 0-15");

    // ---- KERNAL ----
    scr_nloc_hw("HW_CHROUT",     0xFFD2, "KERNAL", "Output char in A to current device");
    scr_nloc_hw("HW_GETIN",      0xFFE4, "KERNAL", "Read char from keyboard buffer");
    scr_nloc_hw("HW_CHRIN",      0xFFCF, "KERNAL", "Input a character");
    scr_nloc_hw("HW_CLRSCR",     0xE544, "KERNAL", "Clear screen (JSR target)");

    // ---- OS CLOCKS ----
    scr_nloc_hw("HW_JIFFIES_LO", 0x00A2, "OS",     "Jiffy clock low byte (60Hz)");
    scr_nloc_hw("HW_JIFFIES_MID",0x00A1, "OS",     "Jiffy clock mid byte");
    scr_nloc_hw("HW_JIFFIES_HI", 0x00A0, "OS",     "Jiffy clock high byte");

    // ----------------------------------------------------------------
    // USER VARIABLES — auto-packed from $C000
    // scr_nloc_uv returns the advanced cursor value each call
    // ----------------------------------------------------------------
    var _c = global.start_pc;



}
