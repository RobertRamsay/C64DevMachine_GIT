/// @desc CONVERT SELECTION TO CODE BLOCK  (PRO — gated behind !global.lite)
///
/// Turns the selected spine nodes into one MACRO_CODE block whose text assembles
/// to the identical byte stream, then deletes the originals.
///
/// ── Why this is safe to run on macros ────────────────────────────────────────
/// Macros do not just emit inline code. Several (METAMAP, SCROLL, CHR, LOADER…)
/// bracket an off-spine data block with the compile chain's PC save/restore
/// markers — ["org",-2] … ["org",addr] … data … ["org",-3] — and the bytes in
/// there are deliberately tagged `noone`, so they are NOT part of the node's
/// slice. Rendering a macro from its slice alone would silently drop its tables.
///
/// So the extraction below does not use slices. It walks the compile output
/// linearly, attributes every entry (tagged or not) to an owning node, and
/// simulates the PC stack so relocated regions are captured with the address
/// they belong at. Those come out as ".pc $XXXX" sections appended AFTER the
/// spine code — one-way relocation, which is exactly what the code-block parser
/// supports, and it means nothing has to relocate back.
///
/// ── And why you can trust the result ─────────────────────────────────────────
/// Reasoning about which macros are self-contained is not good enough. Instead
/// the generated text is fed straight back through scr_parse_asm_text() and the
/// resulting byte stream is compared, entry by entry, against the stream the
/// selection produced. If they differ ANYWHERE the conversion is abandoned and
/// nothing is deleted. That turns "is this macro convertible?" from a judgement
/// call into a measurement.
///
/// Functions:
///   scr_cbc_selection()        selected connected nodes, spine order
///   scr_cbc_validate()         { ok, reason, nodes }
///   scr_cbc_owner_map()        label name -> owning LABEL node
///   scr_cbc_extract(_sel)      compile output -> { ok, spine, reloc }
///   scr_cbc_sig(_entries)      section -> comparable signature array
///   scr_cbc_asset_deps(_sel)   asset-mode references the selection would orphan
///   scr_cbc_inline_text(_sel)  build-time injected text the stream never carries
///   scr_cbc_render(_ex,_deps)  sections -> code block text
///   scr_cbc_verify(_txt, _ex)  round trip the text, compare signatures
///   scr_cbc_convert()          the whole operation, including the swap
///   scr_cbc_button_rect()      one geometry definition for hit test + draw
///   scr_cbc_hit()              Begin Step: is the button under the pointer
///   scr_cbc_draw_button()      the floating CONVERT TO CODE button

// =====================================================================
// Selected, connected, spine-ordered.
// =====================================================================
function scr_cbc_selection() {
    var _out = [];

    for (var _i = 0; _i < array_length(global.selected_nodes); _i++) {
        var _n = global.selected_nodes[_i];
        if (!instance_exists(_n))   { continue; }
        if (!_n.is_connected)       { continue; }
        if (_n.node_type == "INIT") { continue; }
        if (_n.node_type == "ORG")  { continue; }
        array_push(_out, _n);
    }

    array_sort(_out, function(_a, _b) {
        if (_a.y < _b.y) { return -1; }
        if (_a.y > _b.y) { return  1; }
        return 0;
    });

    return _out;
}

// =====================================================================
// Can this selection become one block?
// =====================================================================
// =====================================================================
// SID / IRQ latching — refused up front, by node type.
//
// The general neutrality gate below already catches any node whose removal
// changes another node's output, and catches it precisely: convert a MACRO_CHR
// nothing branches on and it lets you through. This list exists because the
// IRQ family is the one place where being precise is not enough.
//
// MACRO_SID owns the interrupt. It installs the handler, acks $D019, and emits
// other nodes' code on their behalf — the raster chain that points $0314/$0315
// at a scroller is six instructions inside MACRO_SID's own case, keyed on the
// scroll node's instance id. MACRO_IRQ_HANDLER is its peer; five sites in the
// emission path treat ownership as (MACRO_SID || MACRO_IRQ_HANDLER).
// MACRO_TEXT_SCROLL is the other end of that binding and cannot run without an
// owner at all — its standalone path is a deliberate `jmp *`.
//
// Converting any of them is a one-way trapdoor in BOTH directions:
//
//   * The block stops seeing the graph. Whatever the scans answered at
//     conversion time is frozen into text. Convert a scroller with no SID
//     present and the dead loop is baked in; adding a SID afterwards cannot
//     revive it.
//
//   * The graph stops seeing the block. Convert the owner — even together with
//     everything that latches to it, which is otherwise the correct move — and
//     the IRQ role still exists in the binary but no longer exists to any
//     macro. The next scroller node you drop in finds no owner, sets
//     _use_sid = 0, and spins forever.
//
// The neutrality gate can only prove the first of those, and only for the graph
// as it stands when you press the button. Nothing inside a convert action can
// vouch for edits that have not happened yet. So these are refused outright and
// the button says why, rather than converting cleanly and failing later on
// hardware with nothing pointing at the cause.
//
// @return the offending node type, or "" when the selection is clear.
// =====================================================================
function scr_cbc_irq_dependency(_sel) {
    for (var _i = 0; _i < array_length(_sel); _i++) {
        var _n = _sel[_i];
        if (!instance_exists(_n)) { continue; }

        var _t = string(_n.node_type);
        if (_t == "MACRO_SID")         { return _t; }
        if (_t == "MACRO_IRQ")         { return _t; }
        if (_t == "MACRO_IRQ_HANDLER") { return _t; }
        if (_t == "MACRO_TEXT_SCROLL") { return _t; }
    }
    return "";
}

// =====================================================================
// Node types that can never be converted, for reasons of their own.
//
// The neutrality gate proves that removing a node does not change what the
// nodes AROUND it emit. That is not the same as proving the node survives
// being frozen into text. A node fails here when its own emission depends on
// something that keeps moving after the conversion — a live scan of the
// graph, an alias other nodes resolve at compile time, or a buffer whose
// address the memory-bar allocator hands out on each rebuild.
//
// MACRO_SCROLL (MAP H SCROLL) is all three at once. It publishes JSR entry
// points other nodes call through `scroll_alias`, it re-reads its MAP_DATA or
// META_TILESET source on every compile to size and lay out its double buffers,
// and the allocator can hand it a different base on the next rebuild. Frozen
// to text, the block keeps the addresses it happened to get on the day and
// stops answering to the alias — so callers still assemble, still JSR, and
// land somewhere that is no longer the scroller.
//
// MACRO_VSCROLL (MAP V SCROLL) is the same node wearing a different axis. It
// takes the same `scroll_alias` path in the emission code, publishes the same
// kind of entry points (Scroller_U / Scroller_D), and buffers the same way.
// Everything true of the horizontal scroller is true of it.
//
// MACRO_COLLISION is on the list for a different reason: it shares one piece
// of per-frame state with every other collision node in the program. Reading
// $D01E and $D01F CLEARS them, so exactly one node — whichever compiles first
// — emits the pre-latch that copies both into $F0/$F1, guarded by
// global.coll_prelatch_done. Every other collision node then tests the ZP
// copies. Convert the collision nodes and that pre-latch is frozen into text
// where the guard cannot see it, so the next collision node added to the graph
// emits a SECOND pre-latch. The second read returns only what has collided
// since the first one, which is almost nothing, and both the block and the new
// node quietly stop detecting hits. Nothing fails to assemble; it just stops
// working, intermittently, with no line to point at.
//
// The neutrality gate catches that only while a sibling collision node is
// still outside the selection. Select them all — the move the gate's own
// message tells you to make — and it passes cleanly, then breaks on the day
// you drop a new collision node in.
//
// MACRO_COLL_ADV and MACRO_COLL_LINE are deliberately NOT here. They never
// touch $D01E/$D01F; they read map and tile-type data. What they share is the
// COLL_ROW_LO / COLL_ROW_HI / COLL_COL_HI tables, and those are fixed 40x25
// screen-row address constants. A duplicate definition of one silently wins
// in the assembler's label map, but it is byte-identical to the copy it
// replaces, so the program behaves the same and only carries the dead bytes.
//
// To add a type here, put it in the array. Nothing else needs to change.
//
// @return the offending node type, or "" when the selection is clear.
// =====================================================================
function scr_cbc_unconvertible(_sel) {
    var _blocked = ["MACRO_SCROLL", "MACRO_VSCROLL", "MACRO_METASCROLL", "MACRO_COLLISION"];

    for (var _i = 0; _i < array_length(_sel); _i++) {
        var _n = _sel[_i];
        if (!instance_exists(_n)) {
            continue;
        }

        var _t = string(_n.node_type);
        for (var _b = 0; _b < array_length(_blocked); _b++) {
            if (_t == _blocked[_b]) {
                return _t;
            }
        }
    }

    return "";
}

function scr_cbc_validate() {
    var _res = { ok: false, reason: "", nodes: [] };

    if (global.lite) {
        _res.reason = "CODE BLOCKS ARE A FULL VERSION FEATURE";
        return _res;
    }

    var _sel = scr_cbc_selection();
    if (array_length(_sel) < 1) {
        _res.reason = "SELECT SOME CONNECTED NODES FIRST";
        return _res;
    }

    // Refused by TYPE, before anything is measured, because these are the ones
    // where the failure is certain, silent and expensive to diagnose. See
    // scr_cbc_irq_dependency for why each is on the list.
    if (scr_cbc_irq_dependency(_sel) != "") {
        _res.reason = "CANNOT CONVERT - SID / IRQ DEPENDENCY";
        return _res;
    }

    // Refused by TYPE for node-specific reasons — see scr_cbc_unconvertible.
    var _unconv = scr_cbc_unconvertible(_sel);
    if (_unconv != "") {
        _res.reason = "CANNOT CONVERT - " + _unconv;
        return _res;
    }

    // One spine position in, one out — so the run has to be unbroken. Anything
    // else would silently reorder the program.
    var _parent = _sel[0].org_parent;
    for (var _i = 0; _i < array_length(_sel); _i++) {
        if (_sel[_i].org_parent != _parent) {
            _res.reason = "SELECTION SPANS MORE THAN ONE ORG BLOCK";
            return _res;
        }
    }

    var _top = _sel[0].y;
    var _bot = _sel[array_length(_sel) - 1].y;
    var _sel_ref = _sel;
    var _gap = noone;

    with (obj_c64_node) {
        if (!is_connected)          { continue; }
        if (node_type == "INIT")    { continue; }
        if (org_parent != _parent)  { continue; }
        if (y < _top || y > _bot)   { continue; }

        var _in = false;
        for (var _j = 0; _j < array_length(_sel_ref); _j++) {
            if (_sel_ref[_j] == id) { _in = true; break; }
        }
        if (!_in) {
            _gap = id;
            break;
        }
    }

    if (_gap != noone) {
        _res.reason = "SELECTION HAS A GAP — " + string(_gap.node_type) + " IS BETWEEN SELECTED NODES";
        return _res;
    }

    _res.ok    = true;
    _res.nodes = _sel;
    return _res;
}

// =====================================================================
// Label name -> the LABEL node that owns it. The compile chain emits
// ["label", name] with no node reference at all, so a label can only be
// attributed by name.
// =====================================================================
function scr_cbc_owner_map() {
    var _m = ds_map_create();
    with (obj_c64_node) {
        if (node_type != "LABEL")              { continue; }
        if (array_length(instructions) < 1)    { continue; }
        if (array_length(instructions[0]) < 2) { continue; }
        ds_map_set(_m, string_replace_all(string(instructions[0][1]), " ", "_"), string(id));
    }
    return _m;
}

// =====================================================================
// Walk the compile output and pull out everything the selection emits —
// inline code AND any off-spine block it brackets.
//
// Returns { ok, reason, spine: [entry], reloc: [ {addr, entries} ] }
// where an entry is { m, v, lbl, sz } straight from the compile stream.
// =====================================================================
function scr_cbc_extract(_sel) {
    var _res = { ok: false, reason: "", spine: [], reloc: [], spine_bytes: 0, reloc_bytes: 0 };

    var _keys = ds_map_create();
    for (var _i = 0; _i < array_length(_sel); _i++) {
        ds_map_set(_keys, string(_sel[_i]), 1);
    }
    var _lblowner = scr_cbc_owner_map();

    global.compile_sizing_pass = true;
    var _code = scr_compile_chain();
    global.compile_sizing_pass = false;

    // Ordinary NORMAL / BRANCH nodes emit their instruction rows VERBATIM
    // (see the DEFAULT case in scr_compile_chain) — two elements, no node
    // reference — so they cannot be attributed by tag. PASS 2 of
    // scr_c64_do_update_addresses sizes them from their own instructions, so
    // pc_address is the reliable handle: a node claims the entries starting at
    // its address until another node claims one. A pc claimed twice (possible
    // across ORG blocks) is dropped rather than guessed at.
    var _pcnode = ds_map_create();
    var _pcdupe = ds_map_create();
    with (obj_c64_node) {
        if (node_type == "INIT")  { continue; }
        if (node_type == "ORG")   { continue; }
        if (node_type == "LABEL") { continue; }
        if (!is_connected)        { continue; }
        if (string_pos("MACRO_", node_type) == 1) { continue; }

        var _pk = string(pc_address);
        if (ds_map_exists(_pcnode, _pk)) {
            ds_map_set(_pcdupe, _pk, 1);
        } else {
            ds_map_set(_pcnode, _pk, string(id));
        }
    }

    var _owner   = "";      // node the stream is currently emitting for
    var _pc      = global.start_pc;
    var _pcstack = [];      // mirrors c64_new_program's org(-2) / org(-3)
    var _reloc   = noone;   // relocated section being filled, or noone
    var _seen    = false;   // have we entered the selection yet
    var _left    = false;   // …and come back out again

    for (var _c = 0; _c < array_length(_code); _c++) {
        var _e = _code[_c];
        if (array_length(_e) < 1) { continue; }

        var _m = string_lower(string(_e[0]));
        if (_m == "_node_ref_" || _m == "const" || _m == "_line_map_" || _m == "") { continue; }

        var _v = 0;
        if (array_length(_e) > 1) { _v = _e[1]; }
        var _lbl = "";
        if (is_string(_v) && _v != "" && _v != "0") {
            _lbl = _v;
            _v   = 0;
        }

        // Hundreds of operands in the compile chain are built from bitwise
        // expressions (`_scr_base & 0xFF00`), so they arrive as int64 — and
        // is_real() is FALSE for an int64. scr_format_asm() gates on is_real(),
        // so an unflattened operand rendered as "STA $0000,X", which the parser
        // then read back as sta_zpx: _asm_resolve_mode picks zero page by VALUE
        // (_v <= 0xFF), not by digit count. That is exactly the
        // "sta_zpx:0 vs sta_abx:1024" the verifier refused to accept.
        _v = scr_show_code_num(_v);

        // ---- ORG: relocation and the PC save/restore markers ----
        if (_m == "org") {
            var _o = _v;
            if (is_string(_o)) { _o = real(_o); }

            if (_o == -2) {
                array_push(_pcstack, _pc);
                continue;
            }
            if (_o == -3) {
                if (array_length(_pcstack) > 0) { _pc = array_pop(_pcstack); }
                _reloc = noone;
                continue;
            }

            _pc = _o;

            // A BRACKETED org — one sitting inside org -2 / org -3 — is a macro
            // relocating its own data table, and that data belongs to whoever
            // is currently emitting. A BARE org is structural: an ORG node, or
            // the ASSET EXPORT pass that scr_compile_chain runs immediately
            // after the node walk with nothing pushed in between.
            //
            // Ownership must not survive a bare org. _owner is sticky, so a
            // selection that happened to be the last thing emitting still owned
            // it when the asset export began — every exported asset then had
            // its ["org", address] treated as one of the selection's own
            // relocated tables, and its bytes were swept into the code block.
            // Neither safety gate could see it: the byte-count cross-check only
            // covers spine bytes (relocated ones are excluded on purpose, that
            // is how macro data tables get through), and the round trip merely
            // proves the text matches whatever was extracted.
            //
            // global.compile_sizing_pass does not suppress that export either —
            // both references to it in scr_compile_chain are dead (one behind
            // `false &&`, one commented out) — so this is the only thing
            // standing between a conversion and a block with the entire sprite
            // set baked into it.
            if (array_length(_pcstack) > 0 && ds_map_exists(_keys, _owner)) {
                _reloc = { addr: _o, entries: [] };
                array_push(_res.reloc, _reloc);
            } else {
                _reloc = noone;
                if (array_length(_pcstack) == 0) {
                    _owner = "";
                }
            }
            continue;
        }

        // ---- who owns this entry ----
        var _tagged = false;
        if (array_length(_e) > 2) {
            var _tag = _e[2];
            if (!is_string(_tag) && _tag != noone) {
                if (instance_exists(_tag)) {
                    _owner  = string(_tag);
                    _tagged = true;
                }
            }
        }

        if (!_tagged) {
            if (_m == "label") {
                // A label names what follows it and carries no tag. An ADDRESS
                // LABEL node's label is matched by name; a macro's own
                // scaffolding label rides on whatever the stream was emitting.
                if (ds_map_exists(_lblowner, _lbl)) {
                    _owner = ds_map_find_value(_lblowner, _lbl);
                }
            } else if (_reloc == noone) {
                var _pk2 = string(_pc);
                if (ds_map_exists(_pcnode, _pk2) && !ds_map_exists(_pcdupe, _pk2)) {
                    _owner = ds_map_find_value(_pcnode, _pk2);
                }
            }
        }

        var _mine = ds_map_exists(_keys, _owner);

        if (_mine) {
            if (_left) {
                ds_map_destroy(_keys);
                ds_map_destroy(_lblowner);
                ds_map_destroy(_pcnode);
                ds_map_destroy(_pcdupe);
                _res.reason = "SELECTION IS NOT CONTIGUOUS IN THE COMPILED ORDER";
                return _res;
            }
            _seen = true;
        } else {
            if (_seen) { _left = true; }
        }

        var _sz = 0;
        if (_m == "label") {
            _sz = 0;
        } else if (_m == "byte" || _m == "byt" || _m == "byte_lab_lo" || _m == "byte_lab_hi") {
            _sz = 1;
        } else {
            _sz = obj_opCodeManager.get_size(scr_show_code_norm(_m));
            if (_sz <= 0) { continue; }
        }

        if (_mine) {
            var _entry = { m: _m, v: _v, lbl: _lbl, sz: _sz };
            if (_reloc != noone) {
                array_push(_reloc.entries, _entry);
                _res.reloc_bytes += _sz;
            } else {
                array_push(_res.spine, _entry);
                _res.spine_bytes += _sz;
            }
        }

        _pc += _sz;
    }

    ds_map_destroy(_pcnode);
    ds_map_destroy(_pcdupe);
    ds_map_destroy(_keys);
    ds_map_destroy(_lblowner);

    if (!_seen) {
        _res.reason = "THE SELECTION EMITS NO CODE";
        return _res;
    }

    _res.ok = true;
    return _res;
}

// =====================================================================
// Comparable signature for one section. Mnemonics are normalised so the
// _rep / _lab / _abs_x spellings all collapse to the same key, which is
// what makes the round-trip comparison meaningful rather than pedantic.
// =====================================================================
function scr_cbc_sig(_entries) {
    var _sig = [];
    for (var _i = 0; _i < array_length(_entries); _i++) {
        var _e = _entries[_i];
        var _m = string_lower(string(_e.m));

        if (_m == "label") {
            array_push(_sig, "L:" + string_upper(string(_e.lbl)));
            continue;
        }

        if (_m == "byt") { _m = "byte"; }
        if (_m != "byte" && _m != "byte_lab_lo" && _m != "byte_lab_hi") {
            _m = scr_show_code_norm(_m);
        }

        var _operand = "";
        if (_e.lbl != "") {
            _operand = string_upper(string(_e.lbl));
        } else {
            _operand = string(scr_show_code_num(_e.v));
        }

        array_push(_sig, _m + ":" + _operand);
    }
    return _sig;
}

// =====================================================================
// Screen-code encode, byte-for-byte identical to the .STRING branch of
// scr_parse_asm_text. Used to PROVE a run is text before emitting it as
// text — encode the candidate back and compare. If it does not match, the
// run goes out as .byte and nothing is risked on a guess.
// =====================================================================
function scr_cbc_str_encode(_txt) {
    var _out = [];
    for (var _i = 1; _i <= string_length(_txt); _i++) {
        var _b = string_ord_at(_txt, _i);
        if (_b >= 65 && _b <= 90) {
            _b -= 64;
        } else if (_b >= 97 && _b <= 122) {
            _b -= 96;
        } else if (_b == 163 || _b == 100) {
            _b = 28;
        }
        array_push(_out, scr_show_code_lo(_b));
    }
    array_push(_out, 0);
    return _out;
}

// Try to read a byte run back as text. Returns "" when it is not text, or
// when re-encoding the candidate would not reproduce the exact same bytes.
function scr_cbc_str_decode(_bytes) {
    var _n = array_length(_bytes);
    if (_n < 3)                { return ""; }   // needs content plus terminator
    if (_bytes[_n - 1] != 0)   { return ""; }   // .string always terminates

    var _txt     = "";
    var _letters = 0;

    for (var _i = 0; _i < _n - 1; _i++) {
        var _b = _bytes[_i];
        if (_b >= 1 && _b <= 26) {
            _txt += chr(64 + _b);
            _letters += 1;
        } else if (_b >= 32 && _b <= 63) {
            // Space, digits and punctuation pass through BOTH encoders
            // untouched, so they decode straight back to themselves. This is
            // what lets "FARTIES00" come out as .string rather than ten hex
            // bytes — the digits were the only thing stopping it.
            _txt += chr(_b);
        } else {
            return "";
        }
    }

    if (_letters < 2)                  { return ""; }
    if (string_pos("\"", _txt) > 0)     { return ""; }

    // Prove it: re-encode and compare.
    var _back = scr_cbc_str_encode(_txt);
    if (array_length(_back) != _n) { return ""; }
    for (var _c = 0; _c < _n; _c++) {
        if (_back[_c] != _bytes[_c]) { return ""; }
    }

    return _txt;
}

// =====================================================================
// Assets the selection depends on that nothing else will keep alive.
//
// A TEXT_DATA asset is exported only because a live MACRO_PRINT in ASSET mode
// marks it used (scr_compile_chain, the _used_str gathering pass). Convert that
// node away and the asset silently drops out of the build — the block is left
// reading empty memory at $2000, which is exactly the "did not print anything"
// case. Same shape for CHAR_SET, MAP_DATA, SPRITE_SET and the rest.
//
// Returns [ { name, addr, size, kind } ] — kind "text" is offered for inlining,
// kind "keep" is declared with an // @asset line and left where it is.
// =====================================================================
function scr_cbc_asset_deps(_sel) {
    var _out  = [];
    var _seen = ds_map_create();

    for (var _i = 0; _i < array_length(_sel); _i++) {
        var _n = _sel[_i];
        if (!instance_exists(_n))              { continue; }
        if (array_length(_n.instructions) < 1) { continue; }

        var _row  = _n.instructions[0];
        var _type = string(_n.node_type);

        // Names this node is the ONLY thing vouching for. Every one of these
        // gates an export in scr_compile_chain's _used_* pass, so converting
        // the node away drops the asset out of the build and the block reads
        // empty memory — the same failure as the lost PRINT text, just wearing
        // a different node type.
        //
        // MACRO_SID and BYTE_DATA_NODE are deliberately absent: SID_MUSIC,
        // SID_SFX, BYTE_DATA and LINE_COLL are pushed into _all_assets
        // unconditionally, so their _used_* maps are collected and never
        // consulted. Nothing to preserve.
        var _keep = [];

        // Only TEXT_DATA behind a MACRO_PRINT is offered for inlining — it is
        // the one whose bytes we know how to re-emit as .string and prove by
        // round trip. Everything else is declared and left where it is.
        var _text = "";

        if (_type == "MACRO_PRINT") {
            var _mode_p = 0;
            if (array_length(_row) > 9 && is_real(_row[9])) {
                _mode_p = real(_row[9]);
            }
            if (_mode_p == 1 && array_length(_row) > 10) {
                _text = string(_row[10]);
            }
        } else if (_type == "MACRO_SPR" || _type == "MACRO_CHR"
                || _type == "MACRO_SFX" || _type == "MACRO_BMP") {
            if (array_length(_row) > 1) {
                array_push(_keep, string(_row[1]));
            }
        } else if (_type == "MACRO_MAP") {
            // The map itself, plus the charset the MAP_DATA asset names —
            // scr_compile_chain marks that one on the map's behalf, so it is
            // orphaned by the same conversion.
            if (array_length(_row) > 1) {
                var _map_name = string(_row[1]);
                array_push(_keep, _map_name);
                var _map_a = scr_cbc_find_asset(_map_name);
                if (!is_undefined(_map_a)) {
                    if (variable_struct_exists(_map_a, "meta")) {
                        if (variable_struct_exists(_map_a.meta, "chr_asset")) {
                            array_push(_keep, string(_map_a.meta.chr_asset));
                        }
                    }
                }
            }
        } else if (_type == "MACRO_TEXT_SCROLL") {
            if (array_length(_row) > 13) {
                array_push(_keep, string(_row[13]));
            }
            var _mode_s = 0;
            if (array_length(_row) > 9 && is_real(_row[9])) {
                _mode_s = real(_row[9]);
            }
            if (_mode_s == 1 && array_length(_row) > 10) {
                // Declared rather than offered for inlining: the scroll macro
                // reads this at runtime and I have not traced its layout the
                // way I traced MACRO_PRINT's. Keeping the asset is correct and
                // loses nothing.
                array_push(_keep, string(_row[10]));
            }
        } else if (_type == "MACRO_LOADER") {
            // Slot 1 is the LOAD_ORG manifest, which is not a binary asset.
            // Slot 2 is the linked file, which is.
            if (array_length(_row) > 2) {
                array_push(_keep, string(_row[2]));
            }
        } else if (_type == "NEW_STR") {
            var _mode_v = 0;
            if (array_length(_row) > 4 && is_real(_row[4])) {
                _mode_v = real(_row[4]);
            }
            if (_mode_v == 1 && array_length(_row) > 5) {
                array_push(_keep, string(_row[5]));
            }
        }

        // ---- declared dependencies ----
        for (var _k = 0; _k < array_length(_keep); _k++) {
            var _kn = _keep[_k];
            if (_kn == "")                    { continue; }
            if (ds_map_exists(_seen, _kn))    { continue; }
            // An @asset line for a name that is not an asset would be silently
            // skipped by the reader, but writing one is still noise.
            if (is_undefined(scr_cbc_find_asset(_kn))) { continue; }
            ds_map_set(_seen, _kn, 1);
            array_push(_out, { name: _kn, addr: 0, size: 0, kind: "keep" });
        }

        // ---- promptable TEXT_DATA ----
        if (_text != "" && !ds_map_exists(_seen, _text)) {
            var _addr = 0;
            var _size = 0;
            var _ta   = scr_cbc_find_asset(_text);
            if (!is_undefined(_ta)) {
                if (_ta.type == "TEXT_DATA") {
                    _addr = _ta.address;
                    if (buffer_exists(_ta.buffer)) {
                        _size = buffer_get_size(_ta.buffer);
                    }
                }
            }
            ds_map_set(_seen, _text, 1);
            array_push(_out, { name: _text, addr: _addr, size: _size, kind: "text" });
        }
    }

    ds_map_destroy(_seen);
    return _out;
}

// =====================================================================
// Asset by name, or undefined. One lookup instead of the four hand-rolled
// walks this file used to carry.
// =====================================================================
function scr_cbc_find_asset(_name) {
    if (!instance_exists(obj_asset_manager)) {
        return undefined;
    }
    var _am = obj_asset_manager;
    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
        var _a = ds_list_find_value(_am.asset_list, _ai);
        if (!is_struct(_a))   { continue; }
        if (_a.name == _name) { return _a; }
    }
    return undefined;
}

// =====================================================================
// GATE 3 — removing this selection must not change what any OTHER node emits.
//
// Gates 1 and 2 both measure the SELECTION: one proves extraction == selection,
// the other proves text == extraction. Neither can see a node OUTSIDE the
// selection whose own output depends on a selected node still existing — and
// scr_compile_chain is full of those. MACRO_SID, for one, scans the workspace
// for a live MACRO_TEXT_SCROLL and, if it finds one, emits twelve bytes of
// raster chain into its OWN stream:
//
//     lda_lab_lo ts<id>_scroll / sta_abs $0314
//     lda_lab_hi ts<id>_scroll / sta_abs $0315
//
// Convert the scroll away and the SID silently stops emitting that. The block
// still defines ts<id>_scroll, but nothing points $0314 at it any more, so the
// scroll never runs — a program that assembles cleanly and behaves differently,
// which is precisely what this feature must never produce. There are dozens of
// scans of that shape across the emission path, so a hardcoded list of
// dangerous pairs would never stay complete.
//
// So this measures it instead: compile once as things stand, hide the selection
// exactly the way conversion will, compile again, and compare every row TAGGED
// TO A NODE THAT IS NOT IN THE SELECTION. If one of those rows moved, changed
// or disappeared, the conversion is not neutral and we refuse.
//
// Untagged rows are deliberately excluded. The asset export tail is untagged
// and DOES legitimately change — the // @asset lines that keep those assets
// alive live in a block that does not exist yet at this point, so counting them
// would refuse every conversion that has an asset dependency.
// =====================================================================
function scr_cbc_outside_sig(_code, _keys) {
    var _sig = [];

    for (var _i = 0; _i < array_length(_code); _i++) {
        var _e = _code[_i];
        if (array_length(_e) < 3) { continue; }

        var _tag = _e[2];
        if (is_string(_tag))        { continue; }
        if (_tag == noone)          { continue; }
        if (!instance_exists(_tag)) { continue; }

        var _k = string(_tag);
        if (ds_map_exists(_keys, _k)) { continue; }

        var _m = string_lower(string(_e[0]));

        var _v = "";
        if (array_length(_e) > 1) {
            if (is_string(_e[1])) {
                _v = string_upper(string(_e[1]));
            } else {
                _v = string(scr_show_code_num(_e[1]));
            }
        }

        array_push(_sig, _k + "|" + string(_tag.node_type) + "|" + _m + ":" + _v);
    }

    return _sig;
}

// Pull the node type back out of a signature entry, for the message.
function scr_cbc_sig_type(_entry) {
    var _parts = string_split(string(_entry), "|");
    if (array_length(_parts) > 1) {
        return _parts[1];
    }
    return "ANOTHER NODE";
}

/// @return "" when the removal is neutral, otherwise the reason to refuse.
function scr_cbc_side_effects(_sel) {
    var _keys = ds_map_create();
    for (var _i = 0; _i < array_length(_sel); _i++) {
        ds_map_set(_keys, string(_sel[_i]), 1);
    }

    global.compile_sizing_pass = true;
    var _before = scr_compile_chain();
    global.compile_sizing_pass = false;
    var _sig_b = scr_cbc_outside_sig(_before, _keys);

    // Hide the selection the way conversion will. is_connected alone is not
    // enough — plenty of these scans test node_type without it — so the type
    // goes too, and both are restored in a finally so a macro that throws with
    // its partner missing cannot leave the project mangled.
    var _saved = [];
    for (var _s = 0; _s < array_length(_sel); _s++) {
        var _n = _sel[_s];
        if (!instance_exists(_n)) { continue; }
        array_push(_saved, { node: _n, conn: _n.is_connected, type: _n.node_type });
    }

    var _sig_a = [];
    var _err   = "";

    try {
        for (var _h = 0; _h < array_length(_saved); _h++) {
            _saved[_h].node.is_connected = false;
            _saved[_h].node.node_type    = "CBC_HIDDEN";
        }
        global.compile_sizing_pass = true;
        var _after = scr_compile_chain();
        global.compile_sizing_pass = false;
        _sig_a = scr_cbc_outside_sig(_after, _keys);
    } catch (_ex) {
        _err = "CONVERT ABANDONED — the program does not compile with this\nselection removed, so the conversion cannot be shown to be\nsafe.\n\nNothing has been changed.";
    } finally {
        for (var _h2 = 0; _h2 < array_length(_saved); _h2++) {
            _saved[_h2].node.is_connected = _saved[_h2].conn;
            _saved[_h2].node.node_type    = _saved[_h2].type;
        }
        global.compile_sizing_pass = false;
    }

    ds_map_destroy(_keys);

    if (_err != "") {
        return _err;
    }

    var _nb  = array_length(_sig_b);
    var _na  = array_length(_sig_a);
    var _lim = min(_nb, _na);

    for (var _c = 0; _c < _lim; _c++) {
        if (_sig_b[_c] != _sig_a[_c]) {
            return scr_cbc_side_effect_msg(scr_cbc_sig_type(_sig_b[_c]));
        }
    }

    if (_nb != _na) {
        var _which = "";
        if (_nb > _na) {
            _which = _sig_b[_lim];
        } else {
            _which = _sig_a[_lim];
        }
        return scr_cbc_side_effect_msg(scr_cbc_sig_type(_which));
    }

    return "";
}

function scr_cbc_side_effect_msg(_type) {
    return "CONVERT ABANDONED — " + string(_type) + " changes what it emits\n"
         + "when this selection is removed, so the converted program\n"
         + "would not behave the same.\n\n"
         + "That node builds part of its own code by looking for one of\n"
         + "the nodes you selected. Select it as well and convert them\n"
         + "together, and the dependency is captured in the block.\n\n"
         + "Nothing has been changed.";
}

// =====================================================================
// Data that scr_node_build_inject() pokes straight into the built PRG,
// scanning live nodes — it never passes through scr_compile_chain at all.
//
// MACRO_PRINT in INLINE mode is the one that bites: its message is written at
// BUILD time from instructions[0][5] to the address in [6]. Those bytes are not
// in the compile stream, so the extractor cannot see them, and converting the
// node away loses the text with nothing to warn you. That is the "FARTS never
// arrives at $2000" case.
//
// Encoded here with scr_cbc_str_encode, which is byte-identical to the parser's
// .STRING branch, so the run renders straight back out as .string "FARTS".
//
// Returns [ { addr, text, bytes } ].
// =====================================================================
function scr_cbc_inline_text(_sel) {
    var _out = [];

    for (var _i = 0; _i < array_length(_sel); _i++) {
        var _n = _sel[_i];
        if (!instance_exists(_n))              { continue; }
        if (_n.node_type != "MACRO_PRINT")     { continue; }
        if (array_length(_n.instructions) < 1) { continue; }

        var _row = _n.instructions[0];

        // Asset mode is handled separately by scr_cbc_asset_deps.
        var _mode = 0;
        if (array_length(_row) > 9 && is_real(_row[9])) { _mode = real(_row[9]); }
        if (_mode == 1) { continue; }

        var _txt = "";
        if (array_length(_row) > 5) { _txt = string(_row[5]); }
        if (_txt == "") { continue; }

        var _addr = 8192;
        if (array_length(_row) > 6 && is_real(_row[6])) { _addr = real(_row[6]); }

        array_push(_out, { addr: _addr, text: _txt, bytes: scr_cbc_str_encode(_txt) });
    }

    return _out;
}

// =====================================================================
// Sections -> code block text.
// =====================================================================
function scr_cbc_render(_ex, _deps) {
    var _txt = "// ---------------------------------------------\n";
    _txt += "// CONVERTED FROM NODES — C64 DEV MACHINE\n";
    _txt += "// ---------------------------------------------\n";

    // Declared dependencies keep the asset in the build now that the node that
    // referenced it is gone. scr_compile_chain reads these.
    for (var _d = 0; _d < array_length(_deps); _d++) {
        _txt += "// @asset " + _deps[_d].name + "\n";
    }

    _txt += scr_cbc_render_section(_ex.spine);

    // Relocated blocks go last, bracketed by .pcsave / .pcrestore.
    //
    // The bracket is not optional. A bare .pc is one-way — pc_override stays
    // put — so without the restore every node BELOW this block on the spine
    // would assemble at the relocated address instead of its own. An RTS node
    // placed after the block would be written to $200A and never execute.
    var _any_reloc = false;
    for (var _rc = 0; _rc < array_length(_ex.reloc); _rc++) {
        if (array_length(_ex.reloc[_rc].entries) > 0) { _any_reloc = true; break; }
    }
    if (_any_reloc) {
        _txt += "\n.pcsave\n";
    }

    for (var _r = 0; _r < array_length(_ex.reloc); _r++) {
        var _rl = _ex.reloc[_r];
        if (array_length(_rl.entries) < 1) { continue; }

        var _h = string_upper(decimal_to_hex(scr_show_code_wrap16(_rl.addr)));
        while (string_length(_h) < 4) { _h = "0" + _h; }

        _txt += "\n// ---- relocated data ----\n";
        _txt += ".pc $" + _h + "\n";
        _txt += scr_cbc_render_section(_rl.entries);
    }

    if (_any_reloc) {
        _txt += ".pcrestore\n";
    }

    return _txt;
}

function scr_cbc_render_section(_entries) {
    var _txt   = "";
    var _bytes = [];

    for (var _i = 0; _i < array_length(_entries); _i++) {
        var _e = _entries[_i];
        var _m = string_lower(string(_e.m));

        var _is_byte = (_m == "byte" || _m == "byt" || _m == "byte_lab_lo" || _m == "byte_lab_hi");

        // Byte runs pack onto shared .byte lines; flush the run before
        // anything that is not another byte.
        if (!_is_byte && array_length(_bytes) > 0) {
            _txt  += scr_cbc_flush_bytes(_bytes);
            _bytes = [];
        }

        if (_m == "label") {
            _txt += string(_e.lbl) + ":\n";
            continue;
        }

        if (_is_byte) {
            if (_e.lbl != "") {
                // A pointer byte — <LABEL / >LABEL keeps the reference alive.
                _txt += scr_cbc_flush_bytes(_bytes);
                _bytes = [];
                if (string_pos("_lab_hi", _m) > 0) {
                    _txt += ".byte >" + string(_e.lbl) + "\n";
                } else {
                    _txt += ".byte <" + string(_e.lbl) + "\n";
                }
            } else {
                array_push(_bytes, scr_show_code_lo(_e.v));
            }
            continue;
        }

        if (_e.lbl != "") {
            _txt += scr_format_asm_label(_m, string(_e.lbl)) + "\n";
        } else {
            _txt += scr_format_asm(_m, _e.v) + "\n";
        }
    }

    if (array_length(_bytes) > 0) {
        _txt += scr_cbc_flush_bytes(_bytes);
    }

    return _txt;
}

function scr_cbc_flush_bytes(_bytes) {
    var _txt = "";
    var _n   = array_length(_bytes);

    // MACRO_PRINT and friends park their message as inline bytes. If the run
    // reads back as text — and re-encodes to exactly the same bytes — emit it
    // as .string so the block stays editable as words rather than hex.
    var _as_text = scr_cbc_str_decode(_bytes);
    if (_as_text != "") {
        return ".string \"" + _as_text + "\"\n";
    }

    var _i = 0;

    while (_i < _n) {
        var _line = ".byte ";
        var _c    = 0;
        while (_i < _n && _c < 16) {
            if (_c > 0) { _line += ","; }
            var _h = string_upper(decimal_to_hex(scr_show_code_lo(_bytes[_i])));
            while (string_length(_h) < 2) { _h = "0" + _h; }
            _line += "$" + _h;
            _i += 1;
            _c += 1;
        }
        _txt += _line + "\n";
    }

    return _txt;
}

// =====================================================================
// Round trip: assemble the generated text and prove it matches.
// =====================================================================
function scr_cbc_verify(_txt, _ex) {
    var _parsed = scr_parse_asm_text(_txt);

    // Re-split the parsed stream the same way the extractor split the
    // original: everything before the first .pc is spine, each .pc opens a
    // new relocated section.
    var _spine = [];
    var _reloc = [];
    var _cur   = noone;

    for (var _i = 0; _i < array_length(_parsed); _i++) {
        var _p = _parsed[_i];
        if (array_length(_p) < 1) { continue; }
        var _m = string_lower(string(_p[0]));

        if (_m == "comment" || _m == "const" || _m == "_line_map_" || _m == "") { continue; }

        var _v = 0;
        if (array_length(_p) > 1) { _v = _p[1]; }
        var _lbl = "";
        if (is_string(_v) && _v != "" && _v != "0") {
            _lbl = _v;
            _v   = 0;
        }

        if (_m == "pc" || _m == "org") {
            var _a = _v;
            if (is_string(_a)) { _a = real(_a); }

            // -2 / -3 are the save / restore markers, not addresses.
            if (_a == -2) { continue; }
            if (_a == -3) {
                _cur = noone;
                continue;
            }

            _cur = { addr: _a, entries: [] };
            array_push(_reloc, _cur);
            continue;
        }

        // A .byte or .string line comes back as ONE entry carrying every byte
        // it declared — ["byte", b1, b2, b3, …] — whereas the compile stream
        // emits one entry per byte. Without expanding here, any run longer
        // than a single byte fails the length check and the whole conversion
        // is refused: which is exactly what a MACRO_PRINT message would do.
        if (_m == "byte" || _m == "byt") {
            if (array_length(_p) > 1 && _lbl == "") {
                for (var _bi = 1; _bi < array_length(_p); _bi++) {
                    var _be = { m: "byte", v: _p[_bi], lbl: "", sz: 1 };
                    if (_cur != noone) {
                        array_push(_cur.entries, _be);
                    } else {
                        array_push(_spine, _be);
                    }
                }
                continue;
            }
        }

        var _entry = { m: _m, v: _v, lbl: _lbl, sz: 0 };
        if (_cur != noone) {
            array_push(_cur.entries, _entry);
        } else {
            array_push(_spine, _entry);
        }
    }

    // ---- compare ----
    var _a_sig = scr_cbc_sig(_ex.spine);
    var _b_sig = scr_cbc_sig(_spine);

    if (array_length(_a_sig) != array_length(_b_sig)) {
        return "SPINE LENGTH " + string(array_length(_b_sig)) + " vs " + string(array_length(_a_sig));
    }
    for (var _s = 0; _s < array_length(_a_sig); _s++) {
        if (_a_sig[_s] != _b_sig[_s]) {
            return "SPINE LINE " + string(_s + 1) + ": " + _b_sig[_s] + " vs " + _a_sig[_s];
        }
    }

    // Empty relocated sections are dropped by the renderer, so compare only
    // the ones that actually made it into the text.
    var _want = [];
    for (var _r = 0; _r < array_length(_ex.reloc); _r++) {
        if (array_length(_ex.reloc[_r].entries) > 0) {
            array_push(_want, _ex.reloc[_r]);
        }
    }

    if (array_length(_want) != array_length(_reloc)) {
        return "RELOCATED BLOCK COUNT " + string(array_length(_reloc)) + " vs " + string(array_length(_want));
    }

    for (var _r2 = 0; _r2 < array_length(_want); _r2++) {
        if (scr_show_code_wrap16(_want[_r2].addr) != scr_show_code_wrap16(_reloc[_r2].addr)) {
            return "RELOCATED BLOCK " + string(_r2 + 1) + " ADDRESS MISMATCH";
        }
        var _c_sig = scr_cbc_sig(_want[_r2].entries);
        var _d_sig = scr_cbc_sig(_reloc[_r2].entries);
        if (array_length(_c_sig) != array_length(_d_sig)) {
            return "RELOCATED BLOCK " + string(_r2 + 1) + " LENGTH " + string(array_length(_d_sig)) + " vs " + string(array_length(_c_sig));
        }
        for (var _s2 = 0; _s2 < array_length(_c_sig); _s2++) {
            if (_c_sig[_s2] != _d_sig[_s2]) {
                return "RELOCATED BLOCK " + string(_r2 + 1) + " LINE " + string(_s2 + 1) + ": " + _d_sig[_s2] + " vs " + _c_sig[_s2];
            }
        }
    }

    return "";   // empty string == verified
}

// =====================================================================
// The whole operation. Nothing is destroyed unless the round trip passed.
// =====================================================================
function scr_cbc_convert() {
    var _val = scr_cbc_validate();
    if (!_val.ok) {
        scr_show_message(_val.reason);
        return false;
    }

    var _sel = _val.nodes;
    var _ex  = scr_cbc_extract(_sel);
    if (!_ex.ok) {
        scr_show_message("CONVERT FAILED\n\n" + _ex.reason);
        return false;
    }

    // Independent cross-check on a different data path: PASS 2 of
    // scr_c64_do_update_addresses sizes every node from its own instructions,
    // with no reference to the compile stream. If the extraction swallowed a
    // neighbour or missed one of ours, these two numbers disagree. The round
    // trip below only proves text == extraction; this is what proves
    // extraction == selection.
    var _want_bytes = 0;
    for (var _b = 0; _b < array_length(_sel); _b++) {
        _want_bytes += _sel[_b].total_node_size;
    }
    if (_want_bytes != _ex.spine_bytes) {
        scr_show_message("CONVERT ABANDONED — extracted " + string(_ex.spine_bytes)
            + " inline bytes but the selection reports " + string(_want_bytes)
            + ".\n\nNothing has been changed.");
        return false;
    }

    // ---- GATE 3: does anything OUTSIDE the selection depend on it? ----
    // Runs before the data prompts so a doomed conversion is refused without
    // asking questions first.
    var _side = scr_cbc_side_effects(_sel);
    if (_side != "") {
        scr_show_message(_side);
        return false;
    }

    // ---- inline PRINT text: the block has to carry it, there is nowhere
    // ---- else for it to live once the node is gone ----
    var _inl = scr_cbc_inline_text(_sel);
    for (var _t = 0; _t < array_length(_inl); _t++) {
        var _it = _inl[_t];
        var _ie = [];
        for (var _ib = 0; _ib < array_length(_it.bytes); _ib++) {
            array_push(_ie, { m: "byte", v: _it.bytes[_ib], lbl: "", sz: 1 });
        }
        array_push(_ex.reloc, { addr: _it.addr, entries: _ie });
    }

    // ---- asset-mode dependencies: inline the data, or keep the asset ----
    var _deps_all  = scr_cbc_asset_deps(_sel);
    var _deps_keep = [];

    for (var _d = 0; _d < array_length(_deps_all); _d++) {
        var _dp = _deps_all[_d];

        // Sprite sets, charsets, maps, bitmaps, SFX and scroll text are
        // declared, not offered — there is no prompt to answer. Only TEXT_DATA
        // behind a MACRO_PRINT can be re-emitted as .string and proved by the
        // round trip, so only that one asks.
        if (_dp.kind != "text") {
            array_push(_deps_keep, _dp);
            continue;
        }

        var _dhex = scr_show_code_hex(_dp.addr, 4);

        var _q = "TEXT DATA \"" + _dp.name + "\"  ($" + _dhex + ", "
               + string(_dp.size) + " bytes)\n\n"
               + "Bring it INTO the code block as .string data?\n\n"
               + "YES  -  inlined at $" + _dhex + ", block is self-contained\n"
               + "NO   -  keep the TEXT_DATA asset (a // @asset line is written\n"
               + "        so it stays in the build)";

        var _inline = scr_show_question_bool(_q);
        io_clear();

        if (_inline) {
            var _entries = [];
            if (instance_exists(obj_asset_manager)) {
                var _am_i = obj_asset_manager;
                for (var _ai_i = 0; _ai_i < ds_list_size(_am_i.asset_list); _ai_i++) {
                    var _a_i = ds_list_find_value(_am_i.asset_list, _ai_i);
                    if (_a_i.type != "TEXT_DATA") { continue; }
                    if (_a_i.name != _dp.name)    { continue; }

                    // Same defensive flush the compile chain does, so the
                    // buffer holds screencodes rather than raw ASCII.
                    scr_asset_text_flush(_a_i);

                    if (buffer_exists(_a_i.buffer)) {
                        var _bsz = buffer_get_size(_a_i.buffer);
                        for (var _bi = 0; _bi < _bsz; _bi++) {
                            array_push(_entries, {
                                m: "byte",
                                v: buffer_peek(_a_i.buffer, _bi, buffer_u8),
                                lbl: "",
                                sz: 1
                            });
                        }
                    }
                    break;
                }
            }

            if (array_length(_entries) < 1) {
                scr_show_message("CONVERT ABANDONED — could not read the bytes of\nTEXT DATA \"" + _dp.name + "\".\n\nNothing has been changed.");
                return false;
            }

            array_push(_ex.reloc, { addr: _dp.addr, entries: _entries });
        } else {
            array_push(_deps_keep, _dp);
        }
    }

    var _txt  = scr_cbc_render(_ex, _deps_keep);
    var _fail = scr_cbc_verify(_txt, _ex);

    if (_fail != "") {
        // The generated text does not assemble to the same bytes. Say so and
        // change nothing — a silently different program is far worse than a
        // refused conversion.
        show_debug_message("CONVERT TO CODE BLOCK — VERIFY FAILED: " + _fail);
        show_debug_message("---- generated text ----\n" + _txt);
        scr_show_message("CONVERT ABANDONED — the generated block does not\nassemble to the same bytes.\n\n" + _fail + "\n\nNothing has been changed. The full text is in the\ndebug log.");
        return false;
    }

    var _count = array_length(_sel);

    // ---- commit ----
    // The engine's undo model banks a snapshot when an edit SETTLES: Step_0
    // sees global.undo_dirty, runs scr_c64_do_update_addresses() and then
    // scr_undo_snapshot(). Snapshotting here as well would push the
    // pre-change state a second time and cost an extra, dead CTRL+Z press.
    //
    // So: if there is an unsettled edit outstanding, settle it first so the
    // pre-conversion state is genuinely on the stack, then let the normal
    // path record the post-conversion tip. Redo then works for free, because
    // the tip is written by the same code path as every other edit.
    if (global.undo_dirty) {
        scr_c64_do_update_addresses();
        scr_undo_snapshot();
        global.undo_dirty = false;
    }

    var _ax     = _sel[0].x;
    var _ay     = _sel[0].y;
    var _parent = _sel[0].org_parent;

    for (var _i = 0; _i < array_length(_sel); _i++) {
        if (instance_exists(_sel[_i])) {
            instance_destroy(_sel[_i]);
        }
    }

    var _cb = scr_node_spawn("MACRO_CODE", _ax, _ay);
    _cb.instructions[0][1] = _txt;
    _cb.is_connected       = true;
    _cb.org_parent         = _parent;
    _cb.height_dirty       = true;
    with (_cb) { event_user(0); }

    global.selected_nodes = [];

    // Everything the delete path and the settle block care about.
    with (obj_c64_node) {
        stats_cache_dirty   = true;
        height_dirty        = true;
        overlap_check_dirty = true;
        last_overlap_check  = false;
    }
    obj_workspace_manager.flow_overlay_dirty = true;

    // Marking dirty rather than calling the update directly is what hands the
    // undo snapshot to Step_0's settle block — see the note above. It also
    // re-packs the spine, which is what closes the gap the deleted nodes left.
    global.addresses_dirty = true;
    global.undo_dirty      = true;
    global.autosave_dirty  = true;

    scr_show_message("CONVERTED " + string(_count) + " NODES TO A CODE BLOCK");
    return true;
}

// =====================================================================
// Button geometry — one definition, used by the Begin Step hit test and by
// the Draw pass, so they cannot disagree.
// =====================================================================
/// @function scr_cbc_message_rect(_txt)
/// @desc The floating plate this feature speaks from — the CONVERT button, the
///       reason it is refusing, and anything else that wants the same spot.
///
/// It was a fixed 260x34 box with the text drawn centred inside it, which is
/// fine for "CONVERT TO CODE" and useless for the messages that actually
/// matter: "SELECTION HAS A GAP — MACRO_MAP IS BETWEEN SELECTED NODES" ran off
/// both ends, so the one line telling you WHY nothing happened was the one line
/// you could not read. The plate now grows to whatever it is given, and handles
/// multi-line text, with 260x34 as the floor so the button itself is unchanged.
///
/// string_width needs the font that will actually draw the text, so this sets
/// fnt_C64_Angled and puts the previous font back — it is called from Begin
/// Step for the hit test as well as from Draw.
function scr_cbc_message_rect(_txt) {
    var _font_before = draw_get_font();
    draw_set_font(fnt_C64_Angled);

    var _lines = string_split(string(_txt), "\n");
    var _tw    = 0;
    for (var _i = 0; _i < array_length(_lines); _i++) {
        _tw = max(_tw, string_width(_lines[_i]));
    }
    var _lh = string_height("A");
    var _th = _lh * max(1, array_length(_lines));

    draw_set_font(_font_before);

    var _gw = global.gui_w;
    var _gh = display_get_gui_height();
    var _bw = max(260, _tw + 32);
    var _bh = max(34,  _th + 14);

    return {
        x: floor((_gw - _bw) / 2),
        y: floor(_gh * 0.8),
        w: _bw,
        h: _bh
    };
}

// The clickable button is always the plain label, so the hit rect stays the
// size of the button and does not swell with a refusal message — which is
// correct, because a refusal is not clickable in the first place.
function scr_cbc_button_rect() {
    return scr_cbc_message_rect("CONVERT TO CODE");
}

// =====================================================================
// BEGIN STEP hit test.
//
// This has to run before the Step events, not during Draw. The workspace
// clears global.selected_nodes on any left click that is not over GUI — so
// if the button only became "hot" during Draw, the very click that pressed
// it would already have emptied the selection it was meant to act on.
// =====================================================================
function scr_cbc_hit() {
    global.cbc_button_hot = false;

    if (global.lite)                             { exit; }
    if (!instance_exists(obj_workspace_manager)) { exit; }
    // An imported block riding the pointer speaks from this same spot, so the
    // button stands down rather than drawing over it.
    if (global.code_import_node != noone)        { exit; }

    with (obj_workspace_manager) {
        if (hideui)              { exit; }
        if (gui_menu_open != -1) { exit; }
        if (is_entering_text)    { exit; }
        if (global.showcode_mouse_over) { exit; }
        if (array_length(global.selected_nodes) < 1) { exit; }

        var _r  = scr_cbc_button_rect();
        var _mx = global.gui_mouse_x;
        var _my = global.gui_mouse_y;

        if (_mx >= _r.x && _mx < _r.x + _r.w && _my >= _r.y && _my < _r.y + _r.h) {
            global.cbc_button_hot = true;
        }
    }
}

// =====================================================================
// Floating CONVERT TO CODE button — appears once a selection exists.
// Call from obj_workspace_manager's Draw GUI event.
// =====================================================================
function scr_cbc_draw_button() {
    if (global.lite)                             { exit; }
    if (!instance_exists(obj_workspace_manager)) { exit; }
    if (global.code_import_node != noone)        { exit; }

    var _do_convert = false;

    with (obj_workspace_manager) {
        if (hideui)              { exit; }
        if (gui_menu_open != -1) { exit; }
        if (is_entering_text)    { exit; }
        if (global.showcode_mouse_over) { exit; }
        if (array_length(global.selected_nodes) < 1) { exit; }

        var _val = scr_cbc_validate();
        var _hv  = global.cbc_button_hot;

        var _col = make_color_rgb(255, 210, 80);
        var _lbl = "CONVERT TO CODE";
        if (!_val.ok) {
            _col = make_color_rgb(130, 130, 140);
            _lbl = _val.reason;
        } else if (_hv) {
            _col = c_white;
        }

        // Sized to the text that is about to be drawn, not to the button, so a
        // long refusal is readable. The HIT rect stays scr_cbc_button_rect()
        // above; only the plate under the message grows.
        var _r = scr_cbc_message_rect(_lbl);

        if (_hv && scr_cbc_primary_pressed() && _val.ok) {
            _do_convert = true;
        }

        draw_sprite_stretched(spr_glassSlice, niceSliceFrm, _r.x, _r.y, _r.w, _r.h);

        var _font_before   = draw_get_font();
        var _halign_before = draw_get_halign();
        var _valign_before = draw_get_valign();

        draw_set_font(fnt_C64_Angled);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);

        draw_set_color(_col);
        draw_rectangle(_r.x + 2, _r.y + 2, _r.x + _r.w - 2, _r.y + _r.h - 2, true);
        draw_text_transformed(_r.x + (_r.w / 2), _r.y + (_r.h / 2), _lbl, 1.0, 1.0, 0);

        draw_set_font(_font_before);
        draw_set_halign(_halign_before);
        draw_set_valign(_valign_before);
        draw_set_color(c_white);
    }

    // Kept outside the with() so the conversion — which spawns, destroys and
    // recompiles — never runs with obj_workspace_manager as `self`.
    if (_do_convert) {
        scr_cbc_convert();
    }
}

// Windows uses the raw button; the macOS port swaps the body of this one
// function for `return scr_primary_pressed();` and nothing else changes.
function scr_cbc_primary_pressed() {
    return mouse_check_button_pressed(mb_left);
}
