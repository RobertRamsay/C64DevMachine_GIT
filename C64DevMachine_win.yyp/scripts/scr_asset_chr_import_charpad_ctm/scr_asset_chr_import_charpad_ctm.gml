/// @desc Import ONLY the charset from a CharPad CTM (v9) into an existing
///       CHAR_SET asset, in place. Ignores materials, colours, tiles and map —
///       just the $da,$b0 char-image block. Called by scr_asset_chr_import when
///       the chosen file has a .ctm extension.
///
/// @param {Struct} _asset  the CHAR_SET asset to overwrite
/// @param {String} _path   full path to the .ctm file
function scr_asset_chr_import_charpad_ctm(_asset, _path) {

    var _buf = buffer_load(_path);
    if (!buffer_exists(_buf)) { scr_show_message("CTM charset import: load failed"); exit; }
    var _sz = buffer_get_size(_buf);

    var _rd_u8 = function(_b, _p) { return buffer_peek(_b, _p, buffer_u8); };

    // ---- Header (19 bytes): validate "CTM" magic ----
    if (_sz < 19) { buffer_delete(_buf); scr_show_message("CTM charset import: file too small"); exit; }
    var _id0 = _rd_u8(_buf, 0);
    var _id1 = _rd_u8(_buf, 1);
    var _id2 = _rd_u8(_buf, 2);
    var _ver = _rd_u8(_buf, 3);
    if (_id0 != 67 || _id1 != 84 || _id2 != 77) {   // "CTM"
        buffer_delete(_buf);
        scr_show_message("CTM charset import: not a CTM file");
        exit;
    }
    if (_ver != 9) {
        show_debug_message("CTM charset import: version " + string(_ver) + " (older) — reading charset block only");
    }

    // Header length (where the first $da,$b0 block starts) varies by version:
    //   v9 = 19, v8 = 14, v7 = 12. The char-image block itself is identical
    //   across all versions, so once we find it the read is the same.
    // We derive a starting guess from the version, then SCAN for the first
    //   $da,$b0 marker so v5/v6 (and any padding) are tolerated too.
    var _disp_mode = 0;                 // default hires; older formats lack a
                                        // display byte at a fixed offset.
    if (_ver == 9) {
        _disp_mode = _rd_u8(_buf, 4);   // 0=Text_HR,1=Text_MC,2=Text_EC,3=Bmp_HR,4=Bmp_MC
    }
    var _chr_mode = (_disp_mode == 1 || _disp_mode == 4) ? 1 : (_disp_mode == 2 ? 2 : 0);

    // ---- Locate the char-image block ($da,$b0) by scanning from byte 4 ----
    var _pos = -1;
    for (var _scan = 4; _scan < _sz - 3; _scan++) {
        if (_rd_u8(_buf, _scan) == 0xDA && _rd_u8(_buf, _scan + 1) == 0xB0) {
            _pos = _scan;
            break;
        }
    }
    if (_pos < 0) {
        buffer_delete(_buf);
        scr_show_message("CTM charset import: bad charset marker");
        exit;
    }
    _pos += 2;

    var _charcnt    = _rd_u8(_buf, _pos) | (_rd_u8(_buf, _pos + 1) << 8);
    _pos += 2;
    var _char_count = _charcnt + 1;             // stored as count-minus-one
    var _used_size  = _char_count * 8;

    if (_pos + _used_size > _sz) {
        buffer_delete(_buf);
        scr_show_message("CTM charset import: charset block truncated");
        exit;
    }
    if (_char_count <= 0) {
        buffer_delete(_buf);
        scr_show_message("CTM charset import: charset empty");
        exit;
    }

    // ---- Build the CHAR_SET buffer from the char bytes ----
    var _cs_buf = buffer_create(_used_size, buffer_fixed, 1);
    for (var _cbi = 0; _cbi < _used_size; _cbi++) {
        buffer_poke(_cs_buf, _cbi, buffer_u8, _rd_u8(_buf, _pos + _cbi));
    }
    buffer_delete(_buf);

    // ---- Overwrite the asset in place (mirrors scr_asset_chr_import) ----
    if (variable_struct_exists(_asset, "buffer") && buffer_exists(_asset.buffer)) {
        buffer_delete(_asset.buffer);
    }
    _asset.buffer    = _cs_buf;
    _asset.file      = _path;
    _asset.file_name = filename_name(_path);
    _asset.meta = {
        format      : "binary",
        char_count  : _char_count,
        total_size  : _used_size,
        preview_surf: -1,
        mc_mode     : _chr_mode,
        mc_fg       : 1,
        mc_bg       : 0,
        mc_col1     : 1,
        mc_col2     : 2,
        ecm_bg1     : 6,
        ecm_bg2     : 14,
        ecm_bg3     : 3,
        is_dirty    : false,
        flash_timer : 0,
        autosave    : true,
        undo_stack  : [],
        redo_stack  : []
    };
    scr_asset_chr_build_preview(_asset);
    global.undo_dirty = true;
    _asset.meta._mtime = md5_file(_asset.file);

    scr_show_message("CTM charset import OK: " + string(_char_count) + " chars ("
        + string(_used_size) + " bytes)");
}
