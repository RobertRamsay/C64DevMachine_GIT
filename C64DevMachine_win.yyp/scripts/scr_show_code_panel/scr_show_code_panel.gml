/// @desc SHOW CODE PANEL
///
/// A floating, draggable, resizable, scrollable listing of the whole compiled
/// program, drawn in GUI space to the LEFT of the global shortcuts column.
///
/// Every MACRO_ node folds into a single "MACRO_NAME [+]" row that expands to
/// its real instructions and collapses again. Non-macro output (raw opcode
/// nodes, user ADDRESS LABEL nodes, ORG, inline byte data) always lists inline.
/// Compiler-internal labels (the L_LEXIT_ref_instance_… family every macro
/// spawns for its own branches) are resolved but never listed — they are noise
/// in a listing and they used to chop one macro into a dozen fragments.
///
/// Byte tables fold too: a run of 4+ plain bytes becomes one collapsible
/// "[+] NAME $4000-$5F3F  8000B" row — but only with MISC on.
///
/// MISC (header button, OFF by default) governs everything that is not code you
/// wrote: byte tables, the <LABEL / >LABEL pointer bytes that index them, and a
/// macro's own scaffolding labels. Off, the listing is just the instruction
/// stream, your ADDRESS LABELs and the ORG markers.
///
/// Two display modes, picked with the two-segment switch in the header (the
/// active one is filled, so there is nothing to infer from a single label):
///   0 = VICE   .0810  F0 05     BEQ $0817
///   1 = ASM    .081E            BEQ WAIT_EDGE_100148
///
/// VICE mode resolves every label operand to a real address using a label map
/// built in the same pass as the listing, and computes true relative offsets
/// for branches — so what the panel shows is what the VICE monitor will show.
/// It lists NO label rows at all: a monitor never prints one, and every operand
/// is already an address.
///
/// ASM mode instead keeps the names AND declares each referenced label on its
/// own line, hanging left of the code it names, so a branch never points at a
/// label the listing never shows. Labels nothing refers to stay hidden.
///
/// Resize: drag the LEFT or RIGHT edge for width, the BOTTOM edge for row
/// count (5..60 lines). The scrollbar thumb drags, and a click on the track
/// pages towards the pointer.
///
/// Hovering a node out on the workspace highlights that node's code here and
/// scrolls to it if it is off screen — a collapsed macro highlights its [+] row.
/// Works for macros, ordinary opcode nodes and ADDRESS LABEL nodes alike, though
/// only macros are tagged by the compile chain (see scr_show_code_attribute).
/// While the pointer is over the panel, nothing underneath it reacts: the hit
/// test runs in Begin Step (scr_show_code_hit), so it is authoritative for the
/// Step events of the same frame rather than a frame behind.
///
/// The panel NEVER runs its own compile pass. scr_c64_do_update_addresses()
/// already produces a full sizing-pass compile every time the graph changes,
/// and hands that array straight to scr_show_code_build(). The fold pass
/// (flat list -> visible rows) is the only thing an expand/collapse click
/// re-runs, and the draw event only ever walks the visible rows.
///
/// Functions in this file:
///   scr_show_code_norm(_mnem)           mnemonic -> obj_opCodeManager key
///   scr_show_code_num(_val)              any numeric type -> plain real
///   scr_show_code_wrap16(_val)           wrap to 0..65535 without bitwise ops
///   scr_show_code_lo(_val)               low byte  (two's complement safe)
///   scr_show_code_hi(_val)               high byte
///   scr_show_code_hex(_val, _digits)     zero-padded uppercase hex
///   scr_show_code_is_branch(_mnem)       relative-addressing test
///   scr_show_code_row_hidden(...)        row visibility for this mode + MISC
///   scr_show_code_is_open(_key)          is this group expanded?
///   scr_show_code_toggle(_key)           expand / collapse one group
///   scr_show_code_bytes(_ln)             "F0 05" style raw byte column
///   scr_show_code_text(_ln, _mode)       "BEQ $0817" style disassembly column
///   scr_show_code_hit()                  Begin Step: pointer ownership + hover
///   scr_show_code_build(_compiled)       compiled array -> showcode_flat
///   scr_show_code_attribute()            owning node for untagged rows
///   scr_show_code_emit(...)              one flat entry -> display rows
///   scr_show_code_fold()                 showcode_flat -> showcode_lines
///   scr_show_code_draw()                 draw + all panel input
///   scr_show_code_save_ini()             persist geometry / open state / mode

// Panel metrics. Shared so the Begin Step hit test and the Draw layout can
// never drift apart — the hit test is what stops clicks reaching the nodes
// underneath, so it has to agree with what is actually on screen.
#macro SHOWCODE_HDR_H 24
#macro SHOWCODE_ROW_H 15
#macro SHOWCODE_PAD_T 6
#macro SHOWCODE_PAD_B 12
#macro SHOWCODE_GRAB  5
#macro SHOWCODE_MAX_ROWS 60

// =====================================================================
// Normalise a compile-chain mnemonic to an obj_opCodeManager key.
// =====================================================================
function scr_show_code_norm(_mnem) {
    var _n = string_trim(string_lower(string(_mnem)));

    _n = string_replace_all(_n, "_abs_x",   "_abx");
    _n = string_replace_all(_n, "_abs_y",   "_aby");
    _n = string_replace_all(_n, "_zp_x",    "_zpx");
    _n = string_replace_all(_n, "_zp_y",    "_zpy");
    _n = string_replace_all(_n, "_ind_x",   "_izx");
    _n = string_replace_all(_n, "_ind_y",   "_izy");
    _n = string_replace_all(_n, "_imm_rep", "_imm");

    // The _lab family is the compile chain's "operand is still a label"
    // spelling of an ordinary opcode. Rewrite it to the real addressing mode
    // so size and opcode-byte lookups land: lda_lab_lo -> lda_imm,
    // stx_lab -> stx_abs, jsr_lab -> jsr.
    if (string_pos("_lab_lo", _n) > 0 || string_pos("_lab_hi", _n) > 0) {
        _n = string_copy(_n, 1, 3) + "_imm";
    } else if (string_pos("_lab", _n) > 0) {
        _n = string_copy(_n, 1, 3) + "_abs";
    }

    // The _rep family (lda_abs_rep, sta_zp_rep, tax_rep, …) is a pure alias —
    // c64_new_program emits the identical opcode for each. Without this,
    // fifteen mnemonics that scr_define_opcodes sizes correctly still had no
    // entry in scr_opcode_hex and printed "??" for their opcode byte.
    if (string_length(_n) > 4) {
        if (string_copy(_n, string_length(_n) - 3, 4) == "_rep") {
            _n = string_copy(_n, 1, string_length(_n) - 4);
        }
    }

    if (_n == "jmp")     { _n = "jmp_abs"; }
    if (_n == "jsr_abs") { _n = "jsr";     }

    return _n;
}

// =====================================================================
// Numeric coercion for everything below.
//
// GML's bitwise operators return int64, and is_real() is FALSE for an
// int64. That is what made every operand byte in this listing print as 00:
// the value arrived here as `something & $FF`, is_real() rejected it, and
// it was zeroed. The address column survived only because a PC is a plain
// real when it is passed in. So: nothing in this file masks with & or >>
// any more — the lo/hi helpers below use arithmetic — and the guard accepts
// the int types as well, since the compile chain itself emits hundreds of
// operands built from bitwise expressions.
// =====================================================================
function scr_show_code_num(_val) {
    if (is_real(_val))  { return floor(_val); }
    if (is_int64(_val)) { return floor(real(_val)); }
    if (is_int32(_val)) { return floor(real(_val)); }
    return 0;
}

function scr_show_code_wrap16(_val) {
    var _v = scr_show_code_num(_val) mod 65536;
    if (_v < 0) {
        _v += 65536;
    }
    return _v;
}

// Low byte. Handles negative input (branch offsets) as two's complement.
function scr_show_code_lo(_val) {
    return scr_show_code_wrap16(_val) mod 256;
}

// High byte.
function scr_show_code_hi(_val) {
    return floor(scr_show_code_wrap16(_val) / 256);
}

// =====================================================================
function scr_show_code_hex(_val, _digits) {
    var _h = string_upper(decimal_to_hex(scr_show_code_wrap16(_val)));
    while (string_length(_h) < _digits) {
        _h = "0" + _h;
    }
    return _h;
}

// =====================================================================
function scr_show_code_is_branch(_mnem) {
    var _m = string_lower(string(_mnem));
    if (_m == "bne") { return true; }
    if (_m == "beq") { return true; }
    if (_m == "bcc") { return true; }
    if (_m == "bcs") { return true; }
    if (_m == "bpl") { return true; }
    if (_m == "bmi") { return true; }
    if (_m == "bvc") { return true; }
    if (_m == "bvs") { return true; }
    return false;
}

// =====================================================================
// Expanded-macro bookkeeping. showcode_expanded is a plain array of node
// keys initialised in the Create event, so there is no struct to test for
// existence and no lazy allocation anywhere.
// =====================================================================
function scr_show_code_is_open(_key) {
    var _list = obj_workspace_manager.showcode_expanded;
    for (var _i = 0; _i < array_length(_list); _i++) {
        if (_list[_i] == _key) {
            return true;
        }
    }
    return false;
}

function scr_show_code_toggle(_key) {
    with (obj_workspace_manager) {
        var _hit = -1;
        for (var _i = 0; _i < array_length(showcode_expanded); _i++) {
            if (showcode_expanded[_i] == _key) {
                _hit = _i;
                break;
            }
        }
        if (_hit >= 0) {
            array_delete(showcode_expanded, _hit, 1);
        } else {
            array_push(showcode_expanded, _key);
        }
        showcode_dirty = true;
    }
}

// =====================================================================
// Raw byte column, VICE monitor style. Label operands are resolved during
// the build pass, so a branch prints its real relative offset here exactly
// as the monitor will show it. Anything genuinely unresolved stays ??.
// =====================================================================
function scr_show_code_bytes(_ln) {
    if (_ln.kind == "byte") {
        if (_ln.lbl != "" && _ln.hasres) {
            if (string_pos("_lab_hi", _ln.raw) > 0) {
                return scr_show_code_hex(scr_show_code_hi(_ln.res), 2);
            }
            return scr_show_code_hex(scr_show_code_lo(_ln.res), 2);
        }
        if (_ln.lbl != "") {
            return "??";
        }
        return scr_show_code_hex(scr_show_code_lo(_ln.val), 2);
    }

    var _op = scr_opcode_hex(_ln.mnem);

    if (_ln.sz <= 1) {
        return _op;
    }

    if (_ln.lbl != "") {
        if (!_ln.hasres) {
            if (_ln.sz == 2) {
                return _op + " ??";
            }
            return _op + " ?? ??";
        }

        // Relative branch: the operand byte is target - (pc + 2), the same
        // arithmetic c64_new_program's "rel" fixup performs. scr_show_code_lo
        // wraps a negative offset to two's complement for us.
        if (scr_show_code_is_branch(_ln.mnem)) {
            return _op + " " + scr_show_code_hex(scr_show_code_lo(_ln.res - (_ln.pc + 2)), 2);
        }

        if (_ln.sz == 2) {
            if (string_pos("_lab_hi", _ln.raw) > 0) {
                return _op + " " + scr_show_code_hex(scr_show_code_hi(_ln.res), 2);
            }
            return _op + " " + scr_show_code_hex(scr_show_code_lo(_ln.res), 2);
        }

        return _op + " " + scr_show_code_hex(scr_show_code_lo(_ln.res), 2)
                   + " " + scr_show_code_hex(scr_show_code_hi(_ln.res), 2);
    }

    if (_ln.sz == 2) {
        return _op + " " + scr_show_code_hex(scr_show_code_lo(_ln.val), 2);
    }
    return _op + " " + scr_show_code_hex(scr_show_code_lo(_ln.val), 2)
               + " " + scr_show_code_hex(scr_show_code_hi(_ln.val), 2);
}

// =====================================================================
// Disassembly column. VICE mode (0) prints resolved addresses; ASM mode (1)
// keeps the label name, which is the more readable of the two when you are
// reading the listing rather than matching it against a monitor dump.
// =====================================================================
function scr_show_code_text(_ln, _mode) {
    if (_ln.kind == "org") {
        return "* = $" + scr_show_code_hex(_ln.pc, 4);
    }

    if (_ln.kind == "label") {
        var _lt = _ln.lbl;
        if (_lt == "") {
            _lt = "(anon)";
        }
        return string_upper(_lt) + ":";
    }

    if (_ln.kind == "byte") {
        if (_ln.lbl != "" && _ln.hasres && _mode == 0) {
            if (string_pos("_lab_hi", _ln.raw) > 0) {
                return ".BYTE $" + scr_show_code_hex(scr_show_code_hi(_ln.res), 2);
            }
            return ".BYTE $" + scr_show_code_hex(scr_show_code_lo(_ln.res), 2);
        }
        if (_ln.lbl != "") {
            if (string_pos("_lab_hi", _ln.raw) > 0) {
                return ".BYTE >" + string_upper(_ln.lbl);
            }
            return ".BYTE <" + string_upper(_ln.lbl);
        }
        return ".BYTE $" + scr_show_code_hex(scr_show_code_lo(_ln.val), 2);
    }

    var _raw = _ln.raw;
    var _op3 = string_upper(string_copy(_raw, 1, 3));

    if (_ln.lbl != "") {
        // VICE mode: show what the monitor shows — the resolved address.
        if (_mode == 0 && _ln.hasres) {
            if (string_pos("_lab_lo", _raw) > 0) {
                return _op3 + " #$" + scr_show_code_hex(scr_show_code_lo(_ln.res), 2);
            }
            if (string_pos("_lab_hi", _raw) > 0) {
                return _op3 + " #$" + scr_show_code_hex(scr_show_code_hi(_ln.res), 2);
            }
            return _op3 + " $" + scr_show_code_hex(_ln.res, 4);
        }

        if (string_pos("_lab_lo", _raw) > 0) {
            return _op3 + " #<" + string_upper(_ln.lbl);
        }
        if (string_pos("_lab_hi", _raw) > 0) {
            return _op3 + " #>" + string_upper(_ln.lbl);
        }
        return _op3 + " " + string_upper(_ln.lbl);
    }

    return scr_format_asm(_raw, _ln.val);
}

// =====================================================================
// BUILD — turn one compile-chain result into the flat line list.
// Called from scr_c64_do_update_addresses() with the sizing-pass array it
// already has in hand, so this costs a walk and nothing more.
// =====================================================================
function scr_show_code_build(_compiled) {
    if (!instance_exists(obj_workspace_manager)) { exit; }

    with (obj_workspace_manager) {
        // Shut means shut. This walks the whole compile stream, allocates a
        // struct per row and now sorts the result into address order, and it
        // was running on every address update whether or not anything was going
        // to look at it. The toggle raises global.addresses_dirty so the very
        // next frame after opening rebuilds it.
        if (!showcode_open) { exit; }
        var _flat    = [];
        var _pc      = global.start_pc;
        var _pcstack = [];   // mirrors c64_new_program's org(-2)/org(-3) stack
        var _lastkey  = "";  // last macro key seen, for crediting bracketed runs
        var _lastname = "";
        var _lastinst = "";
        var _brkkey   = "";  // …captured when a save/restore bracket opened
        var _brkname  = "";
        var _brkinst  = "";
        var _brkstack = [];  // one entry per open bracket, so -3 restores the
                             // context the enclosing bracket had rather than
                             // leaving the innermost one latched forever
        var _run     = -1;   // index of the byte run currently being extended

        // Every label's address, internal ones included — this is what makes
        // VICE mode able to resolve a branch target.
        var _lblmap = ds_map_create();

        // Names the user actually authored on ADDRESS LABEL nodes. Only these
        // get a row in the listing; every other label the compile chain spawns
        // is scaffolding and stays hidden.
        var _userlbl = ds_map_create();
        with (obj_c64_node) {
            if (node_type != "LABEL") { continue; }
            if (array_length(instructions) < 1)    { continue; }
            if (array_length(instructions[0]) < 2) { continue; }
            var _un = string_replace_all(string(instructions[0][1]), " ", "_");
            ds_map_set(_userlbl, _un, 1);
        }

        for (var _i = 0; _i < array_length(_compiled); _i++) {
            var _e = _compiled[_i];
            if (array_length(_e) < 1) { continue; }

            var _m = string_lower(string(_e[0]));
            if (_m == "_node_ref_" || _m == "const" || _m == "_line_map_" || _m == "comment" || _m == "") {
                continue;
            }

            // ORG relocates the program counter mid-stream — follow it so
            // every address below stays honest.
            //
            // -2 and -3 are NOT addresses: they are the compile chain's
            // save/restore PC markers, matching c64_new_program's org().
            // -2 pushes the current PC, -3 pops it back. Printing them as
            // addresses is what produced the phantom "* = $FFFE" rows
            // (-2 masked to 16 bits). They are bookkeeping, so they get a
            // stack push/pop here and no row in the listing.
            if (_m == "org") {
                var _o = _e[1];
                if (is_string(_o)) {
                    _o = real(_o);
                }

                if (_o == -2) {
                    array_push(_pcstack, _pc);
                    // A save/restore bracket is an EXCURSION inside one node's
                    // emission — a code block's .pcsave/.pc/.pcrestore, or a
                    // macro parking a table off-spine. Remember whose emission
                    // it interrupted so the rows inside can be credited to it.
                    _brkkey  = _lastkey;
                    _brkname = _lastname;
                    _brkinst = _lastinst;
                    array_push(_brkstack, { key: _brkkey, name: _brkname, inst: _brkinst });
                    _run = -1;
                    continue;
                }

                if (_o == -3) {
                    if (array_length(_pcstack) > 0) {
                        _pc = array_pop(_pcstack);
                    }
                    // Leave the bracket's context behind with the bracket. It
                    // used to stay latched, so any later stream position that
                    // still looked bracketed kept crediting a macro that had
                    // finished emitting long before.
                    if (array_length(_brkstack) > 0) {
                        array_pop(_brkstack);
                    }
                    _brkkey  = "";
                    _brkname = "";
                    _brkinst = "";
                    if (array_length(_brkstack) > 0) {
                        var _bt  = _brkstack[array_length(_brkstack) - 1];
                        _brkkey  = _bt.key;
                        _brkname = _bt.name;
                        _brkinst = _bt.inst;
                    }
                    _run = -1;
                    continue;
                }

                _pc  = _o;
                _run = -1;

                // Untagged by the compile chain, so without this the ORG row
                // has no key and the fold pass chops the node it sits inside
                // into two separate [+] groups — which is exactly what a
                // converted code block with a .pc data tail was doing.
                var _okey  = "";
                var _oname = "";
                var _oinst = "";
                if (array_length(_pcstack) > 0) {
                    _okey  = _brkkey;
                    _oname = _brkname;
                    _oinst = _brkinst;
                }

                // `top` separates a real block boundary from a macro parking a table
                // off-spine inside a save/restore bracket. Only the former may
                // cut the listing into re-orderable segments — the bracketed
                // ones are the "inline stuff" and must stay exactly where they
                // are, inside the run that owns them.
                array_push(_flat, { kind:"org", key:_okey, name:_oname, owner:"", inst:_oinst, pc:_pc, raw:_m, mnem:_m, val:0, lbl:"", sz:0, res:0, hasres:false, count:0, vals:[], dkey:"", internal:false, used:false, used_code:false, top:(array_length(_pcstack) == 0) });
                continue;
            }

            // [1] is the operand. A non-numeric operand is an unresolved label.
            var _v = 0;
            if (array_length(_e) > 1) {
                _v = _e[1];
            }
            var _lbl = "";
            if (is_string(_v) && _v != "" && _v != "0") {
                _lbl = _v;
                _v   = 0;
            }

            // Over three hundred operands in the compile chain are built from
            // bitwise expressions (`_addr & 0xFF`, `(_v >> 8) & 0xFF`), so they
            // arrive as int64. scr_format_asm() gates on is_real() and would
            // render those as a bare decimal or as $0000. Flatten to a plain
            // real once, here, and every consumer downstream is safe.
            _v = scr_show_code_num(_v);

            // [2] is the owning node instance, or — on the branch/jump forms
            // that carry their target there instead — a string label.
            var _key   = "";
            var _name  = "";
            var _owner = "";
            var _inst  = "";
            var _tstr  = "";
            if (array_length(_e) > 2) {
                var _tag = _e[2];
                if (is_string(_tag)) {
                    _tstr = _tag;
                } else if (_tag != noone) {
                    if (instance_exists(_tag)) {
                        // _inst / _owner are set for every node type; _key only
                        // for macros, since only macros fold as macro groups.
                        // _inst is what the workspace hover highlight matches on.
                        _inst  = string(_tag);
                        _owner = string(_tag.node_type);
                        if (string_pos("MACRO_", _owner) == 1) {
                            _key  = string(_tag);
                            _name = _owner;
                        }
                    }
                }
            }

            // Remember the last real owner, so a save/restore bracket can credit
            // what happens inside it — and while a bracket is open, let untagged
            // entries inherit it. The compile chain tags relocated bytes `noone`
            // on purpose, so without this a code block's .pc data tail has no
            // key and the fold pass splits the block into two [+] groups.
            // Any row the compile chain TAGGED re-anchors this, macro or not.
            // Only macros produce a key, so a plain node's row clears it rather
            // than setting it — previously _lastkey survived every untagged and
            // non-macro row, so a bracket opened much later snapshotted a macro
            // that had stopped emitting long before and credited its name to
            // whatever the bracket contained.
            if (_inst != "") {
                _lastkey  = _key;
                _lastname = _name;
                _lastinst = _inst;
            } else if (array_length(_pcstack) > 0) {
                _key  = _brkkey;
                _name = _brkname;
                _inst = _brkinst;
            }

            if (_m == "label") {
                ds_map_set(_lblmap, _lbl, _pc);
                _run = -1;

                // Every label now gets a row. Scaffolding labels are flagged
                // internal and are filtered later — hidden in VICE mode, where
                // the branch already shows a resolved address and the name is
                // noise, and shown in ASM mode, where a branch to a label that
                // is never declared makes the listing unreadable.
                var _isint = true;
                if (ds_map_exists(_userlbl, _lbl)) {
                    _isint = false;
                }
                array_push(_flat, { kind:"label", key:_key, name:_name, owner:_owner, inst:_inst, pc:_pc, raw:_m, mnem:_m, val:0, lbl:_lbl, sz:0, res:0, hasres:false, count:0, vals:[], dkey:"", internal:_isint, used:false, used_code:false, top:false });
                continue;
            }

            if (_m == "byte" || _m == "byt" || _m == "byte_lab_lo" || _m == "byte_lab_hi") {

                // A byte whose operand is a label stays its own row — it is a
                // pointer, not table filler, and it needs its own resolution.
                if (_lbl != "") {
                    _run = -1;
                    array_push(_flat, { kind:"byte", key:_key, name:_name, owner:_owner, inst:_inst, pc:_pc, raw:_m, mnem:"byte", val:_v, lbl:_lbl, sz:1, res:0, hasres:false, count:1, vals:[], dkey:"", internal:false, used:false, used_code:false, top:false });
                    _pc += 1;
                    continue;
                }

                // Plain table bytes accumulate into ONE "data" entry holding an
                // array of values. An 8000-byte bitmap costs one struct and one
                // real array here instead of 8000 structs, which is what keeps
                // the rebuild cheap on a graph with several assets in it.
                var _extend = false;
                if (_run >= 0) {
                    if (_flat[_run].key == _key && _flat[_run].inst == _inst) {
                        if (_flat[_run].pc + _flat[_run].count == _pc) {
                            _extend = true;
                        }
                    }
                }

                if (_extend) {
                    array_push(_flat[_run].vals, _v);
                    _flat[_run].count += 1;
                    _flat[_run].sz    += 1;
                } else {
                    var _dname = "BYTE DATA";
                    if (_owner != "") {
                        _dname = _owner;
                    }
                    array_push(_flat, { kind:"data", key:_key, name:_dname, owner:_owner, inst:_inst, pc:_pc, raw:"byte", mnem:"byte", val:0, lbl:"", sz:1, res:0, hasres:false, count:1, vals:[_v], dkey:"D:" + _inst + "@" + scr_show_code_hex(_pc, 4), internal:false, used:false, used_code:false, top:false });
                    _run = array_length(_flat) - 1;
                }

                _pc += 1;
                continue;
            }

            var _norm = scr_show_code_norm(_m);
            var _sz   = obj_opCodeManager.get_size(_norm);
            if (_sz <= 0) { continue; }

            // Branch and jump forms may carry their target in [2] rather than
            // [1]. Restricted to those mnemonics so a stray string sentinel on
            // any other opcode can never be mistaken for a label.
            if (_lbl == "" && _tstr != "" && _tstr != "0") {
                if (scr_show_code_is_branch(_norm) || _norm == "jmp_abs" || _norm == "jsr") {
                    _lbl = _tstr;
                }
            }

            _run = -1;
            array_push(_flat, { kind:"op", key:_key, name:_name, owner:_owner, inst:_inst, pc:_pc, raw:_m, mnem:_norm, val:_v, lbl:_lbl, sz:_sz, res:0, hasres:false, count:1, vals:[], dkey:"", internal:false, used:false, used_code:false, top:false });
            _pc += _sz;
        }

        // ---- PASS 2: resolve label operands now every label address is known.
        // Forward branches are the whole reason this is a second pass. The same
        // walk records which label names anything actually refers to.
        var _refs = ds_map_create();

        // Referenced BY AN INSTRUCTION, as opposed to referenced at all. The
        // <LABEL / >LABEL pointer bytes in a macro's off-spine table also name
        // labels, but those rows are MISC-only — so a label known only to them
        // must not surface while MISC is off, or it would appear with nothing
        // on screen referring to it.
        var _refs_op = ds_map_create();

        for (var _r = 0; _r < array_length(_flat); _r++) {
            var _ln = _flat[_r];
            if (_ln.lbl == "")       { continue; }
            if (_ln.kind == "label") { continue; }
            ds_map_set(_refs, _ln.lbl, 1);
            if (_ln.kind == "op") {
                ds_map_set(_refs_op, _ln.lbl, 1);
            }
            if (!ds_map_exists(_lblmap, _ln.lbl)) { continue; }
            _ln.res    = ds_map_find_value(_lblmap, _ln.lbl);
            _ln.hasres = true;
        }

        // ---- PASS 3: zero-size rows take their owner from what FOLLOWS them.
        //  * used  — is this label the target of anything in the listing? An
        //            unreferenced scaffolding label is pure noise even in ASM
        //            mode, so it never gets shown.
        //  * key   — a label and a relocating ORG both NAME WHAT COMES NEXT,
        //            and neither emits a byte. Attributing one to anything
        //            other than the run it introduces splits a macro in two —
        //            or, when the key it carried was stale, invents a whole
        //            phantom group.
        //
        // That phantom is what put "MACRO_VWAIT 0B" immediately above
        // "MACRO_CHR 15B" at the very same address: the ORG row opening the
        // charset macro's relocation still carried the key remembered from a
        // macro several nodes earlier, so the fold pass saw a one-row run of a
        // different key and gave it its own [+] header. The same shape
        // repeated at every relocation, which is why one macro appeared over
        // and over down the listing.
        //
        // A TOP-LEVEL org (key "") is deliberately left alone. That is an ORG
        // BLOCK boundary — "* = $C000" — and it belongs to the listing itself,
        // not to whatever node happens to follow it.
        var _fn = array_length(_flat);
        for (var _r2 = 0; _r2 < _fn; _r2++) {
            var _lr = _flat[_r2];

            var _adopt = false;

            if (_lr.kind == "label") {
                _lr.used      = ds_map_exists(_refs,    _lr.lbl);
                _lr.used_code = ds_map_exists(_refs_op, _lr.lbl);
                if (_lr.internal && _lr.key == "") {
                    _adopt = true;
                }
            } else if (_lr.kind == "org") {
                if (_lr.key != "") {
                    _adopt = true;
                }
            }

            if (!_adopt) { continue; }

            for (var _f = _r2 + 1; _f < _fn; _f++) {
                if (_flat[_f].kind == "label") { continue; }
                if (_flat[_f].kind == "org")   { continue; }
                _lr.key  = _flat[_f].key;
                _lr.name = _flat[_f].name;
                _lr.inst = _flat[_f].inst;
                break;
            }
        }

        ds_map_destroy(_refs);
        ds_map_destroy(_refs_op);

        ds_map_destroy(_lblmap);
        ds_map_destroy(_userlbl);

        // Total emitted bytes, for the header readout.
        var _tot = 0;
        for (var _t = 0; _t < array_length(_flat); _t++) {
            _tot += _flat[_t].sz;
        }

        // ---- PASS 4: put the listing in ADDRESS order.
        //
        // scr_compile_chain emits ORG blocks sorted by their node's canvas y:
        //
        //     array_sort(_org_nodes, function(a, b) { return a.y - b.y; });
        //
        // so the stream follows where you happened to drag the blocks, not
        // where the code actually lives, and reading down the panel jumped
        // around the memory map. The asset export tail then arrives after every
        // block regardless of address, jumping again.
        //
        // This reorders the VIEW only. The compile stream is untouched, so
        // nothing about the built program changes — doing it in the compile
        // chain would have altered real emission order, and with two ORG blocks
        // overlapping that decides which one wins.
        //
        // Segments are cut at TOP-LEVEL org rows only, so a macro bracketed
        // data table travels with its owner rather than being flung off to its
        // own address. The sort carries the original index as a tie-breaker,
        // because GML array_sort makes no stability promise and two blocks at
        // one address must not swap places at random between frames.
        var _segs    = [];
        var _cur_seg = { pc: global.start_pc, idx: 0, rows: [] };

        for (var _s4 = 0; _s4 < array_length(_flat); _s4++) {
            var _r4 = _flat[_s4];
            if (_r4.kind == "org" && _r4.top) {
                if (array_length(_cur_seg.rows) > 0) {
                    array_push(_segs, _cur_seg);
                }
                _cur_seg = { pc: _r4.pc, idx: array_length(_segs), rows: [] };
            }
            array_push(_cur_seg.rows, _r4);
        }
        if (array_length(_cur_seg.rows) > 0) {
            array_push(_segs, _cur_seg);
        }

        array_sort(_segs, function(_a, _b) {
            if (_a.pc  < _b.pc)  { return -1; }
            if (_a.pc  > _b.pc)  { return  1; }
            if (_a.idx < _b.idx) { return -1; }
            if (_a.idx > _b.idx) { return  1; }
            return 0;
        });

        var _ordered = [];
        for (var _o4 = 0; _o4 < array_length(_segs); _o4++) {
            var _rows4 = _segs[_o4].rows;
            for (var _p4 = 0; _p4 < array_length(_rows4); _p4++) {
                array_push(_ordered, _rows4[_p4]);
            }
        }
        _flat = _ordered;

        showcode_flat   = _flat;
        showcode_total  = _tot;
        showcode_gen    = global.named_loc_repack_gen;
        showcode_dirty  = true;
    }
}

// =====================================================================
// Should this flat entry be hidden in the current mode?
//
// VICE mode is a monitor dump: every operand is already a resolved $nnnn, so a
// label row adds nothing a monitor would ever print. No labels there at all,
// yours included.
//
// ASM mode is the readable one, so it declares labels. Your own ADDRESS LABEL
// nodes always show, and so does any internal label an instruction branches or
// jumps to — a visible branch to an invisible target is worse than useless.
// Scaffolding nothing refers to is noise in any mode and never shows.
// =====================================================================
function scr_show_code_row_hidden(_ln, _mode, _misc) {

    // MISC covers everything that is not code you wrote: the byte tables a
    // macro parks off-spine, the <LABEL / >LABEL pointer bytes that index them,
    // and the macro's own scaffolding labels. Off by default, because none of
    // it is what you came to the listing to read.
    if (_ln.kind == "data") { return !_misc; }
    if (_ln.kind == "byte") { return !_misc; }

    if (_ln.kind != "label") { return false; }

    // VICE is a monitor dump: no label rows at all, yours included.
    if (_mode != 1) { return true; }

    // Your own ADDRESS LABEL nodes are never MISC.
    if (!_ln.internal) { return false; }

    // An internal label that an INSTRUCTION branches or jumps to is declared
    // whether MISC is on or not. It has to be: the listing was showing
    // "BNE CLRSCR_100015_P012" with the row that defines CLRSCR_100015_P012
    // nowhere on screen, so nothing said where the branch went. MISC was being
    // tested BEFORE the unreferenced case, which is what hid every branch
    // target inside a converted code block.
    if (_ln.used_code) { return false; }

    // What is left is scaffolding: unreferenced, or named only by the pointer
    // bytes of an off-spine table that MISC itself controls.
    if (!_misc)    { return true; }
    if (!_ln.used) { return true; }
    return false;
}

// =====================================================================
// ATTRIBUTE — work out which node owns the rows the compile chain left untagged.
//
// Only macros tag their output. scr_compile_chain's DEFAULT case pushes a plain
// node's instruction rows verbatim (`["lda_imm", 0]` — two elements, no node),
// and a LABEL node emits `["label", name]` with no node either. So ordinary
// nodes and labels had nothing for the workspace hover highlight to match on.
//
// LABEL nodes are matched by name, which is exact. Plain nodes are matched by
// pc_address, then carried forward across their following rows until the program
// counter jumps or another node claims one — which is why this runs at the END
// of scr_c64_do_update_addresses(), after pc_address has actually been assigned.
// A pc claimed by two nodes is dropped rather than guessed at.
// =====================================================================
function scr_show_code_attribute() {
    if (!instance_exists(obj_workspace_manager)) { exit; }

    with (obj_workspace_manager) {
        if (!showcode_open) { exit; }
        var _n = array_length(showcode_flat);
        if (_n == 0) { exit; }

        var _lblnode = ds_map_create();   // label name  -> node
        var _pcnode  = ds_map_create();   // pc_address  -> node
        var _pcdupe  = ds_map_create();   // pc_address claimed more than once

        with (obj_c64_node) {
            if (node_type == "INIT") { continue; }

            if (node_type == "LABEL") {
                if (array_length(instructions) > 0 && array_length(instructions[0]) > 1) {
                    ds_map_set(_lblnode, string_replace_all(string(instructions[0][1]), " ", "_"), string(id));
                }
                continue;
            }

            if (string_pos("MACRO_", node_type) == 1) { continue; }  // already tagged
            if (!is_connected) { continue; }

            var _k = string(pc_address);
            if (ds_map_exists(_pcnode, _k)) {
                ds_map_set(_pcdupe, _k, 1);
            } else {
                ds_map_set(_pcnode, _k, string(id));
            }
        }

        var _cur    = "";
        var _expect = -1;

        for (var _i = 0; _i < _n; _i++) {
            var _ln = showcode_flat[_i];

            // A break in the program counter means we are somewhere else
            // entirely — an ORG, or a macro's off-spine data block — so the
            // node we were attributing to no longer applies.
            if (_ln.pc != _expect) { _cur = ""; }
            _expect = _ln.pc + _ln.sz;

            if (_ln.kind == "org") {
                _cur    = "";
                _expect = _ln.pc;
                continue;
            }

            if (_ln.kind == "label") {
                if (ds_map_exists(_lblnode, _ln.lbl)) {
                    _ln.inst = ds_map_find_value(_lblnode, _ln.lbl);
                }
                continue;
            }

            if (_ln.inst != "") {
                _cur = "";       // a macro row: its own node, and it ends the run
                continue;
            }

            var _pk = string(_ln.pc);
            if (ds_map_exists(_pcnode, _pk) && !ds_map_exists(_pcdupe, _pk)) {
                _cur = ds_map_find_value(_pcnode, _pk);
            }
            _ln.inst = _cur;
        }

        ds_map_destroy(_lblnode);
        ds_map_destroy(_pcnode);
        ds_map_destroy(_pcdupe);
    }
}

// =====================================================================
// Emit the display rows for ONE flat entry at the given indent.
// A byte table long enough to be worth hiding becomes its own collapsible
// group; a short one just lists. Arrays are reference types in GML 2.3+,
// so the pushes onto _out are seen by the caller.
// =====================================================================
function scr_show_code_emit(_out, _flat, _idx, _indent, _mode, _misc) {
    var _ln = _flat[_idx];

    if (scr_show_code_row_hidden(_ln, _mode, _misc)) {
        return;
    }

    if (_ln.kind != "data") {
        array_push(_out, { kind:"line", idx:_idx, sub:0, indent:_indent, key:"", name:"", pc:_ln.pc, sz:_ln.sz, count:1, open:false });
        return;
    }

    // Runs this short are not worth a fold — a 2-byte vector reads better inline.
    if (_ln.count < 4) {
        for (var _b = 0; _b < _ln.count; _b++) {
            array_push(_out, { kind:"databyte", idx:_idx, sub:_b, indent:_indent, key:"", name:"", pc:_ln.pc + _b, sz:1, count:1, open:false });
        }
        return;
    }

    var _dopen = scr_show_code_is_open(_ln.dkey);
    array_push(_out, { kind:"datagroup", idx:_idx, sub:0, indent:_indent, key:_ln.dkey, name:_ln.name, pc:_ln.pc, sz:_ln.count, count:_ln.count, open:_dopen });

    if (_dopen) {
        for (var _b2 = 0; _b2 < _ln.count; _b2++) {
            array_push(_out, { kind:"databyte", idx:_idx, sub:_b2, indent:_indent + 10, key:"", name:"", pc:_ln.pc + _b2, sz:1, count:1, open:false });
        }
    }
}

// =====================================================================
// FOLD — flat list -> visible rows, honouring the expand/collapse state.
// Runs on a rebuild and on every expand/collapse click. Never on a plain
// scroll and never per frame.
// =====================================================================
function scr_show_code_fold() {
    if (!instance_exists(obj_workspace_manager)) { exit; }

    with (obj_workspace_manager) {
        var _out  = [];
        var _n    = array_length(showcode_flat);
        var _i    = 0;

        while (_i < _n) {
            var _ln = showcode_flat[_i];

            if (_ln.key == "") {
                scr_show_code_emit(_out, showcode_flat, _i, 0, showcode_mode, showcode_misc);
                _i += 1;
                continue;
            }

            // Fold this run of consecutive lines owned by the same macro node.
            var _k     = _ln.key;
            var _j     = _i;
            var _bytes = 0;
            var _cnt   = 0;
            while (_j < _n && showcode_flat[_j].key == _k) {
                _bytes += showcode_flat[_j].sz;
                _cnt   += 1;
                _j     += 1;
            }

            var _open = scr_show_code_is_open(_k);
            array_push(_out, { kind:"group", idx:_i, sub:0, indent:0, key:_k, name:_ln.name, pc:_ln.pc, sz:_bytes, count:_cnt, open:_open });

            if (_open) {
                for (var _g = _i; _g < _j; _g++) {
                    scr_show_code_emit(_out, showcode_flat, _g, 10, showcode_mode, showcode_misc);
                }
            }

            _i = _j;
        }

        // With MISC off the data blocks vanish, which can leave two ORG markers
        // back to back with nothing between them. Keep the one that actually
        // introduces something.
        var _clean = [];
        var _on    = array_length(_out);
        for (var _o = 0; _o < _on; _o++) {
            var _orow = _out[_o];
            if (_orow.kind == "line" && _o + 1 < _on) {
                if (showcode_flat[_orow.idx].kind == "org") {
                    var _nrow = _out[_o + 1];
                    if (_nrow.kind == "line") {
                        if (showcode_flat[_nrow.idx].kind == "org") { continue; }
                    }
                }
            }
            array_push(_clean, _orow);
        }

        showcode_lines  = _clean;
        showcode_dirty  = false;

        var _maxs = max(0, array_length(showcode_lines) - showcode_rows);
        showcode_scroll = clamp(showcode_scroll, 0, _maxs);
    }
}

// =====================================================================
// BEGIN STEP hit test.
//
// Draw runs AFTER every Step, so a flag set during Draw is a frame stale — on
// the frame the pointer first crosses onto the panel, the nodes underneath
// would still act on the click. Computing it in obj_workspace_manager's Begin
// Step means every Step event that frame already knows the panel owns the
// pointer.
//
// Also resolves which workspace node the pointer is over, for the listing
// highlight.
// =====================================================================
function scr_show_code_hit() {
    global.showcode_mouse_over = false;
    global.showcode_live       = false;
    global.showcode_hover_node = noone;

    if (!instance_exists(obj_workspace_manager)) { exit; }

    with (obj_workspace_manager) {

        // Mirror every condition that stops Draw putting the panel on screen.
        if (hideui)                  { exit; }
        if (gui_menu_open != -1)     { exit; }
        if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) { exit; }

        global.showcode_live = true;

        // A drag or resize in progress owns the pointer wherever it has gone.
        if (showcode_dragging || showcode_resize != 0 || showcode_sb_drag) {
            global.showcode_mouse_over = true;
            exit;
        }

        var _gh = display_get_gui_height();
        var _pw = clamp(showcode_w, 300, 900);

        var _px = showcode_x;
        if (_px < 0) {
            _px = global.sc_x_start - _pw - 14;
        }
        _px = clamp(_px, 0, max(0, global.gui_w - _pw));
        var _py = clamp(showcode_y, 0, max(0, _gh - SHOWCODE_HDR_H - 8));

        var _ph = SHOWCODE_HDR_H + 12;
        if (showcode_open) {
            var _fit  = floor((_gh - _py - SHOWCODE_HDR_H - SHOWCODE_PAD_T - SHOWCODE_PAD_B - 6) / SHOWCODE_ROW_H);
            var _rows = clamp(showcode_rows, 1, max(1, min(SHOWCODE_MAX_ROWS, _fit)));
            _ph = SHOWCODE_HDR_H + SHOWCODE_PAD_T + (_rows * SHOWCODE_ROW_H) + SHOWCODE_PAD_B;
        }

        var _mx = global.gui_mouse_x;
        var _my = global.gui_mouse_y;

        if (_mx >= _px - SHOWCODE_GRAB && _mx < _px + _pw + SHOWCODE_GRAB &&
            _my >= _py                 && _my < _py + _ph + SHOWCODE_GRAB) {
            global.showcode_mouse_over = true;
            exit;
        }

        // Pointer is out on the workspace — find the node under it so the
        // listing can highlight that node's code.
        if (!showcode_open) { exit; }

        with (obj_c64_node) {
            if (node_type == "INIT") { continue; }
            if (point_in_rectangle(mouse_x, mouse_y, x + x_indent, y, x + x_indent + width, y + height)) {
                global.showcode_hover_node = id;
                break;
            }
        }
    }
}

// =====================================================================
// DRAW — panel chrome, listing, drag, resize, scroll, collapse, mode.
// Call this once from obj_workspace_manager's Draw GUI event.
// =====================================================================
function scr_show_code_draw() {
    if (!instance_exists(obj_workspace_manager)) { exit; }

    with (obj_workspace_manager) {

        global.showcode_mouse_over = false;

        // A dropdown menu owns the screen while it is open — stand down so the
        // two panels never fight, and come straight back once it closes.
        if (gui_menu_open != -1) {
            showcode_dragging = false;
            showcode_resize   = 0;
            exit;
        }

        if (showcode_dirty) {
            scr_show_code_fold();
        }

        var _gw = global.gui_w;
        var _gh = display_get_gui_height();
        var _mx = global.gui_mouse_x;
        var _my = global.gui_mouse_y;

        // ---- geometry -------------------------------------------------
        var _hdr_h = SHOWCODE_HDR_H;
        var _row_h = SHOWCODE_ROW_H;
        var _pad_t = SHOWCODE_PAD_T;
        var _pad_b = SHOWCODE_PAD_B;
        var _grab  = SHOWCODE_GRAB;

        showcode_w    = clamp(showcode_w, 300, 900);
        showcode_rows = clamp(showcode_rows, 5, SHOWCODE_MAX_ROWS);

        var _pw = showcode_w;

        // First run of a fresh .ini: park immediately left of the shortcuts column.
        if (showcode_x < 0) {
            showcode_x = global.sc_x_start - _pw - 14;
            showcode_y = 50;
        }

        showcode_x = clamp(showcode_x, 0, max(0, _gw - _pw));
        showcode_y = clamp(showcode_y, 0, max(0, _gh - _hdr_h - 8));

        var _px = floor(showcode_x);
        var _py = floor(showcode_y);

        // Rows actually drawn: the setting, capped by what fits below the
        // panel's current y. Dragging the panel down never destroys a 60-row
        // setting — it just shows fewer until you drag it back up.
        var _fit  = floor((_gh - _py - _hdr_h - _pad_t - _pad_b - 6) / _row_h);
        var _rows = clamp(showcode_rows, 1, max(1, min(SHOWCODE_MAX_ROWS, _fit)));

        var _body_h = _rows * _row_h;
        var _ph     = _hdr_h + _pad_t + _body_h + _pad_b;
        if (!showcode_open) {
            _ph = _hdr_h + 12;
        }

        // ---- header buttons -------------------------------------------
        var _btn_w     = 30;
        var _btn_min_x = _px + _pw - 10 - _btn_w;
        // Mode control is a two-segment switch, not a one-word button: the old
        // button showed the CURRENT mode, which reads just as easily as "click
        // to switch TO this". Both options are on screen now, the active one
        // filled, so there is nothing to infer.
        var _seg_w     = 42;
        var _mod_w     = _seg_w * 2;
        var _btn_mod_x = _btn_min_x - 6 - _mod_w;

        // MISC sits between the title and the mode switch.
        var _msc_w     = 46;
        var _btn_msc_x = _btn_mod_x - 6 - _msc_w;

        var _hdr_hover = (_mx >= _px && _mx < _px + _pw && _my >= _py && _my < _py + _hdr_h);
        var _in_hdr_v  = (_my >= _py + 4 && _my < _py + _hdr_h - 4);
        var _on_min = (_mx >= _btn_min_x && _mx < _btn_min_x + _btn_w && _in_hdr_v);
        var _on_seg0 = (_mx >= _btn_mod_x           && _mx < _btn_mod_x + _seg_w && _in_hdr_v);
        var _on_seg1 = (_mx >= _btn_mod_x + _seg_w  && _mx < _btn_mod_x + _mod_w && _in_hdr_v);
        var _on_mod  = (_on_seg0 || _on_seg1);
        var _on_msc  = (_mx >= _btn_msc_x && _mx < _btn_msc_x + _msc_w && _in_hdr_v);

        // ---- resize edges ---------------------------------------------
        // Live only while the panel is open, and only below the header so a
        // header drag is never ambiguous.
        var _edge_l = false;
        var _edge_r = false;
        var _edge_b = false;
        if (showcode_open) {
            var _in_v = (_my >= _py + _hdr_h && _my <= _py + _ph + _grab);
            var _in_h = (_mx >= _px - _grab  && _mx <= _px + _pw + _grab);

            _edge_l = (_in_v && _mx >= _px - _grab && _mx <= _px + _grab);
            _edge_r = (_in_v && _mx >= _px + _pw - _grab && _mx <= _px + _pw + _grab);
            _edge_b = (_in_h && _my >= _py + _ph - _grab && _my <= _py + _ph + _grab);

            // The bottom edge wins the corners — it is the one you reach for.
            if (_edge_b) {
                _edge_l = false;
                _edge_r = false;
            }
        }

        // ---- press ------------------------------------------------------
        // The scrollbar sits inside the body and claims its own presses further
        // down; the edge tests below must not steal one.
        if (mouse_check_button_pressed(mb_left) && !showcode_sb_drag) {
            if (_on_min) {
                showcode_open = !showcode_open;
                // Nothing was built while it was shut, so ask for the pass that
                // fills it back in.
                if (showcode_open) {
                    global.addresses_dirty = true;
                }
                scr_show_code_save_ini();
            } else if (_on_msc && showcode_open) {
                showcode_misc  = !showcode_misc;
                // Visibility changes the fold, not just the paint.
                showcode_dirty = true;
                scr_show_code_save_ini();
            } else if (_on_mod && showcode_open) {
                var _newmode = showcode_mode;
                if (_on_seg0) { _newmode = 0; }
                if (_on_seg1) { _newmode = 1; }
                if (_newmode != showcode_mode) {
                    showcode_mode  = _newmode;
                    // Label visibility depends on the mode, so the fold has to
                    // be rebuilt — not just redrawn.
                    showcode_dirty = true;
                    scr_show_code_save_ini();
                }
            } else if (_edge_b) {
                showcode_resize  = 3;
            } else if (_edge_l) {
                showcode_resize  = 1;
                showcode_rs_edge = _px + _pw;   // pin the right edge
            } else if (_edge_r) {
                showcode_resize  = 2;
            } else if (_hdr_hover) {
                showcode_dragging = true;
                showcode_drag_dx  = _mx - showcode_x;
                showcode_drag_dy  = _my - showcode_y;
            }
        }

        // ---- resize -----------------------------------------------------
        if (showcode_resize != 0) {
            if (mouse_check_button(mb_left)) {
                if (showcode_resize == 1) {
                    var _newx = clamp(_mx, 0, showcode_rs_edge - 300);
                    showcode_w = clamp(showcode_rs_edge - _newx, 300, 900);
                    showcode_x = showcode_rs_edge - showcode_w;
                } else if (showcode_resize == 2) {
                    showcode_w = clamp(_mx - _px, 300, 900);
                } else {
                    var _body_top = _py + _hdr_h + _pad_t;
                    showcode_rows = clamp(round((_my - _pad_b - _body_top) / _row_h), 5, SHOWCODE_MAX_ROWS);
                }

                _pw     = showcode_w;
                _px     = floor(showcode_x);
                _rows   = clamp(showcode_rows, 1, max(1, min(SHOWCODE_MAX_ROWS, _fit)));
                _body_h = _rows * _row_h;
                _ph     = _hdr_h + _pad_t + _body_h + _pad_b;

                _btn_min_x = _px + _pw - 10 - _btn_w;
                _btn_mod_x = _btn_min_x - 6 - _mod_w;
                _btn_msc_x = _btn_mod_x - 6 - _msc_w;
            } else {
                showcode_resize = 0;
                scr_show_code_save_ini();
            }
        }

        // ---- drag ------------------------------------------------------
        if (showcode_dragging) {
            if (mouse_check_button(mb_left)) {
                showcode_x = _mx - showcode_drag_dx;
                showcode_y = _my - showcode_drag_dy;
                showcode_x = clamp(showcode_x, 0, max(0, _gw - _pw));
                showcode_y = clamp(showcode_y, 0, max(0, _gh - _hdr_h - 8));
                _px = floor(showcode_x);
                _py = floor(showcode_y);

                _fit    = floor((_gh - _py - _hdr_h - _pad_t - _pad_b - 6) / _row_h);
                _rows   = clamp(showcode_rows, 1, max(1, min(SHOWCODE_MAX_ROWS, _fit)));
                _body_h = _rows * _row_h;
                _ph     = _hdr_h + _pad_t + _body_h + _pad_b;
                if (!showcode_open) {
                    _ph = _hdr_h + 12;
                }

                _btn_min_x = _px + _pw - 10 - _btn_w;
                _btn_mod_x = _btn_min_x - 6 - _mod_w;
                _btn_msc_x = _btn_mod_x - 6 - _msc_w;
            } else {
                showcode_dragging = false;
                scr_show_code_save_ini();
            }
        }

        // Everything below the workspace needs to know the mouse is ours.
        // The rect is grown by the grab margin so the edge handles are covered.
        var _over = (_mx >= _px - _grab && _mx < _px + _pw + _grab &&
                     _my >= _py         && _my < _py + _ph + _grab);
        global.showcode_mouse_over = (_over || showcode_dragging || showcode_resize != 0 || showcode_sb_drag);

        // ---- panel background: the same glass 9-slice the menus use ----
        draw_sprite_stretched(spr_glassSlice, niceSliceFrm, _px, _py, _pw, _ph);

        var _font_before   = draw_get_font();
        var _halign_before = draw_get_halign();
        var _valign_before = draw_get_valign();
        draw_set_valign(fa_top);

        // ---- header ----------------------------------------------------
        draw_set_font(fnt_C64_Angled);
        draw_set_halign(fa_left);
        draw_set_color(c_white);
        draw_text_transformed(_px + 12, _py + 6, "SHOW CODE", 1.0, 1.0, 0);

        // Program size, only when the panel is wide enough to hold it without
        // crowding the buttons.
        if (showcode_open && _pw >= 380) {
            draw_set_color(make_color_rgb(120, 130, 150));
            draw_text_transformed(_px + 114, _py + 6, string(showcode_total) + " B", 1.0, 1.0, 0);
        }

        if (showcode_open) {
            var _sy1 = _py + 4;
            var _sy2 = _py + _hdr_h - 4;
            var _acc = make_color_rgb(255, 210, 80);

            // MISC — same visual language as the mode switch: filled when on.
            if (showcode_misc) {
                draw_set_color(_acc);
                draw_rectangle(_btn_msc_x + 1, _sy1 + 1, _btn_msc_x + _msc_w - 1, _sy2 - 1, false);
            }
            draw_set_color(make_color_rgb(120, 120, 130));
            draw_rectangle(_btn_msc_x, _sy1, _btn_msc_x + _msc_w, _sy2, true);

            var _cm = make_color_rgb(140, 140, 150);
            if (showcode_misc) {
                _cm = c_black;
            } else if (_on_msc) {
                _cm = c_white;
            }
            draw_set_color(_cm);
            draw_set_halign(fa_center);
            draw_text_transformed(_btn_msc_x + (_msc_w / 2), _py + 6, "MISC", 1.0, 1.0, 0);
            draw_set_halign(fa_left);

            // Active segment filled, inactive segment just outlined.
            var _act_x = _btn_mod_x;
            if (showcode_mode == 1) {
                _act_x = _btn_mod_x + _seg_w;
            }
            draw_set_color(_acc);
            draw_rectangle(_act_x + 1, _sy1 + 1, _act_x + _seg_w - 1, _sy2 - 1, false);

            draw_set_color(make_color_rgb(120, 120, 130));
            draw_rectangle(_btn_mod_x, _sy1, _btn_mod_x + _mod_w, _sy2, true);
            draw_line(_btn_mod_x + _seg_w, _sy1, _btn_mod_x + _seg_w, _sy2);

            draw_set_halign(fa_center);

            // VICE segment
            var _c0 = make_color_rgb(140, 140, 150);
            if (showcode_mode == 0) {
                _c0 = c_black;
            } else if (_on_seg0) {
                _c0 = c_white;
            }
            draw_set_color(_c0);
            draw_text_transformed(_btn_mod_x + (_seg_w / 2), _py + 6, "VICE", 1.0, 1.0, 0);

            // ASM segment
            var _c1 = make_color_rgb(140, 140, 150);
            if (showcode_mode == 1) {
                _c1 = c_black;
            } else if (_on_seg1) {
                _c1 = c_white;
            }
            draw_set_color(_c1);
            draw_text_transformed(_btn_mod_x + _seg_w + (_seg_w / 2), _py + 6, "ASM", 1.0, 1.0, 0);
        }

        var _min_lbl = "-";
        if (!showcode_open) {
            _min_lbl = "+";
        }
        var _min_col = make_color_rgb(120, 120, 130);
        if (_on_min) {
            _min_col = c_white;
        }
        draw_set_color(_min_col);
        draw_rectangle(_btn_min_x, _py + 4, _btn_min_x + _btn_w, _py + _hdr_h - 4, true);
        draw_set_halign(fa_center);
        draw_text_transformed(_btn_min_x + (_btn_w / 2), _py + 5, _min_lbl, 1.0, 1.0, 0);

        if (!showcode_open) {
            draw_set_font(_font_before);
            draw_set_halign(_halign_before);
            draw_set_valign(_valign_before);
            exit;
        }

        // ---- body ------------------------------------------------------
        var _total = array_length(showcode_lines);
        var _maxs  = max(0, _total - _rows);
        showcode_scroll = clamp(showcode_scroll, 0, _maxs);

        var _body_y = _py + _hdr_h + _pad_t;

        // Wheel scrolls the listing whenever the pointer is over the panel.
        if (_over && showcode_resize == 0) {
            if (mouse_wheel_up())   { showcode_scroll = max(0,     showcode_scroll - 3); }
            if (mouse_wheel_down()) { showcode_scroll = min(_maxs, showcode_scroll + 3); }
        }

        // Column origins. ASM mode drops the raw byte column and pulls the
        // disassembly left into the space it frees.
        var _col_addr = _px + 12;
        var _col_byte = _px + 66;
        var _col_text = _px + 150;
        if (showcode_mode == 1) {
            _col_text = _px + 66;
        }

        // ---- workspace hover -> highlight that node's code ---------------
        // Every display row carries idx into showcode_flat, and every flat
        // entry knows its owning node, so one string compare per drawn row is
        // the whole match — collapsed macro rows included, since a group row's
        // idx points at the first entry of its run.
        var _hov_key = "";
        if (global.showcode_hover_node != noone) {
            if (instance_exists(global.showcode_hover_node)) {
                _hov_key = string(global.showcode_hover_node);
            }
        }

        // Scroll to the match only when the hovered node CHANGES, otherwise the
        // panel would yank itself back every time you scrolled while hovering.
        if (_hov_key != showcode_last_hover) {
            showcode_last_hover = _hov_key;

            if (_hov_key != "") {
                var _find = -1;
                for (var _s = 0; _s < _total; _s++) {
                    if (showcode_flat[showcode_lines[_s].idx].inst == _hov_key) {
                        _find = _s;
                        break;
                    }
                }
                if (_find >= 0) {
                    if (_find < showcode_scroll || _find >= showcode_scroll + _rows) {
                        showcode_scroll = clamp(_find - 3, 0, _maxs);
                    }
                }
            }
        }

        draw_set_font(fnt_c64_opCode);
        draw_set_halign(fa_left);

        if (_total == 0) {
            draw_set_color(make_color_rgb(120, 120, 130));
            draw_text_transformed(_col_addr, _body_y, "NO CODE — ADD SOME NODES", 1.0, 1.0, 0);
        }

        var _clicked_key = "";

        for (var _r = 0; _r < _rows; _r++) {
            var _li = showcode_scroll + _r;
            if (_li >= _total) { break; }

            var _row    = showcode_lines[_li];
            var _ry     = _body_y + (_r * _row_h);
            var _indent = _row.indent;
            var _rhov   = (showcode_resize == 0 && !showcode_dragging && !showcode_sb_drag &&
                           _mx >= _px + 6 && _mx < _px + _pw - 18 &&
                           _my >= _ry && _my < _ry + _row_h);

            if (_hov_key != "" && showcode_flat[_row.idx].inst == _hov_key) {
                draw_set_alpha(0.16);
                draw_set_color(make_color_rgb(90, 200, 255));
                draw_rectangle(_px + 6, _ry, _px + _pw - 14, _ry + _row_h - 1, false);
                draw_set_alpha(1.0);
                draw_set_color(make_color_rgb(90, 200, 255));
                draw_rectangle(_px + 6, _ry, _px + 7, _ry + _row_h - 1, false);
            }

            // ---- collapsible rows: macro groups and byte tables ----
            if (_row.kind == "group" || _row.kind == "datagroup") {

                if (_rhov) {
                    draw_set_alpha(0.22);
                    draw_set_color(c_white);
                    draw_rectangle(_px + 6, _ry, _px + _pw - 14, _ry + _row_h - 1, false);
                    draw_set_alpha(1.0);

                    if (mouse_check_button_pressed(mb_left)) {
                        _clicked_key = _row.key;
                    }
                }

                var _sign = "[+]";
                if (_row.open) {
                    _sign = "[-]";
                }

                var _gtitle = _sign + " " + _row.name;
                var _gcol   = make_color_rgb(255, 210, 80);
                if (_row.kind == "datagroup") {
                    // Byte tables get their span in the title — the thing you
                    // actually want to know about a data block you cannot see.
                    _gtitle = _sign + " " + _row.name + "  $" + scr_show_code_hex(_row.pc, 4)
                            + "-$" + scr_show_code_hex(_row.pc + _row.count - 1, 4);
                    _gcol   = make_color_rgb(180, 170, 210);
                }

                draw_set_color(make_color_rgb(150, 150, 160));
                draw_text_transformed(_col_addr + _indent, _ry, "." + scr_show_code_hex(_row.pc, 4), 1.0, 1.0, 0);

                draw_set_color(_gcol);
                draw_text_transformed(_col_byte + _indent, _ry, _gtitle, 1.0, 1.0, 0);

                draw_set_halign(fa_right);
                draw_set_color(make_color_rgb(110, 130, 150));
                draw_text_transformed(_px + _pw - 20, _ry, string(_row.sz) + "B", 1.0, 1.0, 0);
                draw_set_halign(fa_left);

                continue;
            }

            var _ln = showcode_flat[_row.idx];

            // ---- one byte out of an expanded (or short) table ----
            if (_row.kind == "databyte") {
                var _bv = _ln.vals[_row.sub];

                draw_set_color(make_color_rgb(150, 150, 160));
                draw_text_transformed(_col_addr + _indent, _ry, "." + scr_show_code_hex(_row.pc, 4), 1.0, 1.0, 0);

                if (showcode_mode == 0) {
                    draw_set_color(make_color_rgb(190, 190, 120));
                    draw_text_transformed(_col_byte + _indent, _ry, scr_show_code_hex(_bv, 2), 1.0, 1.0, 0);
                }

                draw_set_color(make_color_rgb(180, 170, 210));
                draw_text_transformed(_col_text + _indent, _ry, ".BYTE $" + scr_show_code_hex(_bv, 2), 1.0, 1.0, 0);
                continue;
            }

            var _tint = make_color_rgb(210, 220, 230);
            if (_indent > 0) {
                _tint = make_color_rgb(160, 200, 220);
            }
            if (_ln.kind == "label") {
                _tint = make_color_rgb(120, 230, 140);
            }
            if (_ln.kind == "org") {
                _tint = make_color_rgb(255, 140, 140);
            }
            if (_ln.kind == "byte") {
                _tint = make_color_rgb(180, 170, 210);
            }

            draw_set_color(make_color_rgb(150, 150, 160));
            draw_text_transformed(_col_addr + _indent, _ry, "." + scr_show_code_hex(_ln.pc, 4), 1.0, 1.0, 0);

            if (showcode_mode == 0 && _ln.kind != "label" && _ln.kind != "org") {
                draw_set_color(make_color_rgb(190, 190, 120));
                draw_text_transformed(_col_byte + _indent, _ry, scr_show_code_bytes(_ln), 1.0, 1.0, 0);
            }

            // A label hangs left of the code it names, the way it reads in a
            // source listing — now by one character beyond the group indent,
            // so a declaration is picked out from the instructions under it at
            // a glance rather than lining up flush with them.
            //
            // Measured from the font rather than hardcoded, and floored so the
            // hang can never reach back into the address column. ASM mode drops
            // the raw byte column, which is what leaves room for this at all;
            // labels are not drawn in VICE mode, so nothing there is affected.
            var _tx_indent = _indent;
            if (_ln.kind == "label") {
                _tx_indent = _indent - 10 - string_width("0");
                var _lbl_min = (_col_addr + string_width(".FFFF") + 4) - _col_text;
                if (_tx_indent < _lbl_min) {
                    _tx_indent = _lbl_min;
                }
            }

            draw_set_color(_tint);
            draw_text_transformed(_col_text + _tx_indent, _ry, scr_show_code_text(_ln, showcode_mode), 1.0, 1.0, 0);
        }

        if (_clicked_key != "") {
            scr_show_code_toggle(_clicked_key);
        }

        // ---- scrollbar --------------------------------------------------
        if (_total > _rows) {
            var _tr_x  = _px + _pw - 12;
            var _tr_y1 = _body_y;
            var _tr_y2 = _body_y + _body_h;
            var _tr_h  = _tr_y2 - _tr_y1;

            var _frac = _rows / _total;
            var _thh  = max(16, _tr_h * _frac);
            var _span = max(1, _tr_h - _thh);          // travel available to the thumb
            var _thy  = _tr_y1 + (_span * (showcode_scroll / max(1, _maxs)));

            // Hit zone is wider than the 5 px bar so it can actually be grabbed,
            // and stops 6 px short of the panel edge so it never fights the
            // right-hand resize handle.
            var _sb_hit = (_mx >= _tr_x - 5 && _mx <= _tr_x + 6 &&
                           _my >= _tr_y1    && _my <= _tr_y2);
            var _on_thumb = (_sb_hit && _my >= _thy && _my <= _thy + _thh);

            if (mouse_check_button_pressed(mb_left) && _sb_hit && !showcode_dragging && showcode_resize == 0) {
                if (_on_thumb) {
                    showcode_sb_drag = true;
                    showcode_sb_off  = _my - _thy;
                } else {
                    // Track click pages towards the pointer, like any scrollbar.
                    if (_my < _thy) {
                        showcode_scroll = max(0, showcode_scroll - _rows);
                    } else {
                        showcode_scroll = min(_maxs, showcode_scroll + _rows);
                    }
                }
            }

            if (showcode_sb_drag) {
                if (mouse_check_button(mb_left)) {
                    var _want = clamp(_my - showcode_sb_off, _tr_y1, _tr_y1 + _span);
                    showcode_scroll = round(((_want - _tr_y1) / _span) * _maxs);
                    showcode_scroll = clamp(showcode_scroll, 0, _maxs);
                    _thy = _tr_y1 + (_span * (showcode_scroll / max(1, _maxs)));
                } else {
                    showcode_sb_drag = false;
                }
            }

            draw_set_alpha(0.30);
            draw_set_color(c_black);
            draw_rectangle(_tr_x, _tr_y1, _tr_x + 5, _tr_y2, false);
            draw_set_alpha(1.0);

            var _sb_col = make_color_rgb(160, 170, 190);
            if (showcode_sb_drag) {
                _sb_col = make_color_rgb(255, 210, 80);
            } else if (_on_thumb) {
                _sb_col = c_white;
            }
            draw_set_color(_sb_col);
            draw_rectangle(_tr_x, _thy, _tr_x + 5, _thy + _thh, false);
        } else {
            showcode_sb_drag = false;
        }

        // ---- resize affordance ------------------------------------------
        // A thin bar on whichever edge is hovered or actively being dragged,
        // plus a row counter on the bottom edge while it is in use.
        var _hl_l = (_edge_l || showcode_resize == 1);
        var _hl_r = (_edge_r || showcode_resize == 2);
        var _hl_b = (_edge_b || showcode_resize == 3);

        draw_set_alpha(0.75);
        draw_set_color(make_color_rgb(255, 210, 80));
        if (_hl_l) { draw_rectangle(_px,          _py + _hdr_h, _px + 2,       _py + _ph - 2, false); }
        if (_hl_r) { draw_rectangle(_px + _pw - 2, _py + _hdr_h, _px + _pw,    _py + _ph - 2, false); }
        if (_hl_b) { draw_rectangle(_px + 4,      _py + _ph - 2, _px + _pw - 4, _py + _ph,    false); }
        draw_set_alpha(1.0);

        if (showcode_resize == 3) {
            draw_set_halign(fa_center);
            draw_set_color(c_white);
            draw_text_transformed(_px + (_pw / 2), _py + _ph + 4, string(showcode_rows) + " LINES", 1.0, 1.0, 0);
            draw_set_halign(fa_left);
        }

        draw_set_font(_font_before);
        draw_set_halign(_halign_before);
        draw_set_valign(_valign_before);
        draw_set_color(c_white);
    }
}

// =====================================================================
// Persist geometry / open state / mode. Written on every state change so
// the panel comes back exactly where and how it was left.
// =====================================================================
function scr_show_code_save_ini() {
    with (obj_workspace_manager) {
        var _open_flag = 0;
        if (showcode_open) {
            _open_flag = 1;
        }

        ini_open("c64devmachine.ini");
        ini_write_real("showcode", "x",    floor(showcode_x));
        ini_write_real("showcode", "y",    floor(showcode_y));
        ini_write_real("showcode", "w",    floor(showcode_w));
        ini_write_real("showcode", "rows", showcode_rows);
        ini_write_real("showcode", "open", _open_flag);
        ini_write_real("showcode", "mode", showcode_mode);
        var _misc_flag = 0;
        if (showcode_misc) {
            _misc_flag = 1;
        }
        ini_write_real("showcode", "misc", _misc_flag);
        ini_close();
    }
}
