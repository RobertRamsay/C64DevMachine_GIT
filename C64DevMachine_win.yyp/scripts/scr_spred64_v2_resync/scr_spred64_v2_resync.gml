/// @function scr_spred64_v2_resync(_asset)
/// @desc Re-syncs V2's working state from an asset whose buffer/meta have
///       just changed underneath it (e.g. after a file reload). Pulls
///       fresh bits, mode flags, palette state from the asset and rebuilds
///       all 64 picker thumbnails.
///
///       Discards V2's dirty flag — any unsaved edits are gone, which is
///       the correct behaviour because the user has explicitly loaded a
///       new file over the top.
function scr_spred64_v2_resync(_asset) {

    with (obj_asset_manager) {

        if (!spred64_v2.active) exit;
        if (_asset.type != "SPRITE_SET") exit;

        // Re-unpack bits from the (now-fresh) buffer
        spred64_v2.bits = scr_spred64_v2_unpack_bits(_asset);

        // Re-pull meta. The import path should have populated all these,
        // but be defensive in case it didn't.
        if (!variable_struct_exists(_asset.meta, "sprite_mcs")) {
            _asset.meta.sprite_mcs = array_create(64, 0);
        }
        if (!variable_struct_exists(_asset.meta, "sprite_ucs")) {
            _asset.meta.sprite_ucs = array_create(64, 1);
        }
        if (!variable_struct_exists(_asset.meta, "bg_col"))     _asset.meta.bg_col     = 0;
        if (!variable_struct_exists(_asset.meta, "mc1_col"))    _asset.meta.mc1_col    = 1;
        if (!variable_struct_exists(_asset.meta, "mc2_col"))    _asset.meta.mc2_col    = 2;
        if (!variable_struct_exists(_asset.meta, "used_count")) _asset.meta.used_count = 1;

        for (var _i = 0; _i < 64; _i++) {
            spred64_v2.sprite_modes[_i] = _asset.meta.sprite_mcs[_i];
            spred64_v2.sprite_uc[_i]    = _asset.meta.sprite_ucs[_i];
        }
        spred64_v2.bg_col     = _asset.meta.bg_col;
        spred64_v2.mc1_col    = _asset.meta.mc1_col;
        spred64_v2.mc2_col    = _asset.meta.mc2_col;
        spred64_v2.used_count = _asset.meta.used_count;

        // ----- COMPOSITOR -----
        // Re-init compositor on the asset if the reloaded file has none.
        // Seed with a single empty frame; the deep-clone-into-working block
        // below will mirror this empty state into spred64_v2.compositor.
        if (!variable_struct_exists(_asset.meta, "compositor")) {
            _asset.meta.compositor = {
                frames       : [ { cells : [] } ],
                active_layer : 0,
                active_frame : 0,
                active_cell  : -1
            };
        }
        if (array_length(_asset.meta.compositor.frames) == 0) {
            array_push(_asset.meta.compositor.frames, { cells : [] });
        }
        // ----- ANIMATION STATE (resync) -----
        if (!variable_struct_exists(_asset.meta, "anim")) {
            _asset.meta.anim = {
                playing   : false,
                direction : "fwd",
                speed     : 10,
                start     : 0,
                ender       : 0
            };
        }
        spred64_v2.anim_playing      = false;
        spred64_v2.anim_direction    = _asset.meta.anim.direction;
        spred64_v2.anim_speed        = _asset.meta.anim.speed;
        spred64_v2.anim_start        = _asset.meta.anim.start;
        spred64_v2.anim_end          = _asset.meta.anim.ender;
        spred64_v2.anim_last_step_ms = 0;
        spred64_v2.anim_png_dir      = 1;
        // Deep-clone reloaded compositor back into working state.
        var _comp_frames_src = _asset.meta.compositor.frames;
        var _comp_frames_wrk = array_create(array_length(_comp_frames_src));
        for (var _cfi = 0; _cfi < array_length(_comp_frames_src); _cfi++) {
            var _src_cells = _comp_frames_src[_cfi].cells;
            var _wrk_cells = array_create(array_length(_src_cells));
            for (var _ci = 0; _ci < array_length(_src_cells); _ci++) {
                var _sc = _src_cells[_ci];
                _wrk_cells[_ci] = {
                    layer  : _sc.layer,
                    row    : _sc.row,
                    col    : _sc.col,
                    slot   : _sc.slot,
                    xo     : _sc.xo,
                    yo     : _sc.yo,
                    expand : _sc.expand
                };
            }
            _comp_frames_wrk[_cfi] = { cells : _wrk_cells };
        }
        spred64_v2.compositor.frames       = _comp_frames_wrk;
        spred64_v2.compositor.active_layer = _asset.meta.compositor.active_layer;
        spred64_v2.compositor.active_frame = _asset.meta.compositor.active_frame;
        spred64_v2.compositor.active_cell  = -1;
        spred64_v2.comp_hover_layer = -1;
        spred64_v2.comp_hover_row   = -1;
        spred64_v2.comp_hover_col   = -1;

        // Discard dirty flag — fresh file load overrides any pending edits
        spred64_v2.dirty       = false;
        spred64_v2.dirty_timer = -1;

        // Force the pixel-editor canvas to rebuild from the new bits
        if (surface_exists(spred64_v2.edit_surface)) {
            surface_free(spred64_v2.edit_surface);
        }
        spred64_v2.edit_surface = -1;

        // Refresh every picker thumbnail so they reflect the loaded file
        for (var _ri = 0; _ri < 64; _ri++) {
            scr_spred64_v2_refresh_slot_sprite(_asset, _ri);
        }

        show_debug_message("SPRED64 V2: re-synced from reloaded asset '" + _asset.name + "'");
    }
}