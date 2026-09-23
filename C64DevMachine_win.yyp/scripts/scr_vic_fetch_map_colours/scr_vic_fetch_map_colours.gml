/// @desc GET MAP COLORS on MACRO_VIC. Finds a live map source on the spine
///       (connected, or inside an ORG), then copies its mode + shared colours
///       onto the VIC node so VIC init matches what the map was painted with.
///
///       Source priority:
///         1. MACRO_METASCROLL  -> META_TILESET  (instructions[0][1])
///         2. MACRO_METAMAP     -> META_TILESET  (instructions[0][1])
///         3. MACRO_MAP         -> MAP_DATA      (instructions[0][1])
///
///       Mode comes from the linked CHAR_SET + the workspace map mode:
///         charset mc_mode 2               -> ECM  (BG0-3 from the charset)
///         map_global_mixed 1 / mc_mode 1  -> MCT  (BG0, MC1, MC2)
///         otherwise                       -> TEXT (BG0 only)
///
/// @param {Id.Instance} _vic  The MACRO_VIC node that was clicked
function scr_vic_fetch_map_colours(_vic) {

    if (!instance_exists(obj_asset_manager)) { exit; }
    var _am = obj_asset_manager;

    // ── 1. Find the live source node ──────────────────────
    var _src_node  = noone;
    var _src_kind  = "";      // "META_TILESET" or "MAP_DATA"
    var _src_types = ["MACRO_METASCROLL", "MACRO_METAMAP", "MACRO_MAP"];
    var _src_asset = ["META_TILESET",     "META_TILESET",  "MAP_DATA"];

    for (var _ti = 0; _ti < array_length(_src_types); _ti++) {
        var _want = _src_types[_ti];
        with (obj_c64_node) {
            if (_src_node != noone) { break; }
            if (node_type != _want) { continue; }
            var _live = is_connected;
            if (org_parent != noone) {
                if (instance_exists(org_parent)) { _live = true; }
            }
            if (!_live) { continue; }
            if (array_length(instructions[0]) < 2) { continue; }
            if (string(instructions[0][1]) == "") { continue; }
            _src_node = id;
        }
        if (_src_node != noone) {
            _src_kind = _src_asset[_ti];
            break;
        }
    }

    if (_src_node == noone) {
        scr_show_message(L("GET MAP COLORS: no connected MACRO METASCROLL, METAMAP or MAP with an asset set."));
        exit;
    }

    // ── 2. Resolve the map asset ──────────────────────────
    var _asset_name = string(_src_node.instructions[0][1]);
    var _map = noone;
    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
        var _a = ds_list_find_value(_am.asset_list, _ai);
        if (_a.type == _src_kind && _a.name == _asset_name) {
            _map = _a;
            break;
        }
    }
    if (_map == noone) {
        scr_show_message(L("GET MAP COLORS: asset not found - ") + _asset_name);
        exit;
    }

    // ── 3. Resolve the linked charset (optional) ──────────
    var _chr = noone;
    var _chr_name = _map.meta[$ "chr_asset"];
    if (is_string(_chr_name)) {
        if (_chr_name != "") {
            for (var _ci = 0; _ci < ds_list_size(_am.asset_list); _ci++) {
                var _ca = ds_list_find_value(_am.asset_list, _ci);
                if (_ca.type == "CHAR_SET" && _ca.name == _chr_name) {
                    _chr = _ca;
                    break;
                }
            }
        }
    }

    var _chr_mode = 0;
    if (_chr != noone) {
        var _cm = _chr.meta[$ "mc_mode"];
        if (is_real(_cm)) { _chr_mode = _cm; }
    }

    // ── 4. Pick the VIC mode ──────────────────────────────
    var _new_mode = "TEXT";
    if (_chr_mode == 2) {
        _new_mode = "ECM";
    } else if (obj_workspace_manager.map_global_mixed == 1) {
        _new_mode = "MCT";
    } else if (_chr_mode == 1) {
        _new_mode = "MCT";
    }

    // ── 5. Charset fallback colours ───────────────────────
    var _c_bg  = 0;
    var _c_mc1 = 1;
    var _c_mc2 = 2;
    var _c_e1  = 6;
    var _c_e2  = 14;
    var _c_e3  = 3;
    if (_chr != noone) {
        var _v;
        _v = _chr.meta[$ "mc_bg"];   if (is_real(_v)) { _c_bg  = _v; }
        _v = _chr.meta[$ "mc_col1"]; if (is_real(_v)) { _c_mc1 = _v; }
        _v = _chr.meta[$ "mc_col2"]; if (is_real(_v)) { _c_mc2 = _v; }
        _v = _chr.meta[$ "ecm_bg1"]; if (is_real(_v)) { _c_e1  = _v; }
        _v = _chr.meta[$ "ecm_bg2"]; if (is_real(_v)) { _c_e2  = _v; }
        _v = _chr.meta[$ "ecm_bg3"]; if (is_real(_v)) { _c_e3  = _v; }
    }

    // ── 6. Map colours (override the charset) ─────────────
    var _m_bg  = -1;
    var _m_mc1 = -1;
    var _m_mc2 = -1;
    var _mv;
    _mv = _map.meta[$ "map_mc_bg"];   if (is_real(_mv)) { _m_bg  = _mv; }
    _mv = _map.meta[$ "map_mc_col1"]; if (is_real(_mv)) { _m_mc1 = _mv; }
    _mv = _map.meta[$ "map_mc_col2"]; if (is_real(_mv)) { _m_mc2 = _mv; }

    var _bg  = _c_bg;
    var _mc1 = _c_mc1;
    var _mc2 = _c_mc2;

    if (_src_kind == "META_TILESET") {
        // Tileset convention: -1 = inherit from the linked charset
        if (_m_bg  >= 0) { _bg  = _m_bg;  }
        if (_m_mc1 >= 0) { _mc1 = _m_mc1; }
        if (_m_mc2 >= 0) { _mc2 = _m_mc2; }
    } else {
        // MAP_DATA: mirror the MACRO_MAP compile - map value wins unless it
        // is still the untouched default (0 / 1 / 2) and a charset is linked
        if (_m_bg >= 0) {
            _bg = _m_bg;
            if (_m_bg == 0 && _chr != noone) { _bg = _c_bg; }
        }
        if (_m_mc1 >= 0) {
            _mc1 = _m_mc1;
            if (_m_mc1 == 1 && _chr != noone) { _mc1 = _c_mc1; }
        }
        if (_m_mc2 >= 0) {
            _mc2 = _m_mc2;
            if (_m_mc2 == 2 && _chr != noone) { _mc2 = _c_mc2; }
        }
    }

    // ── 7. Apply to the VIC node ──────────────────────────
    with (_vic) {
        // Pad older nodes out to the full 10-slot layout
        while (array_length(instructions[0]) < 10) { array_push(instructions[0], 0); }

        var _old_mode  = string(instructions[0][1]);
        var _vic_bank  = 0;
        if (is_real(instructions[0][2])) { _vic_bank = clamp(real(instructions[0][2]), 0, 3); }
        var _bank_base = _vic_bank * 0x4000;

        // Leaving a bitmap mode: move CHR ADDR back off the bitmap, same as the mode buttons
        var _was_bitmap = false;
        if (_old_mode == "BITMAP" || _old_mode == "BMP" || _old_mode == "MCB") { _was_bitmap = true; }
        instructions[0][1] = _new_mode;
        if (_was_bitmap) {
            instructions[0][4] = _bank_base + 0x0800;
        }

        // Point CHR ADDR at the linked charset when it sits in this VIC bank on a 2K boundary
        if (_chr != noone) {
            var _ca_addr = _chr.address;
            if (is_real(_ca_addr)) {
                if (_ca_addr >= _bank_base && _ca_addr < _bank_base + 0x4000) {
                    if (((_ca_addr - _bank_base) mod 0x0800) == 0) {
                        instructions[0][4] = _ca_addr;
                    }
                }
            }
        }

        // Colours - border is left as the user set it
        instructions[0][6] = _bg;
        if (_new_mode == "ECM") {
            instructions[0][7] = _c_e1;
            instructions[0][8] = _c_e2;
            instructions[0][9] = _c_e3;
        } else if (_new_mode == "MCT") {
            instructions[0][7] = _mc1;
            instructions[0][8] = _mc2;
        }
    }

    scr_c64_update_addresses();
}
