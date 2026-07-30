	/// scr_chr_multi_copy_paste(_asset)
	/// Handles CTRL+C / CTRL+V across multiple selected chars in the
	/// CHAR_SET picker grid. Single-tile copy/paste lives in
	/// scr_chr_editor_draw and is gated to defer to this handler when
	/// a multi-selection exists.
	function scr_chr_multi_copy_paste(_asset) {

	    if (_asset.type != "CHAR_SET") {
	        return;
	    }

	    var _mgr = obj_asset_manager;

	    // ---- BACKSPACE / DELETE: clear all selected tiles ----
	    // Runs outside the vk_control gate so plain Backspace/Delete works.
	    // Only fires when there is an active multi-selection — otherwise
	    // these keys would steal input from other editors.
	    if (array_length(_mgr.chr_multi_select) > 0) {
	        if (keyboard_check_pressed(vk_backspace) || keyboard_check_pressed(vk_delete)) {
	            scr_chr_undo_push(_asset);
	            var _cleared = 0;
	            for (var _ci = 0; _ci < array_length(_mgr.chr_multi_select); _ci++) {
	                var _tgt_idx = _mgr.chr_multi_select[_ci];
	                if (_tgt_idx < 0 || _tgt_idx >= _asset.meta.char_count) {
	                    continue;
	                }
	                var _tgt_base = _tgt_idx * 8;
	                for (var _bi = 0; _bi < 8; _bi++) {
	                    buffer_poke(_asset.buffer, _tgt_base + _bi, buffer_u8, 0);
	                }
	                _cleared++;
	            }
	            scr_asset_chr_build_preview(_asset);
	            global.undo_dirty    = true;
	            _asset.meta.is_dirty = true;
	            keyboard_clear(vk_backspace);
	            keyboard_clear(vk_delete);
	            // Clear multi-selection after clear so highlights stop flashing
	            // (chr_clipboard is preserved so paste still works afterwards)
	            _mgr.chr_multi_select = [];
	            show_debug_message("MULTI-CLEARED " + string(_cleared) + " TILES");
	        }
	    }

	    if (!scr_ctrl_held()) {
	        return;
	    }

	    // ---- CTRL+C: copy all selected chars into multi-clipboard ----
	    if (keyboard_check_pressed(ord("C"))) {
	        if (array_length(_mgr.chr_multi_select) > 0) {
	            _mgr.chr_clipboard       = [];
	            _mgr.chr_clipboard_owner = _asset.name;
	            // Sort selection so paste lays out in grid order
	            var _sel = array_create(array_length(_mgr.chr_multi_select), 0);
	            for (var _si = 0; _si < array_length(_mgr.chr_multi_select); _si++) {
	                _sel[_si] = _mgr.chr_multi_select[_si];
	            }
	            array_sort(_sel, true);
	            for (var _ci = 0; _ci < array_length(_sel); _ci++) {
	                var _src_idx  = _sel[_ci];
	                var _src_base = _src_idx * 8;
	                var _bytes    = array_create(8, 0);
	                for (var _bi = 0; _bi < 8; _bi++) {
	                    _bytes[_bi] = buffer_peek(_asset.buffer, _src_base + _bi, buffer_u8);
	                }
	                var _entry = {
	                    src_idx : _src_idx,
	                    bytes   : _bytes
	                };
	                array_push(_mgr.chr_clipboard, _entry);
	            }
	            show_debug_message("MULTI-COPIED " + string(array_length(_mgr.chr_clipboard)) + " TILES");
	        }
	    }

	    // ---- CTRL+V: paste multi-clipboard starting at chr_paste_anchor ----
	    if (keyboard_check_pressed(ord("V"))) {
	        if (array_length(_mgr.chr_clipboard) > 1) {
	            var _anchor = _mgr.chr_paste_anchor;
	            if (_anchor < 0) {
	                _anchor = _mgr.chr_edit_idx;
	            }
	            if (_anchor < 0) {
	                _anchor = 0;
	            }

	            var _first_src = _mgr.chr_clipboard[0].src_idx;
	            scr_chr_undo_push(_asset);

	            var _pasted = 0;
	            for (var _pi = 0; _pi < array_length(_mgr.chr_clipboard); _pi++) {
	                var _entry   = _mgr.chr_clipboard[_pi];
	                var _src_off = _entry.src_idx - _first_src;

	                var _src_row = _src_off div 16;
	                var _src_col = _src_off mod 16;

	                var _anc_row = _anchor div 16;
	                var _anc_col = _anchor mod 16;

	                var _dst_row = _anc_row + _src_row;
	                var _dst_col = _anc_col + _src_col;
	                if (_dst_col >= 16) {
	                    _dst_row += _dst_col div 16;
	                    _dst_col  = _dst_col mod 16;
	                }

	                var _dst_idx = (_dst_row * 16) + _dst_col;
	                if (_dst_idx < 0 || _dst_idx >= _asset.meta.char_count) {
	                    continue;
	                }

	                var _dst_base = _dst_idx * 8;
	                for (var _bi = 0; _bi < 8; _bi++) {
	                    buffer_poke(_asset.buffer, _dst_base + _bi, buffer_u8, _entry.bytes[_bi]);
	                }
	                _pasted++;
	            }

	            scr_asset_chr_build_preview(_asset);
	            global.undo_dirty    = true;
	            _asset.meta.is_dirty = true;
	            // Clear multi-selection after paste so highlights stop flashing
	            // (chr_clipboard is preserved so further pastes still work)
	            _mgr.chr_multi_select = [];
	            show_debug_message("MULTI-PASTED " + string(_pasted) + " TILES AT ANCHOR " + string(_anchor));
	        }
	    }
	}