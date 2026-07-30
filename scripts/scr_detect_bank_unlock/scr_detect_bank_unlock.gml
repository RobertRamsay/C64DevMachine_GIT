/// @description Scans the resolved spine for $01 banking unlocks and sets
///              global.basic_unlocked / global.kernal_unlocked accordingly.
///              Detects the lda $01 / and #mask / sta $01 triplet across
///              separate nodes OR inside a single node's instruction list,
///              so the memory bar reflects real banking state however the
///              unlock was authored (combined node, split nodes, or MACRO_CODE).
function scr_detect_bank_unlock() {

    var _found_basic  = false;
    var _found_kernal = false;

    // Flatten the connected main spine into instruction order.
    // We need node order top-to-bottom so the triplet is read in sequence,
    // matching how it actually executes on the C64.
    var _spine = [];
    with (obj_c64_node) {
        if (is_connected && org_parent == noone) {
            array_push(_spine, id);
        }
    }
    array_sort(_spine, function(_a, _b) {
        if (_a.y < _b.y) return -1;
        if (_a.y > _b.y) return 1;
        return 0;
    });

    // State machine across the whole flattened stream:
    //   _armed        = we have just seen an "lda $01" (A holds the bank byte)
    //   _pending_mask = the AND mask seen since arming
    //   _pending_or   = the ORA value seen since arming (Shallan-style banking)
    var _armed          = false;
    var _pending_mask   = 0xFF;
    var _pending_or     = 0x00;
    var _armed_direct   = false;
    var _pending_direct = 0x00;

    for (var _ni = 0; _ni < array_length(_spine); _ni++) {
        var _node = _spine[_ni];
        if (!variable_instance_exists(_node, "instructions")) continue;

        // Title-based fast path (covers the dedicated unlock nodes incl. combined).
        if (_node.node_title == "BASIC RAM UNLOCK")          _found_basic  = true;
        if (_node.node_title == "KERNAL RAM UNLOCK")         _found_kernal = true;
        if (_node.node_title == "RAM UNLOCK (BASIC+KERNAL)") { _found_basic = true; _found_kernal = true; }

        // BANK_SWITCH node — reads the target $01 value directly from the node.
        // This node writes $01 with an immediate value (lda #V / sta $01), which
        // the read-modify-write state machine below does not catch. Decode the
        // config byte here so the memory bar reflects the new banking state.
        if (_node.node_type == "BANK_SWITCH") {
            var _bs_v01 = 0x37;
            if (array_length(_node.instructions) > 0 && array_length(_node.instructions[0]) > 1) {
                if (is_real(_node.instructions[0][1])) {
                    _bs_v01 = real(_node.instructions[0][1]);
                }
            }
            var _bs_loram = ((_bs_v01 & 0x01) != 0); // bit 0 = BASIC ROM in
            var _bs_hiram = ((_bs_v01 & 0x02) != 0); // bit 1 = KERNAL ROM in
            if (!_bs_hiram)                     _found_kernal = true; // KERNAL RAM
            if (!(_bs_loram && _bs_hiram))      _found_basic  = true; // BASIC RAM unless %11
        }

        // Build this node's instruction stream. MACRO_CODE keeps source text in
        // instructions[0][1]; parse it so typed unlocks are caught too.
        var _stream = [];
        if (_node.node_type == "MACRO_CODE") {
            if (array_length(_node.instructions) > 0 && array_length(_node.instructions[0]) > 1) {
                var _txt = string(_node.instructions[0][1]);
                if (_txt != "") _stream = scr_parse_asm_text(_txt);
            }
        } else {
            _stream = _node.instructions;
        }

        for (var _ii = 0; _ii < array_length(_stream); _ii++) {
            if (array_length(_stream[_ii]) < 1) continue;
            var _m = string_lower(string(_stream[_ii][0]));
            // Skip parser bookkeeping rows (line maps, labels, comments, pc, byte data).
            if (_m == "_line_map_" || _m == "label" || _m == "comment" || _m == "pc" || _m == "byte") continue;
            // Operand may be a real (node instructions) OR a hex/dec string like
            // "$01" / "#$FC" (MACRO_CODE parser output). Resolve both to a number.
            var _v = -1;
            if (array_length(_stream[_ii]) > 1) {
                var _raw_op = _stream[_ii][1];
                if (is_real(_raw_op)) {
                    _v = real(_raw_op);
                } else if (is_string(_raw_op)) {
                    var _ops = string(_raw_op);
                    _ops = string_replace_all(_ops, "#", "");
                    if (string_char_at(_ops, 1) == "$") {
                        _ops = string_delete(_ops, 1, 1);
                        _v   = hex_to_decimal(_ops);
                    } else {
                        var _dig = string_digits(_ops);
                        if (_dig != "") _v = real(_dig);
                    }
                }
            }
            // Fallback: if neither branch resolved it but a numeric-ish value
            // is present, coerce through string->real (covers typed values that
            // is_real() rejects, e.g. expression-evaluated operands).
            if (_v < 0 && array_length(_stream[_ii]) > 1) {
                var _coerce = string(_stream[_ii][1]);
                var _cdig   = string_digits(_coerce);
                if (_cdig != "" && string_pos("-", _coerce) == 0) {
                    _v = real(_cdig);
                }
            }

            
            if (_m == "lda_zp" && _v == 0x01) {
                _armed         = true;
                _armed_direct  = false;
                _pending_mask  = 0xFF; // fresh read, no mask applied yet
                _pending_or    = 0x00;
            }
            else if (_armed && _m == "and_imm" && _v >= 0) {
                _pending_mask = _v;
            }
            else if (_armed && _m == "ora_imm" && _v >= 0) {
                _pending_or = _v;
            }
            else if (_m == "lda_imm" && _v >= 0) {
                // Direct immediate write path: LDA #imm / STA $01, with no
                // preceding read of the current $01 value. The immediate IS
                // the new config byte outright, not a mask applied to it.
                _armed_direct   = true;
                _pending_direct = _v;
                _armed          = false;
                _pending_mask   = 0xFF;
                _pending_or     = 0x00;
            }
            else if (_armed && _m == "sta_zp" && _v == 0x01) {
                // Resolve the value actually written to $01: (read AND mask) OR or-bits.
                // Per the official $0001 table: HIRAM = bit 1 (KERNAL), and BASIC is
                // RAM unless the low two bits are %11 (bit0 AND bit1 both set).
                var _result    = (_pending_mask & 0x07) | (_pending_or & 0x07);
                var _hiram_set = ((_result & 0x02) != 0); // bit 1
                var _loram_set = ((_result & 0x01) != 0); // bit 0
                if (!_hiram_set)                 _found_kernal = true; // KERNAL RAM
                if (!(_loram_set && _hiram_set)) _found_basic  = true; // BASIC RAM unless %11
                _armed        = false;
                _pending_mask = 0xFF;
                _pending_or   = 0x00;
            }
            else if (_armed_direct && _m == "sta_zp" && _v == 0x01) {
                // Direct-write resolution: the immediate value loaded above IS
                // the config byte, so decode it the same way BANK_SWITCH does.
                var _dresult    = _pending_direct & 0x07;
                var _dhiram_set = ((_dresult & 0x02) != 0); // bit 1
                var _dloram_set = ((_dresult & 0x01) != 0); // bit 0
                if (!_dhiram_set)                   _found_kernal = true; // KERNAL RAM
                if (!(_dloram_set && _dhiram_set))  _found_basic  = true; // BASIC RAM unless %11
                _armed_direct   = false;
                _pending_direct = 0x00;
            }
            else if (_m == "lda_abs" || _m == "lda_zp") {
                // A reloaded from somewhere that isn't our $01 read -> disarm.
                // (e.g. the buggy "lda #$00" case: we never armed, so no false unlock.)
                if (!(_m == "lda_zp" && _v == 0x01)) {
                    _armed         = false;
                    _armed_direct  = false;
                    _pending_mask  = 0xFF;
                }
            }
        }
        // A real spine never carries the half-state across an sta to a far node
        // in practice, but reset between nodes only if the lda/sta straddle is
        // unlikely. We intentionally DO let it carry so split nodes still work.
    }


    global.basic_unlocked  = _found_basic;
    global.kernal_unlocked = _found_kernal;
}