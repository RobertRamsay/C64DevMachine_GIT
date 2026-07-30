/// @function scr_code_editor_step()
function scr_code_editor_step() {
	
    if (!code_editor_open) return;
	
// ─── FIND DIALOGUE MODAL GUARD ───
if (code_editor_find_open && code_editor_find_active_field > 0) {
    var _search = string_trim(code_editor_find_text);
    
    // Enter = Next, Shift+Enter = Prev
    if (keyboard_check_pressed(vk_enter)) {
        if (keyboard_check(vk_shift)) {
            // Logic for PREV (see step 2 for the actual logic to paste here or call as function)
            scr_code_editor_do_search(-1); 
        } else {
            // Logic for NEXT
            scr_code_editor_do_search(1);
        }
        keyboard_string = "";
    }

    if (keyboard_check_pressed(vk_tab)) {
        code_editor_find_active_field = (code_editor_find_active_field == 1) ? 2 : 1;
        keyboard_string = "";
    }
    
    // ... rest of your modal guard (Backspace, Escape, etc.)
    
    // Close dialogue
    if (keyboard_check_pressed(vk_escape)) { 
        code_editor_find_open = false; 
        code_editor_find_active_field = 0; 
    }

    // Handle sanitized Paste (First line only)
    if (keyboard_check(vk_control) && keyboard_check_pressed(ord("V"))) {
        var _p = clipboard_get_text();
        _p = string_replace_all(_p, "\r", "");
		var _nl = string_pos("\n", _p);
        if (_nl > 0) _p = string_copy(_p, 1, _nl - 1);
        _p = string_trim(_p); // Trims outer spaces/tabs
        
        if (code_editor_find_active_field == 1) code_editor_find_text += _p;
        else code_editor_replace_text += _p;
        keyboard_string = "";
    }

    // Handle Backspace
    if (keyboard_check_pressed(vk_backspace)) {
        if (keyboard_check(vk_control)) {
            if (code_editor_find_active_field == 1) {
                code_editor_find_text = "";
            } else {
                code_editor_replace_text = "";
            }
        } else {
            if (code_editor_find_active_field == 1) {
                code_editor_find_text = string_delete(code_editor_find_text, string_length(code_editor_find_text), 1);
            } else {
                code_editor_replace_text = string_delete(code_editor_replace_text, string_length(code_editor_replace_text), 1);
            }
        }
        keyboard_string = "";
        keyboard_clear(vk_backspace);
    }

    // Handle Typing (allow AltGr combos for non-US layouts: # @ [ ] { } etc.)
    if (keyboard_string != "") {
        var _alt_gr_find = (keyboard_check(vk_control) && keyboard_check(vk_alt));
        if (!keyboard_check(vk_control) || _alt_gr_find) {
            if (code_editor_find_active_field == 1) code_editor_find_text += keyboard_string;
            else code_editor_replace_text += keyboard_string;
        }
        keyboard_string = "";
    }
    // IMPORTANT: Clear the keyboard buffer so these keys don't "leak" to the 
    // next frame or other systems.
    keyboard_clear(vk_anykey);
    
    // Increment blink so cursor animates in find fields
    code_editor_blink++;

    // EXIT HERE: This prevents the rest of the function (Undo, Arrows, Enter, etc.) 
    // from ever running while the dialogue is active.
    exit; 
}
	
	
    if (!instance_exists(code_editor_node)) { scr_code_editor_close(false); return; }

// ── F12: cycle editor font ──
    if (keyboard_check_pressed(vk_f12)) {
        code_editor_font_index = (code_editor_font_index + 1) mod array_length(code_editor_fonts);
    }

// ── F5: Commit and Build ──
    if (keyboard_check_pressed(vk_f5)) {
        // Push current text to the node so the compiler sees it
        if (instance_exists(code_editor_node)) {
            code_editor_node.instructions[0][1] = code_editor_text;
            global.addresses_dirty = true;
        }
        trigger_build = true;
    }
	


    code_editor_blink++;
    var _txt   = code_editor_text;
    var _cur   = code_editor_cursor;
    var _len   = string_length(_txt);
    var _shift = keyboard_check(vk_shift);
    var _ctrl  = keyboard_check(vk_control);

    // If Alt is held alongside Ctrl, this is AltGr (a typing modifier on non-US layouts),
    // not a shortcut. Disable Ctrl-shortcut interpretation for this frame.
    if (_ctrl && keyboard_check(vk_alt)) _ctrl = false;

    var _has_sel = (code_editor_sel_start != -1 && code_editor_sel_start != code_editor_sel_end);
    var _sel_lo  = _has_sel ? min(code_editor_sel_start, code_editor_sel_end) : _cur;
    var _sel_hi  = _has_sel ? max(code_editor_sel_start, code_editor_sel_end) : _cur;

    // ── Ctrl+Z  Undo ──────────────────────────────────────────
    if (keyboard_check_pressed(ord("Z")) && keyboard_check(vk_control)) {
        if (array_length(code_editor_undo_stack) > 0) {
            var _tip = array_length(code_editor_undo_stack) - 1;
            array_push(code_editor_redo_stack, { text: code_editor_text, cursor: code_editor_cursor });
            var _s = code_editor_undo_stack[_tip];
            array_delete(code_editor_undo_stack, _tip, 1);
            code_editor_text      = _s.text;
            code_editor_cursor    = _s.cursor;
            code_editor_sel_start = -1;
            code_editor_sel_end   = -1;
        }
        exit;
    }

    // ── Ctrl+Y  Redo ──────────────────────────────────────────
    if (keyboard_check_pressed(ord("Y")) && keyboard_check(vk_control)) {
        if (array_length(code_editor_redo_stack) > 0) {
            var _tip = array_length(code_editor_redo_stack) - 1;
            array_push(code_editor_undo_stack, { text: code_editor_text, cursor: code_editor_cursor });
            var _s = code_editor_redo_stack[_tip];
            array_delete(code_editor_redo_stack, _tip, 1);
            code_editor_text      = _s.text;
            code_editor_cursor    = _s.cursor;
            code_editor_sel_start = -1;
            code_editor_sel_end   = -1;
        }
        exit;
    }

	// ─── Close: Escape or Ctrl+Enter ───
    if (keyboard_check_pressed(vk_escape) ||
        (keyboard_check_pressed(vk_enter) && _ctrl)) {
        if (instance_exists(code_editor_node)) code_editor_node.code_cache_dirty = true;
		code_editor_symbol_cache_dirty = true;
        scr_code_editor_close(true);
        keyboard_string = "";
        return;
    }

    // ─── ENTER: new line ───
    if (keyboard_check_pressed(vk_enter) && !_ctrl) {
        scr_code_editor_push_undo();
        if (_has_sel) {
            _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
            _cur = _sel_lo;
            code_editor_sel_start = -1;
            code_editor_sel_end   = -1;
        }
        _txt = string_insert("\n", _txt, _cur + 1);
        _cur++;
        code_editor_text   = _txt;
        code_editor_cursor = _cur;
        code_editor_blink  = 1;
        keyboard_string    = "";
        keyboard_clear(vk_enter);
        code_editor_preferred_col = 0;
        code_editor_cache_dirty   = true;
        // Rebuild line starts immediately so cursor draw is correct this frame
        var _ls_lines = string_split(_txt, "\n");
        var _ls_count = array_length(_ls_lines);
        code_editor_line_starts = array_create(_ls_count, 0);
        var _ls_off = 0;
        for (var _lsi = 0; _lsi < _ls_count; _lsi++) {
            code_editor_line_starts[_lsi] = _ls_off;
            _ls_off += string_length(_ls_lines[_lsi]) + 1;
        }
        return;
    }

    // ─── Ctrl+A: Select all ───
    if (_ctrl && keyboard_check_pressed(ord("A"))) {
        code_editor_sel_start = 0;
        code_editor_sel_end   = _len;
        code_editor_cursor    = _len;
        keyboard_string = "";
        return;
    }

    // ─── Ctrl+C: Copy ───
    if (_ctrl && keyboard_check_pressed(ord("C"))) {
        if (_has_sel) {
            clipboard_set_text(string_copy(_txt, _sel_lo + 1, _sel_hi - _sel_lo));
        }
        keyboard_string = "";
        return;
    }

    // ─── Ctrl+X: Cut ───
    if (_ctrl && keyboard_check_pressed(ord("X"))) {
        scr_code_editor_push_undo();
        if (_has_sel) {
            clipboard_set_text(string_copy(_txt, _sel_lo + 1, _sel_hi - _sel_lo));
            _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
            _cur = _sel_lo;
            code_editor_sel_start = -1;
            code_editor_sel_end   = -1;
            code_editor_text   = _txt;
            code_editor_cursor = _cur;
        }
        code_editor_preferred_col = 0;
        keyboard_string = "";
        code_editor_cache_dirty = true;
        var _ls_lines = string_split(_txt, "\n");
        var _ls_count = array_length(_ls_lines);
        code_editor_line_starts = array_create(_ls_count, 0);
        var _ls_off = 0;
        for (var _lsi = 0; _lsi < _ls_count; _lsi++) {
            code_editor_line_starts[_lsi] = _ls_off;
            _ls_off += string_length(_ls_lines[_lsi]) + 1;
        }
        return;
    }

    // ─── Ctrl+V: Paste ───
    if (_ctrl && keyboard_check_pressed(ord("V"))) {
        scr_code_editor_push_undo();
        var _paste = clipboard_get_text();
        if (_paste != "") {
            _paste = string_replace_all(_paste, "\r\n", "\n");
            _paste = string_replace_all(_paste, "\r",   "\n");
            if (_has_sel) {
                _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
                _cur = _sel_lo;
                code_editor_sel_start = -1;
                code_editor_sel_end   = -1;
            }
            _txt = string_insert(_paste, _txt, _cur + 1);
            _cur += string_length(_paste);
            code_editor_text   = _txt;
            code_editor_cursor = _cur;
            code_editor_blink  = 1;
        }
        code_editor_preferred_col = 0;
        keyboard_string = "";
        code_editor_cache_dirty = true;
        var _ls_lines = string_split(_txt, "\n");
        var _ls_count = array_length(_ls_lines);
        code_editor_line_starts = array_create(_ls_count, 0);
        var _ls_off = 0;
        for (var _lsi = 0; _lsi < _ls_count; _lsi++) {
            code_editor_line_starts[_lsi] = _ls_off;
            _ls_off += string_length(_ls_lines[_lsi]) + 1;
        }
        return;
    }
	
	// Block input if mouse is in the header button area
	var _mx = device_mouse_x_to_gui(0);
	var _my = device_mouse_y_to_gui(0);
	var _header_y_limit = ((display_get_gui_height() - 900) / 2) + 28;
	if (_my < _header_y_limit && mouse_check_button(mb_left)) {
		keyboard_string = ""; 
		// This prevents clicking buttons from placing the cursor at the top line
	}
	
    // ─── Key repeat system ───
    var _do_action = false;
    var _any_nav = keyboard_check(vk_left)  || keyboard_check(vk_right) ||
                   keyboard_check(vk_up)    || keyboard_check(vk_down)  ||
                   keyboard_check(vk_backspace) || keyboard_check(vk_delete);
    if (_any_nav) {
        if (keyboard_check_pressed(vk_left)  || keyboard_check_pressed(vk_right) ||
            keyboard_check_pressed(vk_up)    || keyboard_check_pressed(vk_down)  ||
            keyboard_check_pressed(vk_backspace) || keyboard_check_pressed(vk_delete)) {
            _do_action = true;
            code_editor_key_timer = 20;
        } else {
            code_editor_key_timer--;
            if (code_editor_key_timer <= 0) {
                _do_action = true;
                code_editor_key_timer = 2;
            }
        }
    } else {
        code_editor_key_timer = 0;
    }

    // ─── Word boundary helpers ───
    var _word_left = function(_text, _pos) {
        if (_pos <= 0) return 0;
        var _p = _pos;
        while (_p > 0 && _code_is_separator(string_char_at(_text, _p))) _p--;
        while (_p > 0 && !_code_is_separator(string_char_at(_text, _p))) _p--;
        return _p;
    };
    var _word_right = function(_text, _pos) {
        var _l = string_length(_text);
        if (_pos >= _l) return _l;
        var _p = _pos + 1;
        while (_p <= _l && !_code_is_separator(string_char_at(_text, _p))) _p++;
        while (_p <= _l &&  _code_is_separator(string_char_at(_text, _p))) _p++;
        return _p - 1;
    };

    if (_do_action) {

        // ─── LEFT ───
        if (keyboard_check(vk_left)) {
            code_editor_preferred_col = 0;
            if (_shift) { if (code_editor_sel_start == -1) code_editor_sel_start = _cur; }
            else { code_editor_sel_start = -1; code_editor_sel_end = -1; }
            if (_ctrl) { _cur = _word_left(_txt, _cur); }
            else {
                if (_has_sel && !_shift) _cur = _sel_lo;
                else if (_cur > 0) _cur--;
            }
            code_editor_cursor = _cur;
            if (_shift) code_editor_sel_end = _cur;
            code_editor_blink = 0;
        }

        // ─── RIGHT ───
        if (keyboard_check(vk_right)) {
            code_editor_preferred_col = 0;
            if (_shift) { if (code_editor_sel_start == -1) code_editor_sel_start = _cur; }
            else { code_editor_sel_start = -1; code_editor_sel_end = -1; }
            if (_ctrl) { _cur = _word_right(_txt, _cur); }
            else {
                if (_has_sel && !_shift) _cur = _sel_hi;
                else if (_cur < _len) _cur++;
            }
            code_editor_cursor = _cur;
            if (_shift) code_editor_sel_end = _cur;
            code_editor_blink = 0;
        }

        // ─── UP ───
        if (keyboard_check(vk_up)) {
            if (_shift) { if (code_editor_sel_start == -1) code_editor_sel_start = _cur; }
            else { code_editor_sel_start = -1; code_editor_sel_end = -1; }
            var _lines = string_split(_txt, "\n");
            var _line_idx = 0, _col = 0, _count = 0;
            for (var _i = 0; _i < array_length(_lines); _i++) {
                var _ll = string_length(_lines[_i]) + 1;
                if (_count + _ll > _cur) { _line_idx = _i; _col = _cur - _count; break; }
                _count += _ll;
            }
            code_editor_preferred_col = max(code_editor_preferred_col, _col);
            if (_line_idx > 0) {
                var _prev_len = string_length(_lines[_line_idx - 1]);
                var _new_col  = min(code_editor_preferred_col, _prev_len);
                _cur = _count - _prev_len - 1 + _new_col;
                if (_cur < 0) _cur = 0;
            } else { _cur = 0; }
            code_editor_cursor = _cur;
            if (_shift) code_editor_sel_end = _cur;
            code_editor_blink = 0;
        }

        // ─── DOWN ───
        if (keyboard_check(vk_down)) {
            if (_shift) { if (code_editor_sel_start == -1) code_editor_sel_start = _cur; }
            else { code_editor_sel_start = -1; code_editor_sel_end = -1; }
            var _lines = string_split(_txt, "\n");
            var _line_idx = 0, _col = 0, _count = 0;
            for (var _i = 0; _i < array_length(_lines); _i++) {
                var _ll = string_length(_lines[_i]) + 1;
                if (_count + _ll > _cur) { _line_idx = _i; _col = _cur - _count; break; }
                _count += _ll;
            }
            code_editor_preferred_col = max(code_editor_preferred_col, _col);
            if (_line_idx < array_length(_lines) - 1) {
                var _next_start = _count + string_length(_lines[_line_idx]) + 1;
                var _next_len   = string_length(_lines[_line_idx + 1]);
                _cur = _next_start + min(code_editor_preferred_col, _next_len);
            } else { _cur = _len; }
            code_editor_cursor = _cur;
            if (_shift) code_editor_sel_end = _cur;
            code_editor_blink = 0;
        }

        // ─── BACKSPACE ───
        if (keyboard_check(vk_backspace)) {
            scr_code_editor_push_undo();
            code_editor_preferred_col = 0;
            if (_has_sel) {
                _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
                _cur = _sel_lo;
                code_editor_sel_start = -1;
                code_editor_sel_end   = -1;
            } else if (_ctrl) {
                var _wp = _word_left(_txt, _cur);
                _txt = string_delete(_txt, _wp + 1, _cur - _wp);
                _cur = _wp;
            } else if (_cur > 0) {
                _txt = string_delete(_txt, _cur, 1);
                _cur--;
            }
			code_editor_text   = _txt;
            code_editor_cursor = _cur;
            code_editor_blink  = 0;
			
        }

        // ─── DELETE ───
        if (keyboard_check(vk_delete)) {
            scr_code_editor_push_undo();
            code_editor_preferred_col = 0;
            if (_has_sel) {
                _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
                _cur = _sel_lo;
                code_editor_sel_start = -1;
                code_editor_sel_end   = -1;
            } else if (_cur < _len) {
                _txt = string_delete(_txt, _cur + 1, 1);
            }
			code_editor_text   = _txt;
            code_editor_cursor = _cur;
            code_editor_blink  = 0;
			
        }
    }

    // ─── PAGE UP ───
    if (keyboard_check_pressed(vk_pageup)) {
        if (_shift) { if (code_editor_sel_start == -1) code_editor_sel_start = _cur; }
        else { code_editor_sel_start = -1; code_editor_sel_end = -1; }
        var _lines = string_split(_txt, "\n");
        var _line_idx = 0;
        var _count = 0;
        for (var _i = 0; _i < array_length(_lines); _i++) {
            var _ll = string_length(_lines[_i]) + 1;
            if (_count + _ll > _cur) { _line_idx = _i; break; }
            _count += _ll;
        }
        var _new_line = max(0, _line_idx - 20);
        _count = 0;
        for (var _i = 0; _i < _new_line; _i++) _count += string_length(_lines[_i]) + 1;
        _cur = _count;
        code_editor_cursor    = _cur;
        code_editor_scroll_y  = max(0, code_editor_scroll_y - 20);
        if (_shift) code_editor_sel_end = _cur;
        code_editor_blink     = 1;
        code_editor_preferred_col = 0;
    }

    // ─── PAGE DOWN ───
    if (keyboard_check_pressed(vk_pagedown)) {
        if (_shift) { if (code_editor_sel_start == -1) code_editor_sel_start = _cur; }
        else { code_editor_sel_start = -1; code_editor_sel_end = -1; }
        var _lines = string_split(_txt, "\n");
        var _total = array_length(_lines);
        var _line_idx = 0;
        var _count = 0;
        for (var _i = 0; _i < _total; _i++) {
            var _ll = string_length(_lines[_i]) + 1;
            if (_count + _ll > _cur) { _line_idx = _i; break; }
            _count += _ll;
        }
        var _new_line = min(_total - 1, _line_idx + 20);
        _count = 0;
        for (var _i = 0; _i < _new_line; _i++) _count += string_length(_lines[_i]) + 1;
        _cur = _count;
        code_editor_cursor    = _cur;
        code_editor_scroll_y  = min(max(0, _total - 20), code_editor_scroll_y + 20);
        if (_shift) code_editor_sel_end = _cur;
        code_editor_blink     = 1;
        code_editor_preferred_col = 0;
    }

    // ─── HOME ───
    if (keyboard_check_pressed(vk_home)) {
        code_editor_preferred_col = 0;
        if (_shift) { if (code_editor_sel_start == -1) code_editor_sel_start = _cur; }
        else { code_editor_sel_start = -1; code_editor_sel_end = -1; }
        var _lines = string_split(_txt, "\n");
        var _count = 0;
        for (var _i = 0; _i < array_length(_lines); _i++) {
            var _ll = string_length(_lines[_i]) + 1;
            if (_count + _ll > _cur) { _cur = _count; break; }
            _count += _ll;
        }
        code_editor_cursor = _cur;
        if (_shift) code_editor_sel_end = _cur;
        code_editor_blink = 0;
		
    }

    // ─── END ───
    if (keyboard_check_pressed(vk_end)) {
        code_editor_preferred_col = 0;
        if (_shift) { if (code_editor_sel_start == -1) code_editor_sel_start = _cur; }
        else { code_editor_sel_start = -1; code_editor_sel_end = -1; }
        var _lines = string_split(_txt, "\n");
        var _count = 0;
        for (var _i = 0; _i < array_length(_lines); _i++) {
            var _ll = string_length(_lines[_i]) + 1;
            if (_count + _ll > _cur) { _cur = _count + string_length(_lines[_i]); break; }
            _count += _ll;
        }
        code_editor_cursor = _cur;
        if (_shift) code_editor_sel_end = _cur;
        code_editor_blink = 0;
		
    }

    // ─── TAB ───
    if (keyboard_check_pressed(vk_tab)) {
        scr_code_editor_push_undo();
        if (_shift) {
            var _lines = string_split(_txt, "\n");
            var _line_idx = 0, _line_start = 0, _count = 0;
            for (var _i = 0; _i < array_length(_lines); _i++) {
                var _ll = string_length(_lines[_i]) + 1;
                if (_count + _ll > _cur) { _line_idx = _i; _line_start = _count; break; }
                _count += _ll;
            }
            var _removed = 0;
            for (var _ri = 0; _ri < 2; _ri++) {
                if (string_char_at(_txt, _line_start + 1) == " ") {
                    _txt = string_delete(_txt, _line_start + 1, 1);
                    _removed++;
                }
            }
            _cur = max(_line_start, _cur - _removed);
            code_editor_text   = _txt;
            code_editor_cursor = _cur;
        } else {
            if (_has_sel) {
                _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
                _cur = _sel_lo;
                code_editor_sel_start = -1;
                code_editor_sel_end   = -1;
            }
            _txt = string_insert("  ", _txt, _cur + 1);
            _cur += 2;
            code_editor_text   = _txt;
            code_editor_cursor = _cur;
        }
        code_editor_preferred_col = 0;
        code_editor_blink = 0;
		
        keyboard_string   = "";
        keyboard_clear(vk_tab);
    }
	
	// ─── CTRL+F / CTRL+SHIFT+F Triggers ───
if (_ctrl && keyboard_check_pressed(ord("F"))) {
    code_editor_find_open = true;
    code_editor_find_active_field = 1;
    code_editor_find_text    = "";
    code_editor_replace_text = "";
    code_editor_blink        = 0;
    keyboard_string = "";
}




    // ─── Character input ───
    // AltGr on non-US layouts (e.g. Italian #, @, [, ], {, }) is reported as Ctrl+Alt.
    // Treat Ctrl+Alt as "not a shortcut" so typed glyphs pass through.
    var _alt_gr = (_ctrl && keyboard_check(vk_alt));
    if (keyboard_string != "" && (!_ctrl || _alt_gr)) {
        scr_code_editor_push_undo();
        var _added = keyboard_string;
        if (_has_sel) {
            _txt = string_delete(_txt, _sel_lo + 1, _sel_hi - _sel_lo);
            _cur = _sel_lo;
            code_editor_sel_start = -1;
            code_editor_sel_end   = -1;
        }
		_txt = string_insert(_added, _txt, _cur + 1);
        _cur += string_length(_added);
        code_editor_preferred_col = 0;
        code_editor_text   = _txt;
        code_editor_cursor = _cur;
        code_editor_blink  = 1;
        keyboard_string    = "";
		code_editor_cache_dirty        = true;
        
    }
	
if keyboard_check_released(vk_anykey) code_editor_symbol_cache_dirty = true;

    keyboard_string = "";

    // ─── Live sync to node so label picker sees current labels ───
    if (instance_exists(code_editor_node)) {
        if (code_editor_node.instructions[0][1] != code_editor_text) {
            code_editor_node.instructions[0][1] = code_editor_text;
            code_editor_symbol_cache_dirty = true;
        }
    }
}