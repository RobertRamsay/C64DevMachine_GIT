/// @function scr_spred64_v2_close(_commit)
/// @desc Closes the built-in SPRED64 V2 editor. If _commit is true, writes
///       working bit array back to the asset's buffer and refreshes the
///       cached sprite surfaces. If false, discards all working state.
function scr_spred64_v2_close(_commit) {

    with (obj_asset_manager) {

        if (!spred64_v2.active) exit;

        var _idx = spred64_v2.asset_index;
        if (_idx < 0 || _idx >= ds_list_size(asset_list)) {
            // Asset deleted while V2 was open — discard
            spred64_v2.active      = false;
            spred64_v2.asset_index = -1;
            if (surface_exists(spred64_v2.edit_surface)) {
                surface_free(spred64_v2.edit_surface);
            }
            spred64_v2.edit_surface = -1;
            exit;
        }

        var _asset = ds_list_find_value(asset_list, _idx);

        if (_commit && spred64_v2.dirty) {
            // Repack bits into asset buffer
            scr_spred64_v2_repack_bits(_asset);

            // Push working colour/mode state back to asset meta — only for
            // used slots, so meta arrays stay sized to used_count.
            var _commit_used = clamp(spred64_v2.used_count, 1, 64);
            _asset.meta.sprite_mcs = array_create(_commit_used, 0);
            _asset.meta.sprite_ucs = array_create(_commit_used, 1);
            for (var _i = 0; _i < _commit_used; _i++) {
                _asset.meta.sprite_mcs[_i] = spred64_v2.sprite_modes[_i];
                _asset.meta.sprite_ucs[_i] = spred64_v2.sprite_uc[_i];
            }
            _asset.meta.bg_col     = spred64_v2.bg_col;
            _asset.meta.mc1_col    = spred64_v2.mc1_col;
            _asset.meta.mc2_col    = spred64_v2.mc2_col;
            _asset.meta.used_count = spred64_v2.used_count;
            _asset.meta.has_colour = true;

            // ----- COMPOSITOR -----
            // Deep-clone working compositor back into the asset's persistent meta.
            var _comp_frames_wrk = spred64_v2.compositor.frames;
            var _comp_frames_out = array_create(array_length(_comp_frames_wrk));
            for (var _cfi = 0; _cfi < array_length(_comp_frames_wrk); _cfi++) {
                var _wrk_cells = _comp_frames_wrk[_cfi].cells;
                var _out_cells = array_create(array_length(_wrk_cells));
                for (var _ci = 0; _ci < array_length(_wrk_cells); _ci++) {
                    var _wc = _wrk_cells[_ci];
                    _out_cells[_ci] = {
                        layer  : _wc.layer,
                        row    : _wc.row,
                        col    : _wc.col,
                        slot   : _wc.slot,
                        xo     : _wc.xo,
                        yo     : _wc.yo,
                        expand : _wc.expand
                    };
                }
                _comp_frames_out[_cfi] = { cells : _out_cells };
            }
            _asset.meta.compositor = {
                frames       : _comp_frames_out,
                active_layer : spred64_v2.compositor.active_layer,
                active_frame : spred64_v2.compositor.active_frame,
                active_cell  : -1
            };
            // Persist animation state alongside the compositor
            _asset.meta.anim = {
                playing   : false,   // never persist playing=true
                direction : spred64_v2.anim_direction,
                speed     : spred64_v2.anim_speed,
                start     : spred64_v2.anim_start,
                ender       : spred64_v2.anim_end
            };
            // Rebuild the GameMaker sprite cache so the existing 8x8 grid
            // and any node previews pick up the changes
            scr_asset_spr_cache_sprites(_asset, true);

            // Mark autosave dirty so changes get written to disk
            if (variable_struct_exists(_asset.meta, "is_dirty")) {
                _asset.meta.is_dirty = true;
            }
            global.addresses_dirty = true;
            global.memory_bar_dirty = true;

            show_debug_message("SPRED64 V2: committed changes to '" + _asset.name + "'");
        } else {
            show_debug_message("SPRED64 V2: closed without commit (dirty=" + string(spred64_v2.dirty) + ")");
        }

        // Reset working state
        spred64_v2.active      = false;
        spred64_v2.asset_index = -1;
        spred64_v2.dirty       = false;
        spred64_v2.dirty_timer = -1;

        if (surface_exists(spred64_v2.edit_surface)) {
            surface_free(spred64_v2.edit_surface);
        }
        spred64_v2.edit_surface = -1;
    }
    show_debug_message("V2 CLOSE: exit");
}