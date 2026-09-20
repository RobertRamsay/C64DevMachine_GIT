/// @function scr_compile_macro_uci_reu(_list, _curr)
/// @description Emits an Ultimate Command Interface request that makes the
///              cartridge load a .reu image from its OWN storage into REU
///              memory, before the program carries on.
///
/// This is not the same problem as attaching an image to an emulator. VICE is
/// told about its image on the command line (scr_launch_vice, and the launcher
/// written beside a manual export). F6 pushes an image over the network. This
/// node covers the third case: a PRG sitting on the Ultimate's own SD or USB,
/// started from its file browser, with no host machine involved at all. The
/// program asks the firmware to fetch its own data.
///
/// Register map, per the Ultimate documentation:
///   $DF1C  write: control      read: status
///   $DF1D  write: command data read: identification ($C9, or $49 during IRQ)
///   $DF1E  read:  response data
///   $DF1F  read:  status data
///
/// STATE lives in bits 1-0 of the status register - 00 idle, 01 command busy,
/// 10 data last, 11 data more - with DATA_AV in bit 7 and STAT_AV in bit 6.
/// Masking $30 for those, as circulating example code does, reads two bits
/// that are always zero: the idle wait then falls straight through and the
/// data comparisons can never match.
///
/// The command is target $04 (control target), command $08 (LOAD REU),
/// followed by the filename. It answers with a 4-byte little-endian transfer
/// count and a status string, both of which must be drained before the
/// interface returns to idle. The first status byte is what distinguishes
/// "00,OK" from "84,REU NOT ENABLED" and "85,REU FILE CANNOT BE OPENED", so
/// it is kept rather than thrown away.

function scr_compile_macro_uci_reu(_list, _curr) {
    var _id   = _curr;
    var _inst = _id.instructions[0];

    var _manifest_name = (array_length(_inst) > 1) ? string(_inst[1]) : "";
    var _override      = (array_length(_inst) > 2) ? string(_inst[2]) : "";
    var _status_var    = (array_length(_inst) > 3) ? string(_inst[3]) : "";

    // The filename follows the LOAD_REU asset unless explicitly overridden,
    // so renaming the manifest cannot silently leave this node pointing at a
    // file that is no longer written.
    var _filename = _override;
    if (_filename == "") {
        var _manifest = scr_reu_find_asset(_manifest_name);
        if (!is_undefined(_manifest) && variable_struct_exists(_manifest, "reu_filename")) {
            _filename = string(_manifest.reu_filename);
        }
    }
    if (_filename == "") {
        show_debug_message("MACRO_UCI_REU WARNING: no filename (manifest=[" + _manifest_name + "]) - skipping emit");
        exit;
    }

    var _status_addr = 0;
    if (_status_var != "") {
        _status_addr = scr_resolve_var_addr(_status_var);
        if (_status_addr == 0) {
            show_debug_message("MACRO_UCI_REU WARNING: status var unresolved: " + _status_var);
        }
    }

    var _pfx        = "uci" + string(real(_id)) + "_";
    var _l_absent   = _pfx + "absent";
    var _l_idle     = _pfx + "idle";
    var _l_name     = _pfx + "name";
    var _l_send     = _pfx + "send";
    var _l_sent     = _pfx + "sent";
    var _l_wait     = _pfx + "wait";
    var _l_drain    = _pfx + "drain";
    var _l_nodata   = _pfx + "nodata";
    var _l_done     = _pfx + "done";
    var _l_final    = _pfx + "final";
    var _l_skipkeep = _pfx + "skipkeep";

    var UCI_CONTROL  = 0xDF1C;
    var UCI_COMMAND  = 0xDF1D;
    var UCI_RESPONSE = 0xDF1E;
    var UCI_STATUS   = 0xDF1F;

    // ---- PRESENCE ----
    // On hardware without the interface these registers are open bus, and the
    // idle wait below would spin forever. Identification reads $C9 normally
    // and $49 while an interrupt is being serviced.
    array_push(_list, ["lda_abs", UCI_COMMAND, _id]);
    array_push(_list, ["cmp_imm", 0xC9,        _id]);
    array_push(_list, ["beq",     _l_idle,     _id]);
    array_push(_list, ["cmp_imm", 0x49,        _id]);
    array_push(_list, ["bne",     _l_absent,   _id]);

    // ---- WAIT FOR IDLE ----
    array_push(_list, ["label",   _l_idle,     _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL, _id]);
    array_push(_list, ["and_imm", 0x03,        _id]);
    array_push(_list, ["bne",     _l_idle,     _id]);

    // ---- COMMAND: target $04, command $08, then the filename ----
    array_push(_list, ["lda_imm", 0x04,        _id]);
    array_push(_list, ["sta_abs", UCI_COMMAND, _id]);
    array_push(_list, ["lda_imm", 0x08,        _id]);
    array_push(_list, ["sta_abs", UCI_COMMAND, _id]);

    array_push(_list, ["ldx_imm", 0x00,        _id]);
    array_push(_list, ["label",   _l_send,     _id]);
    array_push(_list, ["lda_abx", _l_name,     _id]);
    array_push(_list, ["beq",     _l_sent,     _id]);
    array_push(_list, ["sta_abs", UCI_COMMAND, _id]);
    array_push(_list, ["inx",     0,           _id]);
    array_push(_list, ["bne",     _l_send,     _id]);
    array_push(_list, ["label",   _l_sent,     _id]);

    array_push(_list, ["lda_imm", 0x01,        _id]);   // PUSH_CMD
    array_push(_list, ["sta_abs", UCI_CONTROL, _id]);

    // ---- WAIT WHILE BUSY ----
    array_push(_list, ["label",   _l_wait,     _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL, _id]);
    array_push(_list, ["and_imm", 0x03,        _id]);
    array_push(_list, ["cmp_imm", 0x01,        _id]);
    array_push(_list, ["beq",     _l_wait,     _id]);

    // ---- DRAIN ----
    // Response bytes first (bit 7), then status bytes (bit 6), until neither
    // is offered. The first status byte is the one worth keeping; the rest of
    // the string is read and discarded so the interface can return to idle.
    if (_status_addr != 0) {
        array_push(_list, ["lda_imm", 0xFF,         _id]);
        array_push(_list, ["sta_abs", _status_addr, _id]);
    }

    array_push(_list, ["label",   _l_drain,     _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL,  _id]);
    array_push(_list, ["bpl",     _l_nodata,    _id]);
    array_push(_list, ["lda_abs", UCI_RESPONSE, _id]);
    array_push(_list, ["jmp_abs", _l_drain,     _id]);

    array_push(_list, ["label",   _l_nodata,    _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL,  _id]);
    array_push(_list, ["and_imm", 0x40,         _id]);
    array_push(_list, ["beq",     _l_done,      _id]);
    array_push(_list, ["lda_abs", UCI_STATUS,   _id]);

    if (_status_addr != 0) {
        // Keep only the first status byte. $FF was stored above as "nothing
        // seen yet", so a slot still holding it is the one to write into.
        // X is used for the test so the status byte stays in A.
        array_push(_list, ["ldx_abs", _status_addr, _id]);
        array_push(_list, ["cpx_imm", 0xFF,         _id]);
        array_push(_list, ["bne",     _l_skipkeep,  _id]);
        array_push(_list, ["sta_abs", _status_addr, _id]);
        array_push(_list, ["label",   _l_skipkeep,  _id]);
    }

    array_push(_list, ["jmp_abs", _l_drain,     _id]);

    // ---- ACCEPT AND WAIT FOR IDLE ----
    array_push(_list, ["label",   _l_done,      _id]);
    array_push(_list, ["lda_imm", 0x02,         _id]);   // DATA_ACC
    array_push(_list, ["sta_abs", UCI_CONTROL,  _id]);

    array_push(_list, ["label",   _l_final,     _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL,  _id]);
    array_push(_list, ["and_imm", 0x03,         _id]);
    array_push(_list, ["bne",     _l_final,     _id]);

    // ---- FILENAME ----
    // Jumped over, not fallen into. The Ultimate expects plain ASCII, which
    // is what these bytes are - do not run them through a PETSCII conversion.
    array_push(_list, ["jmp_abs", _l_absent,    _id]);
    array_push(_list, ["label",   _l_name,      _id]);
    for (var _ci = 1; _ci <= string_length(_filename); _ci++) {
        array_push(_list, ["byte", ord(string_char_at(_filename, _ci)), _id]);
    }
    array_push(_list, ["byte", 0x00, _id]);

    // Falls through to whatever node follows, on every path.
    array_push(_list, ["label", _l_absent, _id]);
}
