function scr_spred64_v2_batch_paste(_asset) {
    if (!variable_global_exists("spred64_v2_clipboard") || global.spred64_v2_clipboard == -1) {
        return;
    }
    
    with (obj_asset_manager) {
        var _v2 = spred64_v2;
        var _clipboard = global.spred64_v2_clipboard;
        // Automatically use the currently highlighted/selected cell as the drop origin
        var _target_base_slot = _v2.selected_slot;
        
        var _items = _clipboard.items;
        for (var i = 0; i < array_length(_items); i++) {
            var _item = _items[i];
            var _dest_slot = _target_base_slot + _item.relative_offset;
            
            // Auto-expand slots if pasting beyond current used count (up to 64 limit)
            while (_v2.used_count <= _dest_slot && _v2.used_count < 64) {
                scr_spred64_v2_add_slot();
            }
            
            if (_dest_slot >= 0 && _dest_slot < 64) {
                // Copy bits over
                var _bit_base = _dest_slot * 504;
                array_copy(_v2.bits, _bit_base, _item.bits, 0, 504);
                
                // Copy metadata/mode configurations
                _v2.sprite_modes[_dest_slot] = _item.mode;
                _v2.sprite_uc[_dest_slot] = _item.uc_col;
                
                // Refresh slot thumbnail on the target asset
                _v2.dirty = true;
                scr_spred64_v2_invalidate_sot(_dest_slot);
                scr_spred64_v2_refresh_slot_sprite(_asset, _dest_slot);
            }
        }
        
        show_debug_message("SPRED64 V2: Pasted clipboard items starting at slot " + string(_target_base_slot));
    }
}