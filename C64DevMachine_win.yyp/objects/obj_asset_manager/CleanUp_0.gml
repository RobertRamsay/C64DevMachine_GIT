// Stop preview instances before releasing their cached sound assets/buffers.
scr_sound_preview_cache_clear();

/// @desc obj_asset_manager CLEANUP

// Free all loaded sprite previews
for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
    var _asset = ds_list_find_value(asset_list, _i);
   if (_asset.type == "SPRITE_SET" && variable_struct_exists(_asset.meta, "spr_sprites")) {
        var _ss_len = array_length(_asset.meta.spr_sprites);
        for (var _si = 0; _si < _ss_len; _si++) {
            if (_asset.meta.spr_sprites[_si] != -1 &&
                sprite_exists(_asset.meta.spr_sprites[_si])) {
                sprite_delete(_asset.meta.spr_sprites[_si]);
            }
        }
    }
}
ds_map_destroy(tag_member_map);
ds_map_destroy(asset_name_map);
ds_list_destroy(asset_list);