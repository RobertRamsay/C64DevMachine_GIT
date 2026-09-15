/// @function scr_hud_create(_asset)
/// @desc Seeds the meta for a fresh HUD asset. Every field the editor or the
///       compile chain touches is initialised here, so neither has to test for
///       a missing member at runtime.
///
/// A HUD is a RECTANGLE OF SCREEN — a char grid plus a colour grid covering
/// cells (hud_x, hud_y) to (hud_x + hud_w - 1, hud_y + hud_h - 1) of the 40x25
/// text screen. That is what a status panel actually is on a C64: a block of
/// screen RAM and matching colour RAM that the game stamps down once and then
/// pokes individual cells of as the score, lives or keys change.
///
/// MACRO_HUD emits the two grids inline, plus a <key>_draw entry point that
/// stamps them into screen/colour RAM, plus one entry point per FIELD.
///
/// FIELDS are the cells the game writes at runtime:
///   kind 0 TEXT   — position only. No code emitted; the label is there so a
///                   code block can find the cell without counting rows.
///   kind 1 DIGITS — <key>_<name> takes a value 0-255 in A and writes it as
///                   decimal digits, right-aligned across the field.
///   kind 2 BAR    — <key>_<name> takes a count in A and fills that many cells
///                   with `full`, the rest with `empty` (lives, energy, ammo).
///
/// The asset carries no address of its own: the data is emitted by the node,
/// on the spine, jumped over — the same arrangement MACRO_SID_SONG uses for a
/// MUSIC_MAKER asset.
function scr_hud_create(_asset) {

    var _w = 40;
    var _h = 5;

    _asset.meta = {
        // ── SCREEN RECT ──
        hud_x         : 0,
        hud_y         : 20,
        hud_w         : _w,
        hud_h         : _h,

        // ── CONTENT ── one entry per cell, row-major, hud_w wide.
        char_grid     : array_create(_w * _h, 32),   // 32 = space
        colour_grid   : array_create(_w * _h, 1),    // 1 = white

        // ── LINKED CHARSET ── "" renders the ROM font shape-for-shape, which
        // is close enough to place text against before the real set exists.
        chr_asset     : "",

        // ── FIELDS ── see the header. fx/fy are RELATIVE to the rect.
        fields        : [],
        sel_field     : -1,

        // ── EDITOR STATE ──
        active_char   : 32,
        active_colour : 1,
        paint_mc      : 0,       // 1 = painted cells are multicolour cells
        hud_mc_bg     : -1,      // -1 = inherit from the linked charset
        hud_mc_col1   : -1,
        hud_mc_col2   : -1,
        zoom          : 2,
        cur_x         : 0,       // typing cursor, relative to the rect
        cur_y         : 0,
        show_grid     : 1,
        show_screen   : 1,       // draw the whole 40x25 screen, rect highlighted

        // ── GLYPH ATLASES ── built lazily by scr_hud_atlas, never serialised.
        atlas_hr      : -1,
        atlas_mcs     : -1,
        atlas_mcf     : -1,
        atlas_key     : "",

        // ── NAME EDIT ──
        name_edit_active : false,
        name_edit_buf    : "",

        // ── UNDO / REDO ── session-only, same shape as the map editor's.
        undo_stack    : [],
        redo_stack    : [],

        // ── WARNING LINE ──
        warn_msg      : "",
        warn_timer    : 0
    };

    scr_hud_flush(_asset);
}
