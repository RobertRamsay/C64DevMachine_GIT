/// @function scr_spred64_v2_open(_asset_index)
/// @desc Opens the built-in SPRED64 V2 editor on a SPRITE_SET asset.
///       Unpacks the asset's packed-byte buffer into a working bit array,
///       loads colour and per-slot mode state into spred64_v2 working struct.
function scr_spred64_v2_open(_asset_index) {

    with (obj_asset_manager) {

        // Bounds check
        if (_asset_index < 0 || _asset_index >= ds_list_size(asset_list)) {
            show_debug_message("SPRED64 V2: invalid asset index " + string(_asset_index));
            exit;
        }

        var _asset = ds_list_find_value(asset_list, _asset_index);
        if (_asset.type != "SPRITE_SET") {
            show_debug_message("SPRED64 V2: asset is not SPRITE_SET");
            exit;
        }

        // If V2 was already open on a different asset, commit that first
        if (spred64_v2.active && spred64_v2.asset_index != _asset_index) {
            scr_spred64_v2_close(true);
        }

        // Unpack buffer to working bit array
        spred64_v2.bits = scr_spred64_v2_unpack_bits(_asset);

        // Pull mode/colour state from existing meta. We don't check
        // variable_struct_exists at runtime — but for an asset that
        // was never imported through spred64 these fields may not be
        // present yet, so we initialise meta if missing here.
        if (!variable_struct_exists(_asset.meta, "sprite_mcs")) {
            _asset.meta.sprite_mcs = array_create(64, 0);
        }
        if (!variable_struct_exists(_asset.meta, "sprite_ucs")) {
            _asset.meta.sprite_ucs = array_create(64, 1);
        }
        if (!variable_struct_exists(_asset.meta, "bg_col")) _asset.meta.bg_col  = 0;
        if (!variable_struct_exists(_asset.meta, "mc1_col")) _asset.meta.mc1_col = 1;
        if (!variable_struct_exists(_asset.meta, "mc2_col")) _asset.meta.mc2_col = 2;
        if (!variable_struct_exists(_asset.meta, "used_count")) _asset.meta.used_count = 1;

        // Copy meta into working state — clone arrays so editor edits
        // don't bleed into the live asset until commit. meta arrays are
        // sized to used_count, so only copy that many; the working arrays
        // stay 64-long (allocated in Create) with defaults past used_count.
        var _open_used = clamp(_asset.meta.used_count, 1, 64);
        var _open_mcs_len = array_length(_asset.meta.sprite_mcs);
        var _open_ucs_len = array_length(_asset.meta.sprite_ucs);
        for (var _i = 0; _i < 64; _i++) {
            spred64_v2.sprite_modes[_i] = (_i < _open_mcs_len) ? _asset.meta.sprite_mcs[_i] : 0;
            spred64_v2.sprite_uc[_i]    = (_i < _open_ucs_len) ? _asset.meta.sprite_ucs[_i] : 1;
        }
        spred64_v2.bg_col        = _asset.meta.bg_col;
        spred64_v2.mc1_col       = _asset.meta.mc1_col;
        spred64_v2.mc2_col       = _asset.meta.mc2_col;
        spred64_v2.used_count    = _asset.meta.used_count;

        // Editor entry state
        spred64_v2.selected_slot = 0;
        spred64_v2.active_colour = 3;
        spred64_v2.dirty         = false;
        spred64_v2.dirty_timer   = -1;
        spred64_v2.asset_index   = _asset_index;
        spred64_v2.active        = true;

        // ----- COMPOSITOR -----
        // Init persistent compositor on the asset if absent (V1 back-compat:
        // any SPRITE_SET saved before phase 2 has no compositor field).
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
        // Defensive: ensure frames[0] exists in case an older partial save left
        // a compositor field with an empty frames array.
        if (array_length(_asset.meta.compositor.frames) == 0) {
            array_push(_asset.meta.compositor.frames, { cells : [] });
        }

        // ----- ANIMATION STATE -----
        // Init persistent anim state on the asset if absent (V1/V2-early back-compat).
        if (!variable_struct_exists(_asset.meta, "anim")) {
            _asset.meta.anim = {
                playing   : false,
                direction : "fwd",
                speed     : 10,
                start     : 0,
                ender       : 0
            };
        }
        // Pull into working state
        spred64_v2.anim_playing      = false;   // never start playing on open
        spred64_v2.anim_direction    = _asset.meta.anim.direction;
        spred64_v2.anim_speed        = _asset.meta.anim.speed;
        spred64_v2.anim_start        = _asset.meta.anim.start;
        spred64_v2.anim_end          = _asset.meta.anim.ender;
        spred64_v2.anim_last_step_ms = 0;
        spred64_v2.anim_png_dir      = 1;

        // Clone compositor into working state. Deep-clone the cells arrays so
        // edits in the editor don't bleed into the asset until commit.
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

        // Free any prior edit surface; rebuild on first draw of the slot
        if (surface_exists(spred64_v2.edit_surface)) {
            surface_free(spred64_v2.edit_surface);
        }
        spred64_v2.edit_surface = -1;

        // Rebuild all 64 picker thumbnails from the freshly unpacked bits.
        // This guarantees the picker shows the asset's actual content even
        // if scr_asset_spr_cache_sprites was skipped (e.g. on workspace
        // load when the SPRITE_SET has no source file on disk).
        var _open_rebuild = clamp(_asset.meta.used_count, 1, 64);
        for (var _ri = 0; _ri < _open_rebuild; _ri++) {
            scr_spred64_v2_refresh_slot_sprite(_asset, _ri);
        }

        show_debug_message("SPRED64 V2: opened asset '" + _asset.name + "' (idx " + string(_asset_index) + ")");
    }
}