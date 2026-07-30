/// @desc Legacy CharPad CTM (v5–v8) reader. These older exports have no tile
///       system: the map holds raw char indices (1x1 chars). Structure:
///
///   header  : "CTM"(3) + version(1) + payload
///             v7 payload = 8 bytes  (first block marker at offset 12)
///             v8 payload = 10 bytes (first block marker at offset 14)
///   block b0 : char images        (u16 count-1, then (count)*8 bytes)
///   block b1 : char materials     ((count) bytes, low nibble = tile type)
///   block b? : per-char colours   (v8 only; (count) bytes, low nibble)  [OPTIONAL]
///   block bN : map data           (u16 w, u16 h, then w*h cells @ 16-bit LSBF)
///
/// Robust rule (avoids trusting old header semantics): the MAP is always the
/// LAST 0xDA,0xBn block. Any block sitting between materials and the map is the
/// per-char colour block. Everything then feeds the SAME two 1x1 builders the
/// v9 importer uses, so downstream asset creation is identical.
///
/// @param _buf          loaded buffer (caller deletes it)
/// @param _sz           buffer size
/// @param _name_stem    cleaned filename stem for asset naming
/// @param _am           obj_asset_manager
/// @param _ver          CTM version byte (5..8)
/// @param _rd_u8        function(_b,_p) -> u8   (shared reader)
/// @param _read_marker  function(_b,_p) -> pos-after-marker or -1
/// @param _imp_mc_bg    default MC background colour
/// @param _imp_mc_col1  default MC colour 1
/// @param _imp_mc_col2  default MC colour 2
function scr_import_charpad_ctm_legacy(_buf, _sz, _name_stem, _am, _ver, _rd_u8, _read_marker, _imp_mc_bg, _imp_mc_col1, _imp_mc_col2, _imp_ecm_bg3 = 3) {

    // ---- header length by version (payload after the 4-byte "CTM"+ver) ----
    // v7 first marker sits at offset 12, v8 at offset 14. Older (v5/v6) fall
    // back to a scan for the first 0xDA,0xB0 so we never mis-seek.
    var _pos = -1;
    if (_ver == 8) { _pos = 14; }
    else if (_ver == 7) { _pos = 12; }
    else {
        // Unknown-but-old: find the first char-image marker by scanning.
        for (var _scan = 4; _scan < _sz - 1; _scan++) {
            if (_rd_u8(_buf, _scan) == 0xDA && (_rd_u8(_buf, _scan + 1) & 0xF0) == 0xB0) {
                _pos = _scan;
                break;
            }
        }
        if (_pos < 0) { scr_show_message("CTM import: no blocks found (v" + string(_ver) + ")"); exit; }
    }

    // ---- collect every block offset up front so we can find the LAST one ----
    var _marker_offs = [];
    var _mm = _pos;
    while (_mm < _sz - 1) {
        if (_rd_u8(_buf, _mm) == 0xDA && (_rd_u8(_buf, _mm + 1) & 0xF0) == 0xB0) {
            array_push(_marker_offs, _mm);
        }
        _mm += 1;
    }
    var _marker_total = array_length(_marker_offs);
    if (_marker_total < 3) {
        scr_show_message("CTM import: legacy file missing blocks (found " + string(_marker_total) + ")");
        exit;
    }
    var _map_marker_off = _marker_offs[_marker_total - 1];   // map is ALWAYS last

    // ---- block b0: char images ----
    _pos = _read_marker(_buf, _pos);
    if (_pos < 0) { scr_show_message("CTM import: bad charset marker (legacy)"); exit; }
    var _charcnt = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);
    _pos += 2;
    var _char_count = _charcnt + 1;
    var _chars_arr = array_create(_char_count * 8, 0);
    for (var _bi = 0; _bi < _char_count * 8; _bi++) {
        _chars_arr[_bi] = _rd_u8(_buf, _pos + _bi);
    }
    _pos += _char_count * 8;

    // ---- block b1: char materials (tile types, low nibble) ----
    _pos = _read_marker(_buf, _pos);
    if (_pos < 0) { scr_show_message("CTM import: bad materials marker (legacy)"); exit; }
    var _mat_arr = array_create(_char_count, 0);
    for (var _mi = 0; _mi < _char_count; _mi++) {
        _mat_arr[_mi] = _rd_u8(_buf, _pos + _mi) & 0x0F;
    }
    _pos += _char_count;

    // ---- OPTIONAL per-char colour block (present when a block precedes map) ----
    // If the next marker we're at is NOT the map marker, it's the colour block.
    var _charcol_arr = -1;
    if (_pos < _map_marker_off) {
        _pos = _read_marker(_buf, _pos);
        if (_pos < 0) { scr_show_message("CTM import: bad colour marker (legacy)"); exit; }
        _charcol_arr = array_create(_char_count, 1);
        for (var _ci = 0; _ci < _char_count; _ci++) {
            _charcol_arr[_ci] = _rd_u8(_buf, _pos + _ci) & 0x0F;
        }
        _pos += _char_count;
    }

    // ---- map block (raw 1x1 char indices) ----
    // The two builders (scr_charpad_ctm_build_map / _build_meta1x1) expect _pos
    // sitting ON the map marker ($da,$bn) — they re-verify and skip it
    // themselves. So we point at the known-last marker WITHOUT advancing past
    // it. Validate the marker bytes here just to fail early with a clear msg.
    var _map_m0 = _rd_u8(_buf, _map_marker_off);
    var _map_m1 = _rd_u8(_buf, _map_marker_off + 1);
    if (_map_m0 != 0xDA || ((_map_m1 & 0xF0) != 0xB0)) {
        scr_show_message("CTM import: bad map marker (legacy)");
        exit;
    }
    _pos = _map_marker_off;

    // Derive display mode from the per-char colours if we have them: any colour
    // with bit3 set means the charset was authored multicolour. No colour block
    // (v7) -> treat as hires text. This matches the v9 char_lut convention.
    var _disp_mode = 0;   // 0 = Text_HR
    if (_charcol_arr != -1) {
        for (var _di = 0; _di < _char_count; _di++) {
            if ((_charcol_arr[_di] & 0x0F) >= 8) { _disp_mode = 1; break; }   // 1 = Text_MC
        }
    }

    // Hand off to the SAME 1x1 builders the v9 path uses. _pos now points at the
    // map dimensions (u16 w, u16 h) exactly as those builders expect.
    var _use_mapdata = scr_show_question_bool(
            "CharPad map has no tiles (1x1 chars).\n\n"
          + "Build as MAP_DATA?\n"
          + "  YES = MAP_DATA (per-cell colour freedom)\n"
          + "  NO  = 1x1 META_TILESET (chars hold colour)"
        );
    if (_use_mapdata) {
        scr_charpad_ctm_build_map(
            _buf, _sz, _pos, _name_stem, _am,
            _char_count, _chars_arr, _mat_arr, _charcol_arr,
            _disp_mode, _imp_mc_bg, _imp_mc_col1, _imp_mc_col2, _imp_ecm_bg3
        );
    } else {
        scr_charpad_ctm_build_meta1x1(
            _buf, _sz, _pos, _name_stem, _am,
            _char_count, _chars_arr, _mat_arr, _charcol_arr,
            _disp_mode, _imp_mc_bg, _imp_mc_col1, _imp_mc_col2, _imp_ecm_bg3
        );
    }
}