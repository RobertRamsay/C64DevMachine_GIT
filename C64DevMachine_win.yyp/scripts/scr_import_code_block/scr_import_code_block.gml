/// ====================================================================
/// CODE BLOCK IMPORT  (PRO — gated behind !global.lite)
///
/// The mirror of the EXPORT button in scr_code_editor_draw. Two ways in:
///
///   * IMPORT button, inside the code editor. Acts on the block being
///     edited: appends or replaces, and asks which when the block already
///     holds code.
///
///   * IMPORT menu -> CODE BLOCK (.ASM). Spawns a NEW code block holding
///     the file and latches it to the pointer, so the drop position is a
///     click rather than a guess. The menu entry is built only when
///     !global.lite, so there is nothing to choose in the Lite build.
///
/// Functions:
///   scr_import_code_block_read()     file dialog -> text ("" on cancel)
///   scr_import_code_block_menu()     menu entry: spawn + latch
///   scr_code_import_step()           ride the pointer, drop, cancel
///   scr_code_import_draw_banner()    the "click to drop it" strip
///   scr_code_import_primary_pressed() one platform seam, as elsewhere
/// ====================================================================

/// @function scr_import_code_block_read()
/// @desc Open a file dialog and read an assembly listing whole.
/// @return {String} the file text, or "" when cancelled or unreadable.
function scr_import_code_block_read() {
    var _path = get_open_filename("Assembly Files|*.asm;*.txt|All Files|*.*", "");
    // A native file dialog takes focus, so the key-up that ends the keypress is
    // delivered to the dialog and not to the game. GameMaker is left thinking the
    // key is still held, and keyboard_check_pressed() needs an up->down edge — so
    // ESC silently stops working until the input state is reset. Every importer
    // in this project does this immediately after its dialog returns.
    io_clear();

    if (_path == "") {
        return "";
    }
    if (!file_exists(_path)) {
        scr_show_message("CODE IMPORT\n\nThat file could not be found.");
        return "";
    }

    // buffer_load + buffer_text reads the whole file as one string, newlines
    // intact. The file_text_read_string loop the asset importers use drops the
    // line breaks, which is fine for a byte list and useless for source.
    var _buf = buffer_load(_path);
    if (_buf < 0) {
        scr_show_message("CODE IMPORT\n\nThat file could not be read.");
        return "";
    }
    var _txt = buffer_read(_buf, buffer_text);
    buffer_delete(_buf);

    // A Windows-authored .asm opened on macOS otherwise carries CRs into
    // scr_parse_asm_text, which reads them as part of the operand.
    _txt = string_replace_all(_txt, "\r\n", "\n");
    _txt = string_replace_all(_txt, "\r",   "\n");

    if (string_trim(_txt) == "") {
        scr_show_message("CODE IMPORT\n\nThat file is empty.");
        return "";
    }
    return _txt;
}

/// @function scr_import_code_block_menu()
/// @desc IMPORT menu entry. Reads a file, spawns a code block holding it, and
///       latches that block to the pointer until the next click drops it.
function scr_import_code_block_menu() {
    // The menu does not offer this in Lite, but the guard stays: a menu list is
    // one edit away from being built unconditionally again.
    if (global.lite) {
        scr_show_message("CODE BLOCKS ARE A FULL VERSION FEATURE");
        return;
    }
    if (global.code_import_node != noone) {
        return;   // one in flight is enough
    }

    var _txt = scr_import_code_block_read();
    if (_txt == "") {
        return;
    }

    var _n = scr_node_spawn("MACRO_CODE", mouse_x, mouse_y);
    _n.instructions[0][1] = _txt;
    _n.code_descriptor    = "IMPORTED CODE";
    _n.code_cache_dirty   = true;
    _n.height_dirty       = true;
    with (_n) { event_user(0); }

    global.code_import_node    = _n;
    global.code_import_release = 0;

    // obj_c64_node's Step exits wholesale on this, so the latched block cannot
    // be grabbed, dragged or edited by the very click meant to drop it.
    global.canEditNode = false;
}

/// @function scr_code_import_step()
/// @desc Call early in obj_workspace_manager's Step. While a block is latched
///       this owns the frame, the same way the code editor and welcome screen
///       do, so no workspace shortcut fires under the pointer.
/// @return {Bool} true while the import owns the frame.
function scr_code_import_step() {
    // Input is handed back a frame late on purpose. Instance Step order is not
    // defined, so releasing canEditNode in the same frame as the drop click can
    // let obj_c64_node see that same press and start a drag on the block that
    // was just placed.
    if (global.code_import_release > 0) {
        global.code_import_release -= 1;
        if (global.code_import_release == 0) {
            global.canEditNode = true;
        }
        return true;
    }

    if (global.code_import_node == noone) {
        return false;
    }
    if (!instance_exists(global.code_import_node)) {
        global.code_import_node = noone;
        global.canEditNode      = true;
        return false;
    }

    var _n = global.code_import_node;
    _n.x = mouse_x - (_n.width / 2);
    _n.y = mouse_y - 12;

    // ESC abandons the import rather than leaving a block stuck to the pointer
    // with no way off it.
    if (keyboard_check_pressed(vk_escape)) {
        instance_destroy(_n);
        global.code_import_node = noone;
        global.canEditNode      = true;
        keyboard_clear(vk_escape);
        return true;
    }

    if (scr_code_import_primary_pressed()) {
        global.code_import_node    = noone;
        global.code_import_release = 2;

        global.addresses_dirty = true;
        global.undo_dirty      = true;
        global.autosave_dirty  = true;

        with (obj_c64_node) {
            stats_cache_dirty = true;
            height_dirty      = true;
        }
    }
    return true;
}

/// @function scr_code_import_draw_banner()
/// @desc The strip along the bottom of the GUI while a block is latched.
///       Call from obj_workspace_manager's Draw GUI.
function scr_code_import_draw_banner() {
    if (global.code_import_node == noone)          { exit; }
    if (!instance_exists(global.code_import_node)) { exit; }

    var _gw = global.gui_w;
    var _gh = display_get_gui_height();
    var _bh = 28;
    var _by = _gh - _bh - 10;
    var _bw = 620;
    var _bx = floor((_gw - _bw) / 2);

    draw_sprite_stretched(spr_glassSlice, niceSliceFrm, _bx, _by, _bw, _bh);

    var _font_before   = draw_get_font();
    var _halign_before = draw_get_halign();
    var _valign_before = draw_get_valign();

    draw_set_font(fnt_C64_Angled);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_color(make_color_rgb(255, 210, 80));
    draw_rectangle(_bx + 2, _by + 2, _bx + _bw - 2, _by + _bh - 2, true);
    draw_text(_bx + (_bw / 2), _by + (_bh / 2),
              "IMPORTED CODE LATCHED TO MOUSE - CLICK TO DROP IT   (ESC CANCELS)");

    draw_set_font(_font_before);
    draw_set_halign(_halign_before);
    draw_set_valign(_valign_before);
    draw_set_color(c_white);
}

// Windows uses the raw button; the macOS port swaps the body of this one
// function for `return scr_primary_pressed();` and nothing else changes.
function scr_code_import_primary_pressed() {
    return mouse_check_button_pressed(mb_left);
}
