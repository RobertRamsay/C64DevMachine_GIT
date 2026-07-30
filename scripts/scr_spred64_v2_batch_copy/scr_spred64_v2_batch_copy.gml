function scr_spred64_v2_batch_copy(_asset) {
    with (obj_asset_manager) {
        var _v2 = spred64_v2;
        var _used = clamp(_v2.used_count, 1, 64);
        
        // Collect multi-selected slots + explicitly ensure the currently highlighted/selected slot is included
        var _selected_slots = [];
        var _included = array_create(64, false);
        
        // Always include current primary selected slot first
        array_push(_selected_slots, _v2.selected_slot);
        _included[_v2.selected_slot] = true;
        
        // Include any other multi-selected slots
        for (var i = 0; i < _used; i++) {
            if (_v2.multi_select[i] && !_included[i]) {
                array_push(_selected_slots, i);
                _included[i] = true;
            }
        }
        
        if (array_length(_selected_slots) == 0) exit;
        
        // Sort selected slots numerically so they maintain correct sequential offsets
        array_sort(_selected_slots, true);
        
        // Find minimum index to calculate relative offsets
        var _min_slot = _selected_slots[0];
        
        // Build clipboard payload
        global.spred64_v2_clipboard = {
            source_asset: _asset,
            items: []
        };
        
        for (var i = 0; i < array_length(_selected_slots); i++) {
            var _s_idx = _selected_slots[i];
            var _rel_offset = _s_idx - _min_slot;
            
            // Extract bits (504 per slot)
            var _bit_base = _s_idx * 504;
            var _slot_bits = array_create(504);
            array_copy(_slot_bits, 0, _v2.bits, _bit_base, 504);
            
            array_push(global.spred64_v2_clipboard.items, {
                relative_offset: _rel_offset,
                bits: _slot_bits,
                mode: _v2.sprite_modes[_s_idx],
                uc_col: _v2.sprite_uc[_s_idx],
                mc1_col: _v2.mc1_col,
                mc2_col: _v2.mc2_col,
                bg_col: _v2.bg_col
            });
        }
        
        show_debug_message("SPRED64 V2: Copied " + string(array_length(_selected_slots)) + " slot(s) to clipboard.");
    }
}