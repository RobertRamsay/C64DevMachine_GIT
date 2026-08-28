/// @function scr_code_editor_draw()
function scr_code_editor_draw() {
    if (!code_editor_open) return;

    var _gui_w = global.gui_w;
    var _gui_h = display_get_gui_height();
    var _txt   = code_editor_text;
    var _cur   = code_editor_cursor;
    var _mx = device_mouse_x_to_gui(0);
    var _my = device_mouse_y_to_gui(0);
	// Reset conflict state — the draw loop below will "trip" it back to true if a conflict still exists
    if (instance_exists(code_editor_node)) code_editor_node.is_conflicted = false;
	
	var _pulse = abs(sin(current_time * 0.01)); // Consistent pulse with the memory bar
	
// --- HELPER: Checks if an address hits a conflict OR a loaded Asset ---
    var _is_danger_addr = function(_addr) {
        // 1. EXEMPT COMMON AREAS (Matches Memory Bar Filter)
        if (_addr <= 0x07FF) return false;      // ZP, Stack, OS, Screen
        if (_addr >= 0xD000 && _addr <= 0xDFFF) return false; // Hardware I/O

        // 2. CHECK ASSETS (Music, Sprites, Bitmaps)
        if (instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = _am.asset_list[| _ai];
                var _asz = 0;
                if (_a.type == "SPRITE_SET" || _a.type == "SID_MUSIC") {
                    _asz = (_a.file != "" && buffer_exists(_a.buffer)) ? max(1, buffer_get_size(_a.buffer) - 2) : 0;
                } else if (_a.type == "BITMAP") {
                    _asz = (_a.file != "" && buffer_exists(_a.buffer)) ? 10192 : 0;
                } else continue;
                
                if (_asz == 0) continue;
                if (_addr >= _a.address && _addr < _a.address + _asz) return true;
            }
        }
        return false;
    };

    // ═════════════════════════════════════════════════════════
    // FONT CONFIG — change this one line to switch editor font
    // ═════════════════════════════════════════════════════════
    var _code_font = code_editor_fonts[code_editor_font_index];

  // ─── Backdrop ───
    draw_set_alpha(0.85);
    draw_set_color(c_black);
    draw_rectangle(0, 0, _gui_w, _gui_h, false);
    draw_set_alpha(1.0);
    // ─── Panel ───
    var _pw = 1200;
    var _ph = 900;
    var _px = (_gui_w - _pw) / 2;
    var _py = (_gui_h - _ph) / 2;
    draw_set_color(make_color_rgb(20, 22, 30));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, false);
    draw_set_color(make_color_rgb(50, 140, 100));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, true);
    // ─── Header ───
    draw_set_color(make_color_rgb(40, 100, 70));
    draw_rectangle(_px, _py, _px + _pw, _py + 28, false);
    draw_set_font(_code_font);
    draw_set_color(c_white);
	
draw_set_halign(fa_center);
    var _desc = instance_exists(code_editor_node) ? code_editor_node.code_descriptor : "Code Block";
    draw_text(_px + _pw / 2, _py + 6, "CODE EDITOR: " + string_upper(_desc));
    draw_set_halign(fa_left);

// ─── Close button [X] ───
    var _close_w = 60;
    var _close_h = 22;
    var _close_x = _px + _pw - _close_w - 6;
    var _close_y = _py + 3;
	
	// ─── Export button ───
	var _exp_w = 80;
	var _exp_h = 22;
	var _exp_x = _close_x - _exp_w - 10; // 10px gap to the left of Close
	var _exp_y = _py + 3;
	var _exp_hover = (_mx >= _exp_x && _mx <= _exp_x + _exp_w
                     && _my >= _exp_y && _my <= _exp_y + _exp_h);

	draw_set_color(_exp_hover ? make_color_rgb(50, 100, 180) : make_color_rgb(30, 50, 80));
	draw_rectangle(_exp_x, _exp_y, _exp_x + _exp_w, _exp_y + _exp_h, false);
	draw_set_color(_exp_hover ? c_white : make_color_rgb(120, 160, 220));
	draw_rectangle(_exp_x, _exp_y, _exp_x + _exp_w, _exp_y + _exp_h, true);
	
	draw_set_font(fnt_c64_code);
	draw_set_halign(fa_center);
	draw_set_valign(fa_middle);
	draw_text(_exp_x + _exp_w / 2, _exp_y + _exp_h / 2, "EXPORT");
	
	// Export Click Logic
	if (_exp_hover && mouse_check_button_pressed(mb_left)) {
		var _def_name = instance_exists(code_editor_node) ? code_editor_node.code_descriptor + ".asm" : "code_export.txt";
		var _filename = get_save_filename("Assembly Files|*.asm;*.txt|All Files|*.*", _def_name);
		// A native file dialog takes focus, so the key-up that ends the keypress is
		// delivered to the dialog and not to the game. GameMaker is left thinking the
		// key is still held, and keyboard_check_pressed() needs an up->down edge — so
		// ESC silently stops working until the input state is reset. This is why ESC
		// only failed after SOME asset operations: scr_asset_sid_import already did
		// this, every other importer did not.
		io_clear();
		if (_filename != "") {
			var _buf = buffer_create(string_byte_length(code_editor_text), buffer_fixed, 1);
			buffer_write(_buf, buffer_text, code_editor_text);
			buffer_save(_buf, _filename);
			buffer_delete(_buf);
		}
	}
    var _close_hover = (_mx >= _close_x && _mx <= _close_x + _close_w
                     && _my >= _close_y && _my <= _close_y + _close_h);
    draw_set_color(_close_hover ? make_color_rgb(180, 50, 50) : make_color_rgb(60, 30, 30));
    draw_rectangle(_close_x, _close_y, _close_x + _close_w, _close_y + _close_h, false);
    draw_set_color(_close_hover ? c_white : make_color_rgb(200, 120, 120));
    draw_rectangle(_close_x, _close_y, _close_x + _close_w, _close_y + _close_h, true);
    draw_set_font(_code_font);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
	draw_set_font(fnt_c64_code)
    draw_text(_close_x + _close_w / 2, _close_y + _close_h / 2, "CLOSE");
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

// ─── Close button click (commit + close) ───
if (_close_hover && mouse_check_button_pressed(mb_left)) {
        if (instance_exists(code_editor_node)) code_editor_node.code_cache_dirty = true;
    code_editor_symbol_cache_dirty = true;
        scr_code_editor_close(true);
        return;
    }

    // ─── Code area layout ───
    draw_set_font(_code_font);
    var _line_h    = string_height("A") + 4;
    var _gutter_w  = 70;
    var _code_x    = _px + _gutter_w + 30;
    var _code_y    = _py + 34;
    var _code_w    = _pw - _gutter_w - 12;
    var _code_h    = _ph - 70;
    var _max_lines = floor(_code_h / _line_h);

    // Split text into lines
    var _lines = (_txt == "") ? [""] : string_split(_txt, "\n");
    var _total_lines = array_length(_lines);

    // ─── Find cursor line and column ───
// ─── Find cursor line and column using cached line starts ───
    var _cur_line = 0;
    var _cur_col  = 0;
    if (array_length(code_editor_line_starts) == _total_lines) {
        var _lo = 0;
        var _hi = _total_lines - 1;
        while (_lo < _hi) {
            var _mid = _lo + ((_hi - _lo + 1) >> 1);
            if (code_editor_line_starts[_mid] <= _cur) {
                _lo = _mid;
            } else {
                _hi = _mid - 1;
            }
        }
        _cur_line = _lo;
        _cur_col  = _cur - code_editor_line_starts[_lo];
    }

    // Auto-scroll only when cursor moves, not while scrollbar dragging
    if (!code_editor_scrollbar_dragging && code_editor_cursor != code_editor_last_cursor) {
        if (_cur_line < code_editor_scroll_y) code_editor_scroll_y = _cur_line;
        if (_cur_line >= code_editor_scroll_y + _max_lines) code_editor_scroll_y = _cur_line - _max_lines + 1;
    }
	code_editor_scroll_y = clamp(code_editor_scroll_y, 0, max(0, _total_lines - _max_lines));

// ─── Horizontal scroll: compute max line width (cached) ───
    draw_set_font(_code_font);
    if (code_editor_cache_dirty || code_editor_max_line_px == 0) {
        code_editor_max_line_px = 0;
        for (var _mi = 0; _mi < _total_lines; _mi++) {
            var _lw = string_width(_lines[_mi]) + 40;
            if (_lw > code_editor_max_line_px) code_editor_max_line_px = _lw;
        }
    }
    var _max_line_px = code_editor_max_line_px;
    var _hscroll_max = max(0, _max_line_px - _code_w + _gutter_w);
    code_editor_scroll_x = clamp(code_editor_scroll_x, 0, _hscroll_max);
    var _sx = code_editor_scroll_x;

// Auto-scroll horizontally to keep cursor visible (only when cursor moves)
    if (!code_editor_hscrollbar_dragging && code_editor_cursor != code_editor_last_cursor) {
        var _cur_line_text = _lines[_cur_line];
        var _cursor_px = string_width(string_copy(_cur_line_text, 1, _cur_col));
        // Scrolled off right edge — bring cursor into view with some margin
        if (_cursor_px - code_editor_scroll_x > _code_w - 30)
            code_editor_scroll_x = _cursor_px - _code_w + 40;
        // Scrolled off left edge — snap to cursor with small left margin
        if (_cursor_px < code_editor_scroll_x)
            code_editor_scroll_x = max(0, _cursor_px - 10);
        _sx = code_editor_scroll_x;
    }
    // Update last_cursor AFTER both vertical and horizontal auto-scroll
    code_editor_last_cursor = code_editor_cursor;

    // Mouse wheel scroll
    if (mouse_wheel_up())   code_editor_scroll_y = max(0, code_editor_scroll_y - 3);
    if (mouse_wheel_down()) code_editor_scroll_y = min(max(0, _total_lines - _max_lines), code_editor_scroll_y + 3);

    // ─── Selection state ───
    var _has_sel = (code_editor_sel_start != -1 && code_editor_sel_start != code_editor_sel_end);
    var _sel_lo  = _has_sel ? min(code_editor_sel_start, code_editor_sel_end) : 0;
    var _sel_hi  = _has_sel ? max(code_editor_sel_start, code_editor_sel_end) : 0;

// ─── Pre-compute PC address per line (cached) ───
var _node_pc = instance_exists(code_editor_node) ? code_editor_node.pc_address : 0;
if (_txt != code_editor_cached_text || _node_pc != code_editor_cached_pc) {
        code_editor_cache_dirty        = true;
        code_editor_symbol_cache_dirty = true;
    code_editor_cached_text  = _txt;
    code_editor_cached_pc    = _node_pc;
}


if (code_editor_cache_dirty) {
    var _rpc = instance_exists(code_editor_node) ? code_editor_node.pc_address : 0x080E;
    code_editor_cached_pcs  = array_create(_total_lines, 0);
    var _full_parsed = scr_parse_asm_text(_txt);
    var _fpi = 0;
    
    var _rep_stack = [];
    code_editor_cached_line_cyc = array_create(_total_lines, 0);
    code_editor_cached_run_cyc  = array_create(_total_lines, 0);
    var _running_cyc = 0;

    for (var _pi = 0; _pi < _total_lines; _pi++) {
        code_editor_cached_pcs[_pi] = _rpc;
        code_editor_cached_run_cyc[_pi] = _running_cyc;
        var _pline = string_trim(_lines[_pi]);
        var _p_low = string_lower(_pline);

        if (_pline == "" || string_char_at(_pline, 1) == ";" || (string_length(_pline) >= 2 && string_copy(_pline, 1, 2) == "//")) continue;

        if (string_pos("repeat", _p_low) == 1) {
            var _open = string_pos("{", _pline);
            if (_open > 0) {
                var _digit_str = string_digits(string_copy(_pline, 7, _open - 7));
                var _cnt = (_digit_str != "") ? real(_digit_str) : 1;
                array_push(_rep_stack, { s_pc: _rpc, s_fpi: _fpi, s_cyc: _running_cyc, count: _cnt });
            }
            continue;
        }

        if (string_char_at(_pline, 1) == "}") {
            if (array_length(_rep_stack) > 0) {
                var _rData = array_pop(_rep_stack);
                var _blockSize = _rpc - _rData.s_pc;
                var _blockInst = _fpi - _rData.s_fpi;
                var _blockCyc  = _running_cyc - _rData.s_cyc;
                _rpc += (_rData.count - 1) * _blockSize;
                _fpi += (_rData.count - 1) * _blockInst;
                _running_cyc += (_rData.count - 1) * _blockCyc;
            }
            continue;
        }
        
        if (string_char_at(_pline, 1) == "{") continue;

       // Skip any _line_map_ sentinel entries
        while (_fpi < array_length(_full_parsed) && string_lower(_full_parsed[_fpi][0]) == "_line_map_") _fpi++;

        if (_fpi < array_length(_full_parsed)) {
            var _pinst = _full_parsed[_fpi];
            var _ptype = string_lower(_pinst[0]);
            _fpi++;
            // Skip the _line_map_ that follows this instruction
            while (_fpi < array_length(_full_parsed) && string_lower(_full_parsed[_fpi][0]) == "_line_map_") _fpi++;
            
            if (_ptype == "pc") {
                _rpc = _pinst[1];
            } else if (_ptype == "byte" || _ptype == "string") {
                _rpc += array_length(_pinst) - 1;
            } else if (_ptype != "label" && _ptype != "const") {
                _rpc += obj_opCodeManager.get_size(_ptype);
                var _cyc = obj_opCodeManager.get_cycles(_ptype);
                code_editor_cached_line_cyc[_pi] = _cyc;
                _running_cyc += _cyc;
            }
        }
    }

    // --- REFRESH STATS & CONFLICT SCAN (Single Pass) ---
    var _sb = 0; var _sc = 0;
    var _has_conflict = false;

    for (var _si = 0; _si < array_length(_full_parsed); _si++) {
        var _sinst = _full_parsed[_si];
        var _sm    = string_lower(_sinst[0]);
        
        // Stat counting
        if (_sm == "byte" || _sm == "string") {
            _sb += array_length(_sinst) - 1;
        } else if (_sm != "pc" && _sm != "label" && _sm != "const") {
            _sb += obj_opCodeManager.get_size(_sm);
            _sc += obj_opCodeManager.get_cycles(_sm);
        }

        // Conflict Scanning
        if (!_has_conflict && array_length(_sinst) > 1 && is_real(_sinst[1])) {
            // Check if this is a JMP/JSR/Branch (exempt from operand danger)
            var _is_jump = (string_pos("jsr", _sm) > 0 || string_pos("jmp", _sm) > 0 || 
                           (string_char_at(_sm, 1) == "b" && _sm != "bit")); // Exempt branches, but NOT 'BIT'

            if (!_is_jump && (string_pos("_abs", _sm) > 0 || string_pos("_ind", _sm) > 0 || string_pos("_zp", _sm) > 0 || _sm == "const")) {
                if (_is_danger_addr(_sinst[1])) _has_conflict = true;
            }
        }
    }
    
    // Also check if any instruction's own location is in a danger zone
    if (!_has_conflict) {
        for (var _ci = 0; _ci < _total_lines; _ci++) {
            if (_is_danger_addr(code_editor_cached_pcs[_ci])) { _has_conflict = true; break; }
        }
    }

    code_editor_cached_stats = [_sb, _sc];
    if (instance_exists(code_editor_node)) code_editor_node.is_conflicted = _has_conflict;

    // ─── Build scope-depth cache (for colouring contained labels) ───
    // Counts non-repeat { } nesting. A label at depth > 0 is scope-contained.
    code_editor_scope_depth = array_create(_total_lines, 0);
    var _sd_depth = 0;
    for (var _sd = 0; _sd < _total_lines; _sd++) {
        var _sd_t   = string_trim(_lines[_sd]);
        var _sd_low = string_lower(_sd_t);
        var _sd_is_repeat = (string_pos("repeat", _sd_low) == 1 && string_pos("{", _sd_t) > 0);
        // Record depth for this line BEFORE applying its own closing brace,
        // so the label line itself reads the depth it sits inside.
        if (_sd_t == "}") {
            _sd_depth = max(0, _sd_depth - 1);
            code_editor_scope_depth[_sd] = _sd_depth;
        } else {
            code_editor_scope_depth[_sd] = _sd_depth;
            // A non-repeat line ending in '{' opens a scope for subsequent lines
            if (!_sd_is_repeat && _sd_t != "" && string_char_at(_sd_t, string_length(_sd_t)) == "{") {
                _sd_depth++;
            }
        }
    }

    // ─── Build auto-indent cache ───
    code_editor_indent_cache = array_create(_total_lines, 0);
    var _last_label_line = -1;
    var _last_flow_line  = -1;
    for (var _ic = 0; _ic < _total_lines; _ic++) {
        var _ic_trim = string_trim(_lines[_ic]);
        var _ic_low  = string_lower(_ic_trim);
        var _ic_colon = string_pos(":", _ic_trim);
        var _ic_is_label = (_ic_colon > 1 && string_pos(" ", string_copy(_ic_trim, 1, _ic_colon - 1)) == 0);
        var _ic_is_comment = (string_char_at(_ic_trim, 1) == ";" || (string_length(_ic_trim) >= 2 && string_copy(_ic_trim, 1, 2) == "//"));
        var _ic_is_flow = (string_pos("jmp", _ic_low) == 1 || string_pos("jsr", _ic_low) == 1 ||
                           string_pos("rts", _ic_low) == 1 || string_pos("rti", _ic_low) == 1);
        if (_ic_is_label) {
            _last_label_line = _ic;
            _last_flow_line  = -1;
        }
        if (_ic_is_flow) {
            _last_flow_line = _ic;
        }
        if (!_ic_is_label && !_ic_is_comment && _last_label_line >= 0 && _last_flow_line < _last_label_line) {
            code_editor_indent_cache[_ic] = 20;
        }
    }

    // ─── Build cumulative line-start offset cache ───
    code_editor_line_starts = array_create(_total_lines, 0);
    var _running_offset = 0;
    for (var _lso = 0; _lso < _total_lines; _lso++) {
        code_editor_line_starts[_lso] = _running_offset;
        _running_offset += string_length(_lines[_lso]) + 1;
    }

    code_editor_cache_dirty        = false;
    code_editor_symbol_cache_dirty = false;
}
	
	
	
    var _line_pcs = code_editor_cached_pcs;

// ─── Build symbol lookup for operand colouring (cached) ───
    if (code_editor_symbol_cache_dirty || ds_map_size(code_editor_local_labels) == 0) {
        if (ds_exists(code_editor_local_labels, ds_type_map)) ds_map_destroy(code_editor_local_labels);
        if (ds_exists(code_editor_local_consts, ds_type_map)) ds_map_destroy(code_editor_local_consts);
        if (ds_exists(code_editor_global_labels, ds_type_map)) ds_map_destroy(code_editor_global_labels);
        code_editor_local_labels  = ds_map_create();
        code_editor_local_consts  = ds_map_create();
        code_editor_global_labels = ds_map_create();
        for (var _li2 = 0; _li2 < _total_lines; _li2++) {
            var _lt = string_trim(_lines[_li2]);
            var _colon = string_pos(":", _lt);
            if (_colon > 1 && string_pos(" ", string_copy(_lt, 1, _colon - 1)) == 0) {
                ds_map_add(code_editor_local_labels, string_copy(_lt, 1, _colon - 1), true);
            }
            var _eq = string_pos("=", _lt);
            if (_eq > 1) {
                var _cname = string_trim(string_copy(_lt, 1, _eq - 1));
                var _cval_str = string_trim(string_copy(_lt, _eq + 1, string_length(_lt) - _eq));
                if (_cname != "" && string_pos(" ", _cname) == 0 && string_char_at(_cname, 1) != "." && string_char_at(_cname, 1) != "*") {
                    ds_map_add(code_editor_local_consts, string_upper(_cname), _asm_val(_cval_str));
                }
            }
        }
        var _glob_lab_map = code_editor_global_labels;
        with (obj_c64_node) {
            if (node_type == "LABEL" && is_connected && array_length(instructions) > 0 && array_length(instructions[0]) > 1) {
                ds_map_add(_glob_lab_map, string(instructions[0][1]), true);
            }
        }
    }
    var _local_labels  = code_editor_local_labels;
    var _local_consts  = code_editor_local_consts;
    var _global_labels = code_editor_global_labels;

    // ─── Draw lines (clipped to code area) ───
    draw_set_font(_code_font);


    for (var _li = 0; _li < _max_lines; _li++) {
        var _line_idx = _li + code_editor_scroll_y;
        if (_line_idx >= _total_lines) break;

        var _ly = _code_y + (_li * _line_h);
        var _line_text = _lines[_line_idx];
        var _code_x_s = _code_x - _sx; // horizontally scrolled code x

        // Calculate char offset for this line start (cached)
        var _line_start = code_editor_line_starts[_line_idx];

// ─── Consolidated Line Classification ───
        var _trimmed = string_trim(_line_text);
        var _tlow    = string_lower(_trimmed);
        
        // Initialize ALL flags to false
        var _is_comment  = (string_char_at(_trimmed, 1) == ";" || (string_length(_trimmed) >= 2 && string_copy(_trimmed, 1, 2) == "//"));
        var _is_label    = false;
        var _is_valid    = false;
        var _is_byte_dir = false;
        var _is_org_dir  = false;
        var _is_const    = false;
        var _is_rep_line = (string_pos("repeat", _tlow) > 0 || string_pos("{", _tlow) > 0 || string_pos("}", _tlow) > 0);

        if (_trimmed != "" && !_is_comment) {
            // Anonymous / named multi-label declaration "!:" or "!name:" — label line
            if (string_char_at(_trimmed, 1) == "!" && string_pos(":", _trimmed) > 1) {
                _is_label = true;
                _is_valid = true;
            }
            // Scope braces — valid structural lines
            else if (_trimmed == "}" || string_char_at(_trimmed, string_length(_trimmed)) == "{") {
                _is_valid = true;
            }
            // Check for Label
            else if (string_pos(":", _trimmed) > 0 && string_pos(" ", string_copy(_trimmed, 1, string_pos(":", _trimmed) - 1)) == 0) {
                _is_label = true;
                _is_valid = true;
            } else {
                // Check for Instructions
                var _known = "adc,and,asl,bcc,bcs,beq,bit,bmi,bne,bpl,brk,bvc,bvs,clc,cld,cli,clv,cmp,cpx,cpy,dec,dex,dey,eor,inc,inx,iny,jmp,jsr,lda,ldx,ldy,lsr,nop,ora,pha,php,pla,plp,rol,ror,rti,rts,sbc,sec,sed,sei,sta,stx,sty,tax,tay,tsx,txa,txs,tya,lax,sax,dcp,isc,rla,rra,slo,sre,anc,anc2,alr,arr,axs";
                var _sp2 = string_pos(" ", _trimmed);
                var _mnem_check = (_sp2 > 0) ? string_copy(_tlow, 1, _sp2 - 1) : _tlow;
                
                // Check Directives
                _is_byte_dir = (string_copy(_tlow, 1, 5) == ".byte" || string_copy(_tlow, 1, 7) == ".string");
                var _is_star_eq = false;
                if (string_char_at(_trimmed, 1) == "*") {
                    var _after_star = string_trim(string_delete(_trimmed, 1, 1));
                    if (string_char_at(_after_star, 1) == "=") _is_star_eq = true;
                }
                _is_org_dir  = !_is_byte_dir && (string_copy(_mnem_check, 1, 3) == ".pc" || _is_star_eq || (string_length(_mnem_check) >= 2 && (string_copy(_mnem_check, 1, 2) == "*." || string_copy(_mnem_check, 1, 2) == ".*")));
                
                // Check Constants
                var _eq_chk  = string_pos("=", _trimmed);
                var _equ_chk = string_pos(" EQU ", string_upper(_trimmed));
                if (_eq_chk > 1 || _equ_chk > 1) {
                    var _const_name = string_trim(string_copy(_trimmed, 1, (_eq_chk > 1 ? _eq_chk : _equ_chk) - 1));
                    if (_const_name != "" && string_pos(" ", _const_name) == 0 && string_char_at(_const_name, 1) != "." && string_char_at(_const_name, 1) != "*") {
                        _is_const = true;
                    }
                }

                // Set final validity
                _is_valid = (string_pos("," + _mnem_check + ",", "," + _known + ",") > 0) || _is_byte_dir || _is_org_dir || _is_const || _is_rep_line;
            }
        }

draw_set_font(_code_font);

      // Clip code text using surface clipping instead of gpu_scissor
        // (gpu_scissor uses display coords, not GUI coords)

        // ─── Auto-indent: read from cache ───
        var _auto_indent = (code_editor_indent_cache[_line_idx]);

        // ─── Indent guide line (dashed) ───
        if (_auto_indent > 0) {
            draw_set_color(make_color_rgb(40, 45, 55));
            var _guide_x = _code_x_s + 8;
            for (var _dy = 0; _dy < _line_h; _dy += 4) {
                draw_line(_guide_x, _ly + _dy, _guide_x, _ly + min(_dy + 2, _line_h));
            }
        }

        // ─── Selection highlight for this line ───
        if (_has_sel) {
            var _line_end = _line_start + string_length(_line_text);
            if (_sel_lo < _line_end && _sel_hi > _line_start) {
                var _hl_start = max(0, _sel_lo - _line_start);
                var _hl_end   = min(string_length(_line_text), _sel_hi - _line_start);
                var _hx1 = _code_x_s + _auto_indent + string_width(string_copy(_line_text, 1, _hl_start));
                var _hx2 = _code_x_s + _auto_indent + string_width(string_copy(_line_text, 1, _hl_end));
                draw_set_alpha(0.3);
                draw_set_color(make_color_rgb(80, 160, 220));
                draw_rectangle(_hx1, _ly, _hx2, _ly + _line_h, false);
                draw_set_alpha(1.0);
            }
        }


        // ─── Syntax colouring ───
        if (_is_comment) {
            // Comments — grey-green
            draw_set_color(make_color_rgb(90, 120, 98));
            draw_text(_code_x_s + _auto_indent, _ly, _line_text);

        } else if (_is_label) {
            var _lbl_name = string_copy(_trimmed, 1, string_pos(":", _trimmed) - 1);
            if (string_char_at(_trimmed, 1) == "!") {
                draw_set_color(make_color_rgb(255, 160, 90));   // multi-label — amber
            } else if (string_char_at(_lbl_name, 1) == ".") {
                draw_set_color(make_color_rgb(200, 255, 255));
            } else if (code_editor_scope_depth[_line_idx] > 0) {
                draw_set_color(make_color_rgb(255, 120, 255));   // scope-contained label — pink
            } else {
                draw_set_color(c_white);
            }
            draw_text(_code_x_s, _ly, _line_text);

        } else if (!_is_valid && _trimmed != "") {
            // Nonsense — dark grey
            draw_set_color(make_color_rgb(90, 90, 90));
            draw_text(_code_x_s + _auto_indent, _ly, _line_text);

} else if (_is_const) {
            // Constant assignment: name = $addr
            var _eq_p  = string_pos("=", _line_text);
            if (_eq_p > 1) {
                var _cname = string_copy(_line_text, 1, _eq_p - 1);
                var _cval  = string_copy(_line_text, _eq_p, string_length(_line_text) - _eq_p + 1);
                
var _cname_trim = string_trim(_cname);
                var _const_is_clashing = false;
                if (ds_map_exists(_local_consts, string_upper(_cname_trim))) {
                    var _c_val = ds_map_find_value(_local_consts, string_upper(_cname_trim));
					if (_is_danger_addr(_c_val)) {
                        _const_is_clashing = true;
                        if (instance_exists(code_editor_node)) code_editor_node.is_conflicted = true;
                    }
                }

                // Detect inline comment within the constant value
                var _c_icmt = 0;
                var _c_semi = string_pos(";", _cval);
                if (_c_semi > 0) _c_icmt = _c_semi;
                for (var _cci = 1; _cci <= string_length(_cval) - 1; _cci++) {
                    if (string_copy(_cval, _cci, 2) == "//") {
                        _c_icmt = (_c_icmt > 0) ? min(_c_icmt, _cci) : _cci;
                        break;
                    }
                }

                // Draw Variable Name
                draw_set_color(_const_is_clashing ? merge_color(make_color_rgb(110, 150, 220), c_red, _pulse) : make_color_rgb(110, 150, 220)); 
                draw_text(_code_x_s, _ly, _cname);
                
                // Draw Value and optional Comment
                var _val_col = _const_is_clashing ? merge_color(make_color_rgb(200, 120, 160), c_red, _pulse) : make_color_rgb(200, 120, 160);
                if (_c_icmt > 0) {
                    var _cval_part = string_copy(_cval, 1, _c_icmt - 1);
                    var _ccmt_part = string_copy(_cval, _c_icmt, string_length(_cval));
                    
                    draw_set_color(_val_col);
                    draw_text(_code_x_s + string_width(_cname), _ly, _cval_part);
                    
                    draw_set_color(make_color_rgb(80, 210, 100)); // Main Comment Green
                    draw_text(_code_x_s + string_width(_cname) + string_width(_cval_part), _ly, _ccmt_part);
                } else {
                    draw_set_color(_val_col);
                    draw_text(_code_x_s + string_width(_cname), _ly, _cval);
                }
            } else {
                draw_set_color(make_color_rgb(255, 180, 60));
                draw_text(_code_x_s, _ly, _line_text);
            }

} else if (_is_rep_line) {
            // Repeat syntax — purple
            draw_set_color(make_color_rgb(110, 50, 180));
            draw_text(_code_x_s + _auto_indent, _ly, _line_text);

        } else if (_is_byte_dir || _is_org_dir) {
            // Directive line — teal keyword, amber values
            var _sp3    = string_pos(" ", _trimmed);
            var _idt2   = string_length(_line_text) - string_length(string_trim_start(_line_text));
            var _idt2px = string_width(string_copy(_line_text, 1, _idt2));
            if (_idt2 > 0) {
                draw_set_color(make_color_rgb(40, 40, 50));
                draw_text(_code_x_s + _auto_indent, _ly, string_copy(_line_text, 1, _idt2));
            }
            draw_set_color(make_color_rgb(0, 210, 180));   // teal keyword
            if (_sp3 > 0) {
                var _dkw  = string_copy(_trimmed, 1, _sp3 - 1);
                var _dval = string_copy(_trimmed, _sp3 + 1, string_length(_trimmed) - _sp3);
                draw_text(_code_x_s + _auto_indent + _idt2px, _ly, _dkw);
                var _d_icmt = 0;
                var _d_semi = string_pos(";", _dval);
                if (_d_semi > 0) _d_icmt = _d_semi;
                for (var _dci = 1; _dci <= string_length(_dval) - 1; _dci++) {
                    if (string_copy(_dval, _dci, 2) == "//") {
                        _d_icmt = (_d_icmt > 0) ? min(_d_icmt, _dci) : _dci;
          break;
                    }
                }
                var _dval_x = _code_x_s + _auto_indent + _idt2px + string_width(_dkw + " ");
                if (_d_icmt > 0) {
                    var _dval_part = string_copy(_dval, 1, _d_icmt - 1);
                    var _dcmt_part = string_copy(_dval, _d_icmt, string_length(_dval));
                    draw_set_color(make_color_rgb(255, 200, 80));
                    draw_text(_dval_x, _ly, _dval_part);
                    draw_set_color(make_color_rgb(80, 160, 100));
                    draw_text(_dval_x + string_width(_dval_part), _ly, _dcmt_part);
                } else {
					var _is_str_dir = (string_copy(string_lower(_trimmed), 1, 7) == ".string");
                    draw_set_color(_is_str_dir ? make_color_rgb(255, 140, 200) : make_color_rgb(255, 200, 80));
                    draw_text(_dval_x, _ly, _dval);
                }
            } else {
                draw_text(_code_x_s + _auto_indent + _idt2px, _ly, _trimmed);
            }

        } else {
			
			
			
            // Valid instruction line
            var _sp = string_pos(" ", _trimmed);
            if (_sp > 0 && _trimmed != "") {
                var _indent    = string_length(_line_text) - string_length(string_trim_start(_line_text));
                var _mnem_end  = _indent + _sp;
                var _indent_px = string_width(string_copy(_line_text, 1, _indent));
                var _mnem_px   = string_width(string_copy(_line_text, 1, _mnem_end));

                // Leading whitespace (dim)
                if (_indent > 0) {
                    draw_set_color(make_color_rgb(40, 40, 50));
                    draw_text(_code_x_s + _auto_indent, _ly, string_copy(_line_text, 1, _indent));
                }

                // Mnemonic (blue)
                draw_set_color(make_color_rgb(140, 200, 255));
                draw_text(_code_x_s + _auto_indent + _indent_px, _ly, string_copy(_line_text, _indent + 1, _sp - 1));

                // Operand — tinted by format
                var _after_mnem = string_delete(_line_text, 1, _mnem_end);
                var _op_text    = string_trim(_after_mnem);

                // ── Detect inline comment within the operand text ──
                var _icmt_pos = 0;
                var _semi = string_pos(";", _op_text);
                if (_semi > 0) _icmt_pos = _semi;
                for (var _sci = 1; _sci <= string_length(_op_text) - 1; _sci++) {
                    if (string_copy(_op_text, _sci, 2) == "//") {
                        _icmt_pos = (_icmt_pos > 0) ? min(_icmt_pos, _sci) : _sci;
                        break;
                    }
                }
                // Pure operand (comment stripped) used for colour detection
                var _op_pure = (_icmt_pos > 0)
                    ? string_trim(string_copy(_op_text, 1, _icmt_pos - 1))
                    : _op_text;

				var _op_col    = c_white;
                var _sym_check = _op_pure;
                
                // 1. Check and strip '#'
                var _has_hash = (string_char_at(_sym_check, 1) == "#");
                if (_has_hash) _sym_check = string_delete(_sym_check, 1, 1);
                
				// 2. Strip brackets for indirect addressing '()'
                // Flag ($xxxx) 16-bit indirect as invalid — only ZP indirect is legal on 6502
                var _is_invalid_indirect = false;
                if (string_char_at(_sym_check, 1) == "(") {
                    var _inner = string_replace_all(string_delete(_sym_check, 1, 1), ")", "");
                    _inner = string_trim(string_copy(_inner, 1, string_pos(",", _inner + ",") - 1));
                    // If inner value is a 16-bit address ($xxxx, >=$100) it's illegal indirect
                    if (string_char_at(_inner, 1) == "$" && string_length(_inner) > 3) {
                        _is_invalid_indirect = true;
                    }
                    _sym_check = string_delete(_sym_check, 1, 1);
                }
                _sym_check = string_replace_all(_sym_check, ")", "");
                
                // 3. Strip commas and register suffixes (e.g. ,x or ,y)
                var _comma_pos = string_pos(",", _sym_check);
                if (_comma_pos > 0) {
                    _sym_check = string_copy(_sym_check, 1, _comma_pos - 1);
                }
                
				// Strip arithmetic offset (+n / -n) for colour lookup only
				var _plus_p  = string_pos("+", _sym_check);
				var _minus_p = string_pos("-", _sym_check);
				if (_plus_p > 1)  _sym_check = string_trim(string_copy(_sym_check, 1, _plus_p - 1));
				else if (_minus_p > 1) _sym_check = string_trim(string_copy(_sym_check, 1, _minus_p - 1));
				_sym_check = string_trim(_sym_check);
				var _has_dollar = (string_char_at(_sym_check, 1) == "$");

                // Multi-label reference (!+, !-, !loop+, !loop-) — check the RAW
                // operand before offset-stripping mangled it.
                var _is_multi_ref = (string_char_at(_op_pure, 1) == "!");

 // Check formatting using the fully cleaned _sym_check
                var _resolved_addr = -1;

                if (_is_multi_ref) {
                    _op_col = make_color_rgb(255, 160, 90);   // multi-label ref — amber
                } else
                if (_is_invalid_indirect) {
                    _op_col = make_color_rgb(255, 60, 60);    // invalid indirect — red/error
                } else
                if (string_char_at(_sym_check, 1) == "%") {
                    _op_col = make_color_rgb(100, 150, 255);  // binary
                } else if (_has_hash && _has_dollar) {
                    _op_col = make_color_rgb(255, 200, 20);   // #$xx immediate hex
                } else if (_has_hash) {
                    _op_col = make_color_rgb(200, 255, 20);   // #xx immediate decimal
                } else if (_has_dollar || _asm_is_dec(_sym_check)) {
                    _op_col = make_color_rgb(255, 255, 10);   // Default yellow
                    _resolved_addr = _asm_val(_sym_check);
                }
                else if (_sym_check != "" && string_pos("HW_", string_upper(_sym_check)) == 1
                           && ds_map_exists(global.named_loc_map, string_upper(_sym_check))) {
                    _op_col = make_color_rgb(255, 140, 40);   // HW_ hardware var — orange
                    _resolved_addr = ds_map_find_value(global.named_loc_map, string_upper(_sym_check));
                } else if (_sym_check != "" && string_pos("UV_", string_upper(_sym_check)) == 1
                           && ds_map_exists(global.named_loc_map, string_upper(_sym_check))) {
                    _op_col = make_color_rgb(40, 220, 255);   // UV_ user var — cyan
                    _resolved_addr = ds_map_find_value(global.named_loc_map, string_upper(_sym_check));
                } else if (_sym_check != "" && ds_map_exists(_local_labels, _sym_check)) {
                    _op_col = make_color_rgb(80, 220, 80);    // local label — green
                } else if (_sym_check != "" && ds_map_exists(_global_labels, _sym_check)) {
                    _op_col = make_color_rgb(220, 80, 255);   // global/IRQ label — magenta
                } else if (_sym_check != "" && variable_struct_exists(global.code_block_labels, _sym_check)) {
                    _op_col = make_color_rgb(80, 220, 180);   // cross-block label — teal
} else if (_sym_check != "" && ds_map_exists(_local_consts, string_upper(_sym_check))) {
                    _op_col = make_color_rgb(255, 180, 60);   // local constant — orange
                    _resolved_addr = ds_map_find_value(_local_consts, string_upper(_sym_check));
                } else if (_sym_check != "" && ds_map_exists(global.named_loc_map, string_upper(_sym_check))) {
                    _op_col = make_color_rgb(255, 180, 60);   // global named constant — orange
                    _resolved_addr = ds_map_find_value(global.named_loc_map, string_upper(_sym_check));
                } else if (_sym_check != "" && !_has_dollar && !_asm_is_dec(_sym_check)
                           && _sym_check != "A" && _sym_check != "a") {
                    _op_col = make_color_rgb(255, 60, 60);    // unrecognised symbol — red/error
                }

				// Global Sync Conflict Flash for operands!
				if (_resolved_addr != -1 && _is_danger_addr(_resolved_addr)) {
				    // ─── Reference Bypass ───
					var _mnem_low = string_lower(_trimmed);
					// We exempt Jumps and Branches, but EXCLUDE 'BIT' because BIT reads memory and can clash
					var _is_jump = (string_pos("jsr", _mnem_low) == 1 || string_pos("jmp", _mnem_low) == 1 || 
					               (string_char_at(_mnem_low, 1) == "b" && string_copy(_mnem_low, 1, 3) != "bit"));

				    if (!_is_jump) {
				        _op_col = merge_color(_op_col, c_red, _pulse * 0.9);
				        if (instance_exists(code_editor_node)) code_editor_node.is_conflicted = true;
				    }
				}

                // ── Draw operand, then inline comment in green if present ──
                if (_icmt_pos > 0) {
                    // _icmt_pos is relative to trimmed _op_text; map back to _after_mnem
                    var _leading_sp = string_length(_after_mnem) - string_length(string_trim_start(_after_mnem));
                    var _cmt_in_after = _leading_sp + _icmt_pos;   // 1-based position of comment in _after_mnem
                    var _op_draw  = string_copy(_after_mnem, 1, _cmt_in_after - 1);
                    var _cmt_draw = string_copy(_after_mnem, _cmt_in_after, string_length(_after_mnem));
                    draw_set_color(_op_col);
                    draw_text(_code_x_s + _auto_indent + _mnem_px, _ly, _op_draw);
                    var _cmt_draw_x = _code_x_s + _auto_indent + _mnem_px + string_width(_op_draw);
                    draw_set_color(make_color_rgb(80, 160, 80));
                    draw_text(_cmt_draw_x, _ly, _cmt_draw);
                } else {
                    draw_set_color(_op_col);
                    draw_text(_code_x_s + _auto_indent + _mnem_px, _ly, _after_mnem);
                }

			} else if (_trimmed != "") {
                // Check for repeat or brackets
                var _is_repeat_syntax = (string_pos("repeat", string_lower(_trimmed)) > 0 || string_pos("{", _trimmed) > 0 || string_pos("}", _trimmed) > 0);
                
                if (_is_repeat_syntax) {
                    draw_set_color(make_color_rgb(180, 60, 250)); // Purple
                } else {
                    draw_set_color(make_color_rgb(140, 200, 255)); // Default Blue
                }
                
                draw_text(_code_x_s + _auto_indent, _ly, _line_text);
            }
        }

// ─── Cursor (drawn unclipped to ensure visibility on empty lines) ───
        if (!code_editor_find_open && _line_idx == _cur_line && (code_editor_blink mod 40 < 25)) {
            var _cx = _code_x_s + _auto_indent + string_width(string_copy(_line_text, 1, _cur_col));
            draw_set_color(c_white);
            draw_line_width(_cx, _ly, _cx, _ly + _line_h, 2);
        }

        // ─── Mouse hit-test: cursor placement & drag selection ───
        if (!code_editor_find_open
            && _my >= _ly && _my < _ly + _line_h
            && _mx >= _px && _mx < _px + _pw - 10
            && !code_editor_scrollbar_dragging
            && !code_editor_hscrollbar_dragging) {

            var _base_x  = _code_x_s + _auto_indent;
            var _hit_col = string_length(_line_text);
            if (_mx <= _base_x) {
                _hit_col = 0;
            } else {
                for (var _ci = 0; _ci < string_length(_line_text); _ci++) {
                    var _cx1 = _base_x + string_width(string_copy(_line_text, 1, _ci));
                    var _cx2 = _base_x + string_width(string_copy(_line_text, 1, _ci + 1));
                    if (_mx < (_cx1 + _cx2) * 0.5) { _hit_col = _ci; break; }
                }
            }
            var _hit_cur = _line_start + _hit_col;

            if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
                code_editor_cursor          = _hit_cur;
                code_editor_sel_start       = _hit_cur;
                code_editor_sel_end         = _hit_cur;
                code_editor_mouse_selecting = true;
                code_editor_preferred_col   = 0;
            }

            if (code_editor_mouse_selecting && mouse_check_button(mb_left)) {
                code_editor_cursor  = _hit_cur;
                code_editor_sel_end = _hit_cur;
            }
        }
    }

    // ─── Mouse release: finalise selection ───
    if (!code_editor_find_open && mouse_check_button_released(mb_left)) {
        code_editor_mouse_selecting = false;
        if (code_editor_sel_start == code_editor_sel_end) {
            code_editor_sel_start = -1;
            code_editor_sel_end   = -1;
        }
    }

// ─── Overdraw masks to clip text overflow (replaces gpu_scissor) ───
    // Left mask: covers everything left of the code area (including off-panel)
    draw_set_alpha(0.85);
    draw_set_color(c_black);
    draw_rectangle(0, _code_y, _px, _code_y + _code_h, false);
    draw_set_alpha(1.0);
    draw_set_color(make_color_rgb(20, 22, 30));
    draw_rectangle(_px, _code_y, _px + _gutter_w, _code_y + _code_h, false);
    // Right mask: covers everything right of the panel (including off-panel)
    draw_rectangle(_px + _pw - 8, _code_y, _px + _pw, _code_y + _code_h, false);
draw_set_alpha(0.85);
    draw_set_color(c_black);
    draw_rectangle(_px + _pw, _code_y, _gui_w, _code_y + _code_h, false);
    draw_set_alpha(1.0);
    // Redraw panel border over masks
    draw_set_color(make_color_rgb(50, 140, 100));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, true);

// ─── Redraw gutter on top of left mask ───
    draw_set_font(fnt_c64_code); 
    for (var _gi = 0; _gi < _max_lines; _gi++) {
        var _g_line_idx = _gi + code_editor_scroll_y;
        if (_g_line_idx >= _total_lines) break;
        var _g_ly = _code_y + (_gi * _line_h);
        var _g_line_num = string(_g_line_idx + 1);
        draw_set_color(make_color_rgb(50, 100, 70)); // New Gutter Color
        draw_text(_px + 4, _g_ly, _g_line_num);
		
        // PC address
        var _g_trimmed = string_trim(_lines[_g_line_idx]);
        var _g_is_comment = (string_char_at(_g_trimmed, 1) == ";" ||
                            (string_length(_g_trimmed) >= 2 && string_copy(_g_trimmed, 1, 2) == "//"));
        var _g_is_label = (string_pos(":", _g_trimmed) > 0 && 
                           string_pos(" ", string_copy(_g_trimmed, 1, string_pos(":", _g_trimmed) - 1)) == 0);
var _g_is_valid = false;
        var _g_is_const = false;
        var _g_eq = 0;
        if (_g_trimmed != "" && !_g_is_comment) {
            if (_g_is_label) {
                _g_is_valid = true;
            } else {
                var _g_known = "adc,and,asl,bcc,bcs,beq,bit,bmi,bne,bpl,brk,bvc,bvs,clc,cld,cli,clv,cmp,cpx,cpy,dec,dex,dey,eor,inc,inx,iny,jmp,jsr,lda,ldx,ldy,lsr,nop,ora,pha,php,pla,plp,rol,ror,rti,rts,sbc,sec,sed,sei,sta,stx,sty,tax,tay,tsx,txa,txs,tya,lax,sax,dcp,isc,rla,rra,slo,sre,anc,anc2,alr,arr,axs";
                var _g_sp2 = string_pos(" ", _g_trimmed);
                var _g_mnem = string_lower(_g_sp2 > 0 ? string_copy(_g_trimmed, 1, _g_sp2 - 1) : _g_trimmed);
                var _g_tlow = string_lower(_g_trimmed);
                _g_eq = string_pos("=", _g_trimmed);
                if (_g_eq > 1) {
                    var _g_const_name = string_trim(string_copy(_g_trimmed, 1, _g_eq - 1));
                    _g_is_const = (_g_const_name != "" && string_pos(" ", _g_const_name) == 0
                                && string_char_at(_g_const_name, 1) != "."
                                && string_char_at(_g_const_name, 1) != "*");
                }
				_g_is_valid = (string_pos("," + _g_mnem + ",", "," + _g_known + ",") > 0);
                
                // Ensure repeat syntax doesn't get a gutter address
                if (string_pos("repeat", _g_tlow) > 0 || string_pos("{", _g_tlow) > 0 || string_pos("}", _g_tlow) > 0) {
                    _g_is_valid = false;
                }
                
                // Ensure '* =' org directive doesn't get a gutter address
                if (string_char_at(_g_trimmed, 1) == "*") {
                    var _g_after_star = string_trim(string_delete(_g_trimmed, 1, 1));
                    if (string_char_at(_g_after_star, 1) == "=") _g_is_valid = false;
                }
            }
        }
        if (!_g_is_comment && _g_trimmed != "" && _g_is_valid) {
            var _g_pc_hex = decimal_to_hex(_line_pcs[_g_line_idx]);
            while (string_length(_g_pc_hex) < 4) _g_pc_hex = "0" + _g_pc_hex;
            var _g_addr_x = _px + 4 + string_width(_g_line_num + "  ");
            var _this_pc = _line_pcs[_g_line_idx];
            var _is_clashing = false;
            
// Check if the line's actual PC address is in danger
            if (_is_danger_addr(_this_pc)) {
                _is_clashing = true;
            }
            
            // Also make the gutter flash if the line DEFINES a local constant pointing to danger
            if (!_is_clashing && _g_is_const) {
                var _cval_str = string_trim(string_copy(_g_trimmed, _g_eq + 1, 999));
                if (_is_danger_addr(_asm_val(_cval_str))) {
                    _is_clashing = true;
                }
            }

		if (_is_clashing) {
		    // 1. Flash the Gutter Background
		    draw_set_alpha(_pulse * 0.4);
		    draw_set_color(c_red);
		    draw_rectangle(_px + 2, _g_ly, _px + _gutter_w - 2, _g_ly + _line_h, false);
		    draw_set_alpha(1.0);
    
		    // 2. Pulse the Address Text
		    draw_set_color(merge_color(make_color_rgb(255, 50, 50), c_white, _pulse));
    
		    // 3. Trip the Node Flag (Only for PC location clashing)
			if (_is_clashing && instance_exists(code_editor_node)) {
			    code_editor_node.is_conflicted = true;
			}
		} else {
		                draw_set_color(make_color_rgb(45, 155, 90));
            }
            draw_text(_g_addr_x, _g_ly, "$" + string_upper(_g_pc_hex));
        }
    }

// Symbol maps are now cached — destroyed only when cache is rebuilt or editor closes

    // ─── Vertical Scrollbar ───
    if (_total_lines > _max_lines) {
        var _sb_x    = _px + _pw - 8;
        var _sb_y1   = _code_y;
        var _sb_y2   = _code_y + _code_h;
        var _sb_h    = _sb_y2 - _sb_y1;
        var _thumb_h = max(20, _sb_h * (_max_lines / _total_lines));
        var _thumb_y = _sb_y1 + (_sb_h - _thumb_h) * (code_editor_scroll_y / max(1, _total_lines - _max_lines));

        // ── Release drag ──
        if (mouse_check_button_released(mb_left)) {
            code_editor_scrollbar_dragging = false;
        }

        // ── Start drag or page-click ──
        if (mouse_check_button_pressed(mb_left)
            && _mx >= _sb_x && _mx <= _sb_x + 6) {
            if (_my >= _thumb_y && _my <= _thumb_y + _thumb_h) {
                // Grabbed the thumb
                code_editor_scrollbar_dragging    = true;
                code_editor_scrollbar_drag_offset = _my - _thumb_y;
            } else {
                // Clicked the track → page up / page down
                if (_my < _thumb_y) {
                    code_editor_scroll_y = max(0, code_editor_scroll_y - _max_lines);
                } else {
                    code_editor_scroll_y = min(max(0, _total_lines - _max_lines),
                                               code_editor_scroll_y + _max_lines);
                }
            }
        }

        // ── Update position while dragging ──
        if (code_editor_scrollbar_dragging) {
            var _ratio = (_my - code_editor_scrollbar_drag_offset - _sb_y1)
                         / max(1, _sb_h - _thumb_h);
            code_editor_scroll_y = round(clamp(_ratio, 0, 1) * max(0, _total_lines - _max_lines));
            // Recalculate thumb position immediately so it follows the mouse this frame
            _thumb_y = _sb_y1 + (_sb_h - _thumb_h) * (code_editor_scroll_y / max(1, _total_lines - _max_lines));
        }

        // ── Draw track + thumb ──
        draw_set_color(make_color_rgb(30, 30, 50));
        draw_rectangle(_sb_x, _sb_y1, _sb_x + 6, _sb_y2, false);
        draw_set_color(make_color_rgb(
            code_editor_scrollbar_dragging ? 80  : 50,
            code_editor_scrollbar_dragging ? 180 : 140,
            code_editor_scrollbar_dragging ? 130 : 100
        ));
        draw_rectangle(_sb_x, _thumb_y, _sb_x + 6, _thumb_y + _thumb_h, false);
    }

    // ─── Horizontal Scrollbar ───
    if (_hscroll_max > 0) {
        var _hsb_y     = _code_y + _code_h - 8;
        var _hsb_x1    = _px + _gutter_w;
        var _hsb_x2    = _px + _pw - 14;
        var _hsb_w     = _hsb_x2 - _hsb_x1;
        var _hthumb_w  = max(20, _hsb_w * (_code_w / (_max_line_px + _gutter_w)));
        var _hthumb_x  = _hsb_x1 + (_hsb_w - _hthumb_w) * (code_editor_scroll_x / max(1, _hscroll_max));

        // Release drag
        if (mouse_check_button_released(mb_left)) {
            code_editor_hscrollbar_dragging = false;
        }

        // Start drag or page-click
        if (mouse_check_button_pressed(mb_left)
            && _my >= _hsb_y && _my <= _hsb_y + 6
            && _mx >= _hsb_x1 && _mx <= _hsb_x2) {
            if (_mx >= _hthumb_x && _mx <= _hthumb_x + _hthumb_w) {
                code_editor_hscrollbar_dragging    = true;
                code_editor_hscrollbar_drag_offset = _mx - _hthumb_x;
            } else {
                if (_mx < _hthumb_x)
                    code_editor_scroll_x = max(0, code_editor_scroll_x - _code_w);
                else
                    code_editor_scroll_x = min(_hscroll_max, code_editor_scroll_x + _code_w);
            }
        }

        // Update while dragging
        if (code_editor_hscrollbar_dragging) {
            var _hratio = (_mx - code_editor_hscrollbar_drag_offset - _hsb_x1)
                          / max(1, _hsb_w - _hthumb_w);
            code_editor_scroll_x = round(clamp(_hratio, 0, 1) * _hscroll_max);
            _hthumb_x = _hsb_x1 + (_hsb_w - _hthumb_w) * (code_editor_scroll_x / max(1, _hscroll_max));
        }

        // Draw track + thumb
        draw_set_color(make_color_rgb(30, 30, 50));
        draw_rectangle(_hsb_x1, _hsb_y, _hsb_x2, _hsb_y + 6, false);
        draw_set_color(make_color_rgb(
            code_editor_hscrollbar_dragging ? 80  : 50,
            code_editor_hscrollbar_dragging ? 180 : 140,
            code_editor_hscrollbar_dragging ? 130 : 100
        ));
        draw_rectangle(_hthumb_x, _hsb_y, _hthumb_x + _hthumb_w, _hsb_y + 6, false);
    }

// ─── Type suffix legend ───
    draw_set_font(fnt_c64_code);
    draw_set_color(make_color_rgb(120, 120, 120));
    draw_text(_px + 8, _py + _ph - 49,
              "VAR.W=WORD(2B)  VAR.B/none=BYTE(1B)  VAR.BCD=3B  VAR.BCD2=2B  VAR.BCD3=3B");

    // ─── Stats bar ───
    var _stats = code_editor_cached_stats;
    
    var _cyc_this = 0;
    var _cyc_to = 0;
    if (is_array(code_editor_cached_line_cyc) && _cur_line < array_length(code_editor_cached_line_cyc)) {
        _cyc_this = code_editor_cached_line_cyc[_cur_line];
        _cyc_to = code_editor_cached_run_cyc[_cur_line] + _cyc_this;
    }

    draw_set_font(fnt_c64_code); // Switched to main code font
    draw_set_color(make_color_rgb(200, 170, 140)); // Slightly brighter dim color
    draw_text(_px + 8, _py + _ph - 34, 
              "L" + string(_cur_line + 1) + ":" + string(_cur_col + 1) + 
              "  (" + string(_total_lines) + " LINES)    " + string(_stats[0]) + " BYTES    " + string(_stats[1]) + " CYC (TOTAL)    CYCLES TO LINE: " + string(_cyc_to) + "    THIS LINE: " + string(_cyc_this));

    // ─── Hints bar ───
    draw_set_color(make_color_rgb(100, 180, 200));
    draw_text(_px + 8, _py + _ph - 19, "(CTRL+ENTER) or ESCAPE to  CLOSE  |  F5: BUILD  |  CTRL+C/X/V  |  CTRL+A  |  TAB |  F12 : FONT  Z CTRL/(+SHIFT)+F FIND+REPLACE");
	
	if (code_editor_find_open) scr_code_editor_draw_find_dialogue(_px, _py, _pw, _mx, _my);
	
}
