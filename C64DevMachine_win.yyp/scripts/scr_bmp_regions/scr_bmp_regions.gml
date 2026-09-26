/// @function scr_bmp_regions(_bmp_base)
/// @desc THE single source of truth for where a BITMAP asset's three physical
///       regions land in C64 memory. The asset injector, MACRO_BMP,
///       MACRO_MOVE_BMP_BLOCK, the memory bar and every conflict pass must
///       call this rather than recomputing the addresses themselves — that
///       duplication is exactly what let the bank-2 colour block silently
///       overrun the VIC bank into $C000+ (see below).
///
/// A KLA bitmap is NOT one contiguous 10192-byte lump. It is three blocks:
///
///   bitmap  — 8000 bytes at the base. The VIC reads this.
///   screen  — 1000 bytes at a VIC-legal 1K slot. The VIC reads this.
///   colour  — 1000 bytes of SOURCE data. The VIC NEVER reads it. MACRO_BMP
///             copies it into $D800 at startup; MACRO_MOVE_BMP_BLOCK reads
///             from it when stamping between bitmaps. So it only has to be
///             CPU-visible and unclaimed — no VIC alignment constraint at all.
///
/// Bank rules:
///   bank 0/1 : screen = bmp + $2000        colour = screen + $03E8
///   bank 2   : screen = bankbase + $3C00   colour = bmp + 8000
///   bank 3   : screen = bankbase + $0400   colour = screen + $03E8
///
/// Bank 2 is the outlier. Its screen must sit at the LAST 1K slot in the bank
/// ($BC00) because the char-ROM shadow at $9000-$9FFF blocks the usual spot.
/// Taking +$03E8 from there gives $BFE8 — and $BFE8 + 1000 = $C3D0, which is
/// 976 bytes PAST the end of the bank, straight into $C000+ where user
/// variables and BYTE_DATA assets live. The block was never written, so
/// MOVE_BMP_BLOCK read zeros and stamped colour 0 (black) into every cell it
/// copied. For bank 2 the colour block therefore goes immediately after the
/// BITMAP instead ($9F40 for a $8000 base) — that region is the VIC's char-ROM
/// shadow, but the CPU reads RAM there and only the CPU touches this block.
function scr_bmp_regions(_bmp_base) {
    var _bank  = floor(_bmp_base / 0x4000);
    var _bbase = _bank * 0x4000;

    var _scr = _bmp_base + 0x2000;
    if (_bank == 2) {
        _scr = _bbase + 0x3C00;
    }
    if (_bank == 3) {
        _scr = _bbase + 0x0400;
    }

    var _col = _scr + 0x03E8;
    if (_bank == 2) {
        _col = _bmp_base + 8000;
    }

    return {
        bank      : _bank,
        bank_base : _bbase,
        bmp_addr  : _bmp_base,
        bmp_size  : 8000,
        scr_addr  : _scr,
        scr_size  : 1000,
        col_addr  : _col,
        col_size  : 1000
    };
}

/// Mark the bitmaps a MOVE BMP BLOCK node reads from as used (ds_map name -> true):
/// any BITMAP at its SOURCE address, and the source sheet of the Bitmap
/// Builder whose record table the node uses in ASSET mode.
function scr_move_bmp_block_mark_sources(_node, _map) {
    if (!instance_exists(obj_asset_manager)) return;
    var _inst = _node.instructions[0];
    var _src  = -1;
    if (array_length(_inst) > 1 && is_real(_inst[1])) { _src = real(_inst[1]); }
    var _rec  = "";
    if (array_length(_inst) > 17) { _rec = string(_inst[17]); }
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if ((_a.type == "BITMAP" || _a.type == "BITMAP_KLA") && real(_a.address) == _src) {
            ds_map_replace(_map, _a.name, true);
        }
        if (_a.type == "BITMAP_BUILDER" && _rec != "" && is_struct(_a.meta)
            && variable_struct_exists(_a.meta, "bbd_name") && _a.meta.bbd_name == _rec
            && variable_struct_exists(_a.meta, "src_asset") && _a.meta.src_asset != "") {
            ds_map_replace(_map, _a.meta.src_asset, true);
        }
    }
}

/// The BITMAP node that is actually on screen, for code that needs the display
/// bank / screen RAM (sprite pointers). A project can hold extra BITMAP nodes
/// that never run — e.g. one parked after an RTS only to pull a Bitmap Builder
/// source sheet into the PRG — so "first connected BITMAP node" is not enough.
/// Preference: same VIC bank as _prefer_bank (pass -1 for none), then on the
/// INIT spine, then any connected BITMAP node. Returns noone if there is none.
function scr_display_bmp_node(_prefer_bank) {
    var _best = noone;
    var _best_score = -1;
    with (obj_c64_node) {
        if (node_type != "MACRO_BMP" || !is_connected) continue;
        var _a = 0x4000;
        if (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) { _a = real(instructions[0][2]); }
        var _sc = 0;
        if (_prefer_bank >= 0 && floor(_a / 0x4000) == _prefer_bank) { _sc += 2; }
        if (!instance_exists(org_parent)) { _sc += 1; }
        if (_sc > _best_score) {
            _best_score = _sc;
            _best = id;
        }
    }
    return _best;
}
