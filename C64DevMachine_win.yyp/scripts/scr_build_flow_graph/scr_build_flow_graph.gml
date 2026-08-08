/// @desc scr_build_flow_graph()
/// Runs an independent, side-effect-free compile+assemble pass (no PRG
/// write, no VICE launch, no LOAD_REU.reu write) purely to extract
/// JMP/JSR/BRANCH/IRQ-vector-write edges for the F-key flow overlay.
/// Safe to call repeatedly on toggle — never touches the real build
/// pipeline or its side effects.
/// Returns an array of {kind, src, tgt} structs, where kind is one of
/// "flow" (sequential spine order), "jmp", "jsr", "jsr_ret" (from the
/// actual RTS instruction — found by scanning forward, not just the JSR's
/// immediate jump target — back to the site that called it), "branch",
/// or "irq", and src/tgt are obj_c64_node instance ids.
function scr_build_flow_graph() {
    scr_c64_do_update_addresses();
    var _final_code = scr_compile_chain();
    var p = c64_new_program();

    // Same KERNAL/SID label injection the real build does, so a JSR to
    // sid_init/sid_play/sid_getin resolves to its real owning node
    // instead of being silently skipped as unresolved.
    ds_map_replace(p.labels, "sid_getin", 0xFFE4);
    var _sid_labels_set = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && !_sid_labels_set) {
            var _asset_name_l = string(instructions[0][1]);
            if (instance_exists(obj_asset_manager)) {
                var _am_l = obj_asset_manager;
                for (var _ali = 0; _ali < ds_list_size(_am_l.asset_list); _ali++) {
                    var _al = ds_list_find_value(_am_l.asset_list, _ali);
                    if (_al.type == "SID_MUSIC" && (_al.name == _asset_name_l || _asset_name_l == "")) {
                        var _si = variable_struct_exists(_al.meta, "sid_init_addr") ? _al.meta.sid_init_addr : _al.address;
                        var _sp = variable_struct_exists(_al.meta, "sid_play_addr") ? _al.meta.sid_play_addr : _al.address + 3;
                        ds_map_replace(p.labels, "sid_init", _si);
                        ds_map_replace(p.labels, "sid_play", _sp);
                        _sid_labels_set = true;
                        break;
                    }
                }
            }
        }
    }

    // Single pass: assemble_instruction() already registers labels as it
    // walks and defers fixup resolution to p.assemble() at the end, so
    // forward references resolve correctly without the real build's
    // separate label-pre-registration pass (that pass exists for other
    // reasons — final byte-length-dependent injection — that don't apply
    // to a read-only analysis pass like this one).
    for (var i = 0; i < array_length(_final_code); i++) {
        var _mnem = string_lower(_final_code[i][0]);
        if (_mnem == "_line_map_" || _mnem == "const" || _mnem == "") continue;
        var _val = (array_length(_final_code[i]) > 1) ? _final_code[i][1] : 0;
        p.assemble_instruction(_mnem, _val);
    }
    p.assemble();

    var _edges = [];
    var _blen  = array_length(p.bytes);

    // Resolve a byte offset (into p.bytes) to the node instance whose
    // compiled range contains it. O(n) per lookup — fine for a one-off
    // toggle-triggered build, not something running every frame.
    var _addr_to_node = function(_addr) {
        var _found = noone;
        with (obj_c64_node) {
            if (_addr >= pc_address && _addr < pc_address + max(1, total_node_size)) {
                _found = id;
                break;
            }
        }
        return _found;
    };

    // A LABEL node emits zero bytes of its own — it just marks a position,
    // so its total_node_size is 0 and its pc_address is often identical to
    // whatever real code immediately follows it. That makes address-range
    // lookup ambiguous: a LABEL node and the very next macro node can both
    // claim the same address, and which one wins is just iteration order.
    // Resolving by the fixup's own label NAME first (same pattern already
    // used elsewhere in scr_compile_chain.gml) sidesteps that entirely —
    // if a JMP targets "target_01", find the LABEL node actually named
    // "target_01" directly, rather than guessing from an address range.
    var _find_label_node = function(_label_name) {
        var _found = noone;
        with (obj_c64_node) {
            if (node_type == "LABEL" && string(instructions[0][1]) == _label_name) {
                _found = id;
                break;
            }
        }
        return _found;
    };

    for (var fi = 0; fi < array_length(p.fixups); fi++) {
        var f = p.fixups[fi];
        if (!ds_map_exists(p.labels, f.label)) continue;
        if (f.pos < 1 || f.pos - 1 >= _blen) continue;

        var _target_addr = p.labels[? f.label];
        var _src_addr     = p.base_address + p.header_size + f.pos - 1; // the opcode byte itself
        var _opcode       = p.bytes[f.pos - 1];

        var _kind = "";
        if (_opcode == 0x4C) _kind = "jmp";
        else if (_opcode == 0x20) _kind = "jsr";
        else if (_opcode == 0x10 || _opcode == 0x30 || _opcode == 0x50 || _opcode == 0x70
              || _opcode == 0x90 || _opcode == 0xB0 || _opcode == 0xD0 || _opcode == 0xF0) _kind = "branch";

        if (_kind != "") {
            var _src_node = _addr_to_node(_src_addr);
            var _tgt_node = _find_label_node(f.label);
            if (_tgt_node == noone) _tgt_node = _addr_to_node(_target_addr);
            if (_src_node != noone && _tgt_node != noone) {
                array_push(_edges, {kind: _kind, src: _src_node, tgt: _tgt_node});
                // JSR: also show the return trip. The label a JSR jumps to
                // is very often NOT where the RTS actually lives — a JSR
                // to an ADDRESS_LABEL node can fall through several more
                // nodes before hitting RTS — so scan forward through the
                // compiled bytes for the actual $60 opcode rather than
                // assuming the jump target's own node is the return point.
                // Capped scan: never runs past the largest subroutines
                // seen in this codebase, and never runs unbounded into
                // unrelated code/data that happens to contain a stray $60.
                if (_kind == "jsr") {
                    var _rts_node  = noone;
                    var _scan_from = _target_addr - p.base_address - p.header_size;
                    var _scan_cap  = 2000;
                    for (var _sb = max(0, _scan_from); _sb < min(_blen, _scan_from + _scan_cap); _sb++) {
                        if (p.bytes[_sb] == 0x60) {
                            _rts_node = _addr_to_node(p.base_address + p.header_size + _sb);
                            break;
                        }
                    }
                    if (_rts_node == noone) _rts_node = _tgt_node; // fallback: no RTS found nearby
                    array_push(_edges, {kind: "jsr_ret", src: _rts_node, tgt: _src_node});
                }
            }
        }

        // IRQ vector write: a "lo" fixup (label's low byte loaded via
        // LDA #<label) immediately followed by STA $0314 is the low byte
        // of an IRQ vector being pointed at a label. One edge per vector
        // (the lo write) is enough — the hi write targets the same pair.
        if (f.type == "lo" && f.pos + 3 < _blen
        &&  p.bytes[f.pos + 1] == 0x8D && p.bytes[f.pos + 2] == 0x14 && p.bytes[f.pos + 3] == 0x03) {
            var _irq_src = _addr_to_node(_src_addr);
            var _irq_tgt = _find_label_node(f.label);
            if (_irq_tgt == noone) _irq_tgt = _addr_to_node(_target_addr);
            if (_irq_src != noone && _irq_tgt != noone) {
                array_push(_edges, {kind: "irq", src: _irq_src, tgt: _irq_tgt});
            }
        }
    }

    // FLOW (white): straight execution order, derived from each node's
    // own compiled position — sorting by pc_address gives the same
    // sequence the program actually runs in when nothing jumps.
    //
    // A flow edge is only a genuine "fall-through, no JMP/RTS involved"
    // hop if the next node's address is EXACTLY where the previous one's
    // compiled bytes end. If there's a gap (or overlap) instead, that
    // means an ORG repositioned the compile position between them — real
    // control never "flows" across that boundary in the normal sense,
    // it's a distinct jump the compiler made, not the CPU. That's the
    // case that gets the org_jump flag (drawn as the S elbow), regardless
    // of which specific node types happen to sit on either side of it —
    // an ORG block's own code usually starts at its LABEL child, not the
    // ORG container node itself, so checking node types directly misses
    // exactly this case.
    var _flow_nodes = [];
    with (obj_c64_node) {
        if (total_node_size > 0) array_push(_flow_nodes, id);
    }
    array_sort(_flow_nodes, function(_a, _b) {
        return _a.pc_address - _b.pc_address;
    });
    for (var _fi = 0; _fi < array_length(_flow_nodes) - 1; _fi++) {
        var _fa = _flow_nodes[_fi];
        var _fb = _flow_nodes[_fi + 1];
        var _contiguous = (_fb.pc_address == _fa.pc_address + _fa.total_node_size);
        array_push(_edges, {kind: "flow", src: _fa, tgt: _fb, org_jump: !_contiguous});
    }

    return _edges;
}
