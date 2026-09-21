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
/// Register map, per the Ultimate Command Interface programming guide:
///   $DF1C  write: control      read: status
///   $DF1D  write: command data read: identification ($C9, or $49 during IRQ)
///   $DF1E  read:  response data
///   $DF1F  read:  status data
///
/// Status register ($DF1C read):
///   bit 0 CMD_BUSY   bit 1 DATA_ACC   bit 2 ABORT_P   bit 3 ERROR
///   bits 5-4 STATE   00 idle, 01 busy, 10 data-last, 11 data-more
///   bit 6 STAT_AV    bit 7 DATA_AV
/// STATE is masked with $30. (An earlier version of this node masked $03 -
/// CMD_BUSY and DATA_ACC - which only says the command has been *taken*, not
/// that it has *finished*, so it carried on while the load was still running.)
///
/// Control register ($DF1C write) is written with literal values only, never
/// read-modify-write: reading it returns the status register.
///
/// The exchange (target $04 control, command $08 LOAD REU, then the filename):
///   1. wait for STATE idle
///   2. write the command bytes to $DF1D, push with $01
///   3. poll while STATE is busy
///   4. STATE idle already -> the command finished with no data phase; done
///   5. drain $DF1E while DATA_AV, $DF1F while STAT_AV (before the accept -
///      DATA_ACC resets both queues)
///   6. write DATA_ACC ($02); data-more means another block follows, so go
///      back to 3; data-last returns to idle
/// LOAD REU answers with a 4-byte transfer count and an ASCII status string in
/// NN,TEXT form - "00,OK", "84,REU NOT ENABLED", "85,REU FILE CANNOT BE
/// OPENED" - so the first status byte is '0' ($30) on success and '8' ($38)
/// on the errors that matter here. That byte is kept rather than thrown away.

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
    var _l_accept   = _pfx + "accept";
    var _l_final    = _pfx + "final";
    var _l_skipkeep = _pfx + "skipkeep";

    var UCI_CONTROL  = 0xDF1C;
    var UCI_COMMAND  = 0xDF1D;
    var UCI_RESPONSE = 0xDF1E;
    var UCI_STATUS   = 0xDF1F;

    var ST_MASK  = 0x30;   // STATE, bits 5-4
    var ST_BUSY  = 0x10;
    var ST_MORE  = 0x30;

    // ---- PRESENCE ----
    // On hardware without the interface these registers are open bus, and the
    // idle wait below would spin forever. Identification reads $C9 normally
    // and $49 while an interrupt is being serviced.
    array_push(_list, ["lda_abs", UCI_COMMAND, _id]);
    array_push(_list, ["cmp_imm", 0xC9,        _id]);
    array_push(_list, ["beq",     _l_idle,     _id]);
    array_push(_list, ["cmp_imm", 0x49,        _id]);
    array_push(_list, ["bne",     _l_absent,   _id]);

    // ---- 1. WAIT FOR STATE IDLE ----
    array_push(_list, ["label",   _l_idle,     _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL, _id]);
    array_push(_list, ["and_imm", ST_MASK,     _id]);
    array_push(_list, ["bne",     _l_idle,     _id]);

    // ---- 2. COMMAND: target $04, command $08, then the filename, push ----
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

    // "Nothing seen yet" - only the first status byte of the exchange is kept.
    if (_status_addr != 0) {
        array_push(_list, ["lda_imm", 0xFF,         _id]);
        array_push(_list, ["sta_abs", _status_addr, _id]);
    }

    array_push(_list, ["lda_imm", 0x01,        _id]);   // PUSH_CMD
    array_push(_list, ["sta_abs", UCI_CONTROL, _id]);

    // ---- 3. POLL WHILE BUSY ----
    array_push(_list, ["label",   _l_wait,     _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL, _id]);
    array_push(_list, ["and_imm", ST_MASK,     _id]);
    array_push(_list, ["cmp_imm", ST_BUSY,     _id]);
    array_push(_list, ["beq",     _l_wait,     _id]);

    // ---- 4. BACK TO IDLE WITH NO DATA PHASE: nothing to read or accept ----
    array_push(_list, ["and_imm", ST_MASK,     _id]);
    array_push(_list, ["beq",     _l_absent,   _id]);

    // ---- 5. DRAIN: response bytes (bit 7), then status bytes (bit 6) ----
    array_push(_list, ["label",   _l_drain,     _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL,  _id]);
    array_push(_list, ["bpl",     _l_nodata,    _id]);
    array_push(_list, ["lda_abs", UCI_RESPONSE, _id]);
    array_push(_list, ["jmp_abs", _l_drain,     _id]);

    array_push(_list, ["label",   _l_nodata,    _id]);
    array_push(_list, ["and_imm", 0x40,         _id]);
    array_push(_list, ["beq",     _l_accept,    _id]);
    array_push(_list, ["lda_abs", UCI_STATUS,   _id]);
    if (_status_addr != 0) {
        // X is used for the test so the status byte stays in A.
        array_push(_list, ["ldx_abs", _status_addr, _id]);
        array_push(_list, ["cpx_imm", 0xFF,         _id]);
        array_push(_list, ["bne",     _l_skipkeep,  _id]);
        array_push(_list, ["sta_abs", _status_addr, _id]);
        array_push(_list, ["label",   _l_skipkeep,  _id]);
    }
    array_push(_list, ["jmp_abs", _l_drain,     _id]);

    // ---- 6. ACCEPT; data-more means another block follows ----
    array_push(_list, ["label",   _l_accept,    _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL,  _id]);
    array_push(_list, ["and_imm", ST_MASK,      _id]);
    array_push(_list, ["tax",     0,            _id]);   // state before the accept
    array_push(_list, ["lda_imm", 0x02,         _id]);   // DATA_ACC
    array_push(_list, ["sta_abs", UCI_CONTROL,  _id]);
    array_push(_list, ["cpx_imm", ST_MORE,      _id]);
    array_push(_list, ["beq",     _l_wait,      _id]);

    array_push(_list, ["label",   _l_final,     _id]);
    array_push(_list, ["lda_abs", UCI_CONTROL,  _id]);
    array_push(_list, ["and_imm", ST_MASK,      _id]);
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
