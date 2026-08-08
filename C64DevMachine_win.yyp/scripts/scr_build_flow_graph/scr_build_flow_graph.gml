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

    // Track exactly which real node authored each emitted byte, using the
    // node id every _final_code entry already carries (_final_code[i][2])
    // and this assembler's own PC before/after each instruction. This is
    // ground truth for this compile pass — unlike inferring ownership from
    // each node's total_node_size, which only covers its inline position
    // on the spine and misses code a macro emits out-of-line. MACRO_IRQ is
    // the concrete case: it emits "jsr init / jmp skip" inline, then its
    // actual handler body (including any user "JSR: <label>" call) further
    // down, past the jmp. That handler code sits well outside the node's
    // own total_node_size range, so a range-only lookup silently drops the
    // edge for that JSR — it's real, just not attributed back correctly.
    var _owner_ranges = [];
    for (var i = 0; i < array_length(_final_code); i++) {
        var _mnem = string_lower(_final_code[i][0]);
        if (_mnem == "_line_map_" || _mnem == "const" || _mnem == "") continue;
        var _val   = (array_length(_final_code[i]) > 1) ? _final_code[i][1] : 0;
        var _owner = (array_length(_final_code[i]) > 2) ? _final_code[i][2] : noone;
        var _addr_before = p.current_pc();
        p.assemble_instruction(_mnem, _val);
        var _addr_after = p.current_pc();
        if (_addr_after > _addr_before && instance_exists(_owner)) {
            array_push(_owner_ranges, {start: _addr_before, stop: _addr_after, node: _owner});
        }
    }
    p.assemble();

    var _edges = [];
    var _blen  = array_length(p.bytes);

    // Resolve an address to the node that actually emitted the byte there.
    // Checks the precise per-instruction ownership map first (handles
    // out-of-line macro bodies correctly), falling back to the coarser
    // pc_address/total_node_size range check only if nothing in this
    // compile pass claims that address. O(n) per lookup — fine for a
    // one-off toggle-triggered build, not something running every frame.
    // _owner_ranges is passed in explicitly rather than closed over: GML
    // function literals here only see their own parameters and instance
    // variables on self, not the enclosing scope's locals — referencing
    // _owner_ranges directly crashes at runtime as an unset instance var
    // read on whichever object happened to call this script.
    var _addr_to_node = function(_addr, _ranges) {
        for (var _ri = 0; _ri < array_length(_ranges); _ri++) {
            var _r = _ranges[_ri];
            if (_addr >= _r.start && _addr < _r.stop) return _r.node;
        }
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

        // Real jmp_abs/jsr/branch instructions always create an "abs" or
        // "rel" fixup — never "lo"/"hi" (those are lda_lab_lo/byte_lab_lo
        // style: immediate-load patches or raw data-table bytes). Without
        // this guard, a "lo"/"hi" fixup sitting right after an arbitrary
        // data byte that happens to equal $20/$4C/a branch opcode gets
        // misread as a real jmp/jsr/branch — exactly what a dispatch
        // table's densely-packed lo/hi byte pairs make fairly likely.
        var _kind = "";
        if (f.type == "abs" || f.type == "rel") {
            if (_opcode == 0x4C) _kind = "jmp";
            else if (_opcode == 0x20) _kind = "jsr";
            else if (_opcode == 0x10 || _opcode == 0x30 || _opcode == 0x50 || _opcode == 0x70
                  || _opcode == 0x90 || _opcode == 0xB0 || _opcode == 0xD0 || _opcode == 0xF0) _kind = "branch";
        }

        if (_kind != "") {
            var _src_node = _addr_to_node(_src_addr, _owner_ranges);
            var _tgt_node = _find_label_node(f.label);
            // JMP/BRANCH still fall back to address-range guessing when
            // there's no matching LABEL node — that's fine, those mostly
            // land on a real node either way. JSR does NOT: dozens of
            // internal jsr calls throughout scr_compile_chain (vbmp_plot,
            // math_mul16, adv_ptr, shcolsub, and similar shared helper
            // subroutines) target labels the user never wrapped in a
            // LABEL node — they're pure implementation detail, not
            // something placed in the graph to call. Falling back for
            // those just lands the line on whatever node happens to own
            // that address, which reads as a random, unexplained
            // connection. Requiring a real LABEL node match keeps JSR
            // edges limited to calls that are genuinely visible and
            // callable in the node graph.
            if (_tgt_node == noone && _kind != "jsr") _tgt_node = _addr_to_node(_target_addr, _owner_ranges);
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
                            var _test_node = _addr_to_node(p.base_address + p.header_size + _sb, _owner_ranges);
                            // Only a genuine standalone RTS node counts — an
                            // explicit RTS instruction is exactly 1 byte on
                            // its own node. Deliberately NOT falling back to
                            // "any node whose instructions happen to contain
                            // an RTS somewhere" — that matches RTS bytes
                            // that are just part of some other macro's own
                            // internal multi-instruction body, not a return
                            // point the user placed or can see as a call
                            // target, which is exactly the source of the
                            // stray/unexpected return-trip lines.
                            if (_test_node != noone && _test_node.total_node_size == 1) {
                                _rts_node = _test_node;
                                break;
                            }
                        }
                    }
                    if (_rts_node == noone) _rts_node = _tgt_node; // fallback: no standalone RTS node found nearby
                    array_push(_edges, {kind: "jsr_ret", src: _rts_node, tgt: _src_node});
                }
            }
        }

        // IRQ vector write: a "lo" fixup (label's low byte loaded via
        // LDA #<label) immediately followed by STA to either IRQ vector is
        // the low byte of an IRQ vector being pointed at a label. Covers
        // both vector modes MACRO_IRQ/MACRO_IRQ_HANDLER can write:
        // $0314 (KERNAL-chained) and $FFFE (Direct hardware vector, used
        // when the KERNAL is banked out). One edge per vector (the lo
        // write) is enough — the hi write targets the same pair.
        var _matched_irq_vector = false;
        if (f.type == "lo" && f.pos + 3 < _blen
        &&  p.bytes[f.pos + 1] == 0x8D
        &&  ( (p.bytes[f.pos + 2] == 0x14 && p.bytes[f.pos + 3] == 0x03)   // $0314
           || (p.bytes[f.pos + 2] == 0xFE && p.bytes[f.pos + 3] == 0xFF) )) { // $FFFE
            var _irq_src = _addr_to_node(_src_addr, _owner_ranges);
            var _irq_tgt = _find_label_node(f.label);
            if (_irq_tgt == noone) _irq_tgt = _addr_to_node(_target_addr, _owner_ranges);
            if (_irq_src != noone && _irq_tgt != noone) {
                array_push(_edges, {kind: "irq", src: _irq_src, tgt: _irq_tgt});
            }
            _matched_irq_vector = true;
        }

        // MACRO_IRQ_HANDLER dispatch table: each user "JSR: <label>" call
        // is stored purely as data — a byte_lab_lo/byte_lab_hi pair in a
        // per-slot jump table — with the actual JSR's operand patched from
        // that table by self-modifying code at runtime. The JSR opcode
        // itself is always compiled with static $00 $00 operand bytes and
        // carries no fixup, so the opcode-scan above can never see these
        // calls. Any remaining "lo" fixup whose bytes were emitted by a
        // MACRO_IRQ_HANDLER node (and isn't the vector write just above)
        // is one of these dispatch entries — surface it as a "jsr" edge.
        // The line should come from whichever individual MACRO_IRQ node
        // actually configured this call, not the shared handler node —
        // resolve that by re-deriving the exact same fallback-label rule
        // scr_compile_chain used when it built this table slot (real
        // call_label field if set, else "irq<id>_handler"), falling back
        // to the handler node only if no MACRO_IRQ node matches. Dedup:
        // 16 table slots always exist and unused ones mirror the last
        // real target, so the same (src, tgt) pair shows up many times
        // over — only the first counts.
        if (!_matched_irq_vector && f.type == "lo") {
            var _table_addr  = p.base_address + p.header_size + f.pos;
            var _disp_owner  = _addr_to_node(_table_addr, _owner_ranges);
            if (_disp_owner != noone && instance_exists(_disp_owner) && _disp_owner.node_type == "MACRO_IRQ_HANDLER") {
                var _disp_src = noone;
                with (obj_c64_node) {
                    if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone) {
                        var _cl = (array_length(instructions[0]) > 5 && string(instructions[0][5]) != "")
                                ? string(instructions[0][5]) : ("irq" + string(real(id)) + "_handler");
                        if (_cl == f.label) { _disp_src = id; break; }
                    }
                }
                if (_disp_src == noone) _disp_src = _disp_owner; // fallback: no matching MACRO_IRQ node found
                var _disp_tgt = _find_label_node(f.label);
                if (_disp_tgt == noone) _disp_tgt = _addr_to_node(_target_addr, _owner_ranges);
                if (_disp_tgt != noone) {
                    var _dup = false;
                    for (var _ei = 0; _ei < array_length(_edges); _ei++) {
                        var _ee = _edges[_ei];
                        if (_ee.kind == "jsr" && _ee.src == _disp_src && _ee.tgt == _disp_tgt) { _dup = true; break; }
                    }
                    if (!_dup) array_push(_edges, {kind: "jsr", src: _disp_src, tgt: _disp_tgt});
                }
            }
        }
    }

    // FLOW (white): straight execution order, derived from each node's
    // own compiled position — sorting by pc_address gives the same
    // sequence the program actually runs in when nothing jumps.
    //
    // org_jump flags a flow edge as an ORG-boundary hop rather than
    // ordinary fall-through, by either of two signals:
    //   1. A genuine address gap/overlap — the next node's address isn't
    //      exactly where the previous one's bytes end. This catches the
    //      common case where an ORG repositions the compile PC and its
    //      own container is zero-size (like a LABEL child), so the flow
    //      edge lands on the surrounding real nodes instead.
    //   2. Either node is literally an ORG or INIT node. This catches the
    //      case a pure gap check misses: an ORG with its own inline code
    //      (so it has nonzero size and shows up directly in this list)
    //      that happens to sit naturally contiguous with what precedes
    //      it — still a distinct addressing context worth calling out,
    //      even though there's no numeric gap to detect.
    // ORG and INIT nodes are included unconditionally, even at size 0 —
    // an ORG's own inline content (its cosmetic "NOP" preview) is never
    // actually tagged back to its own total_node_size during compile
    // (Pass 2 only emits a zero-byte "org" meta-instruction for the ORG
    // node itself, then walks its CHILD's spine separately), so without
    // this the ORG node type check below could never fire — the node
    // would already be filtered out of this list before that check ever
    // runs against it.
    var _flow_nodes = [];
    with (obj_c64_node) {
        // VARIABLES is a fixed anchor ORG parked at $C000 by obj_workspace_manager
        // at startup — it's never walked by the real spine, so its address is not
        // representative of program order. Sweeping it in here (it matches
        // node_type == "ORG" below like any real ORG would) drags a stale address
        // into the sort and produces a bogus edge with the wrong direction.
        if (node_title == "VARIABLES") continue;
        if (total_node_size > 0 || node_type == "ORG" || node_type == "INIT") array_push(_flow_nodes, id);
    }
    array_sort(_flow_nodes, function(_a, _b) {
        return _a.pc_address - _b.pc_address;
    });
    for (var _fi = 0; _fi < array_length(_flow_nodes) - 1; _fi++) {
        var _fa = _flow_nodes[_fi];
        var _fb = _flow_nodes[_fi + 1];
        var _contiguous = (_fb.pc_address == _fa.pc_address + _fa.total_node_size);
        var _org_edge = (_fa.node_type == "ORG") || (_fb.node_type == "ORG")
                      || (_fa.node_type == "INIT") || (_fb.node_type == "INIT");
        array_push(_edges, {kind: "flow", src: _fa, tgt: _fb, org_jump: (!_contiguous || _org_edge)});
    }

    return _edges;
}
