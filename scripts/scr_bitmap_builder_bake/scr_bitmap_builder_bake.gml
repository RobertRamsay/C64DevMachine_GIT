/// @function scr_bitmap_builder_bake(_asset)
/// @desc Commits the builder's scratch preview into the DESTINATION bitmap
///       asset — pixels, mask, backup — so the assembled image becomes real
///       data on that BITMAP. From there it round-trips through the normal
///       bitmap pipeline: EXPORT PNG / EXPORT KLA / autosave all just work.
///
/// scr_asset_kla_save re-quantises the surface itself (it derives screen RAM
/// and colour RAM per char cell from the resolved pixels), so the bake only
/// needs to write the surface, rebuild bg_mask against the dest's bg_col, and
/// refresh pixel_backup for F11 surface-loss recovery.
///
/// This is destructive to the destination. The runtime doesn't need it — the
/// MOVE_BMP_BLOCK node assembles the same image on the C64 from the BBD table
/// — so bake is purely for when you want the composed picture as a real asset.
function scr_bitmap_builder_bake(_asset) {
    var _m = _asset.meta;

    if (!surface_exists(_m.prev_surf)) {
        _m.warn_msg   = "NO PREVIEW TO BAKE";
        _m.warn_timer = game_get_speed(gamespeed_fps) * 3;
        return;
    }

    // ── Resolve the destination BITMAP ──
    var _dst = noone;
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a.type == "BITMAP" && _a.name == _m.dst_asset) {
                _dst = _a;
                break;
            }
        }
    }
    if (_dst == noone) {
        _m.warn_msg   = "NO DEST BITMAP LINKED";
        _m.warn_timer = game_get_speed(gamespeed_fps) * 3;
        return;
    }

    // ── Write the pixels ──
    if (!variable_struct_exists(_dst.meta, "preview_surf")
    ||  !surface_exists(_dst.meta.preview_surf)) {
        _dst.meta.preview_surf = surface_create(320, 200);
    }
    surface_set_target(_dst.meta.preview_surf);
    gpu_set_texfilter(false);
    gpu_set_blendmode_ext(bm_one, bm_zero);
    draw_clear(c_black);
    draw_surface(_m.prev_surf, 0, 0);
    gpu_set_blendmode(bm_normal);
    surface_reset_target();

    // ── Rebuild bg_mask from the new pixels ──
    // 0 = background (absorbs changes), 1 = explicitly drawn (protected).
    // Same rule scr_asset_bmp_build_preview uses: anything not the bg colour
    // is protected.
    var _bg = variable_struct_exists(_dst.meta, "bg_col") ? _dst.meta.bg_col : 0;
    var _bg_col = scr_c64_pepto_colour(_bg);
    var _bg_r   = color_get_red(_bg_col);
    var _bg_g   = color_get_green(_bg_col);
    var _bg_b   = color_get_blue(_bg_col);

    var _mbuf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_mbuf, _dst.meta.preview_surf, 0);
    _dst.meta.bg_mask = array_create(64000, 0);
    for (var _mi = 0; _mi < 64000; _mi++) {
        var _mo = _mi * 4;
        var _mr = buffer_peek(_mbuf, _mo,     buffer_u8);
        var _mg = buffer_peek(_mbuf, _mo + 1, buffer_u8);
        var _mb = buffer_peek(_mbuf, _mo + 2, buffer_u8);
        if (_mr == _bg_r && _mg == _bg_g && _mb == _bg_b) {
            _dst.meta.bg_mask[_mi] = 0;
        } else {
            _dst.meta.bg_mask[_mi] = 1;
        }
    }
    buffer_delete(_mbuf);

    // ── Refresh the F11 restore backup ──
    if (!variable_struct_exists(_dst.meta, "pixel_backup")) {
        _dst.meta.pixel_backup = -1;
    }
    if (!buffer_exists(_dst.meta.pixel_backup)) {
        _dst.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    }
    buffer_get_surface(_dst.meta.pixel_backup, _dst.meta.preview_surf, 0);

    // ── Flag it dirty so the normal bitmap pipeline picks it up ──
    _dst.meta.has_data         = true;
    _dst.meta.needs_mask_init  = false;
    _dst.meta.pixels_dirty     = true;
    _dst.meta.bmp_unsaved      = true;
    _dst.meta.clash_grid       = array_create(1000, false);
    _dst.meta.undo_stack       = [];
    _dst.meta.redo_stack       = [];

    // Give it a file path if it's a brand-new in-memory bitmap, so RESAVE /
    // EXPORT KLA have somewhere to write.
    if (_dst.file == "" || _dst.file == undefined) {
        var _save_dir = working_directory + "bitmaps";
        if (!directory_exists(_save_dir)) {
            directory_create(_save_dir);
        }
        _dst.file = _save_dir + "/" + _dst.name + ".kla";
    }

    global.undo_dirty = true;

    _m.warn_msg   = "BAKED -> " + _dst.name;
    _m.warn_timer = game_get_speed(gamespeed_fps) * 3;
}