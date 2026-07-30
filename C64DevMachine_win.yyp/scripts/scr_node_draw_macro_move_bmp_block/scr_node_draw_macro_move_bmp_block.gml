/// @desc Draw MOVE_BMP_BLOCK node body
function scr_node_draw_macro_move_bmp_block(_draw_x, _y) {
    var _header_h = 24;
    var _line_h   = 12;

    // Backfill for older saves. 14 entries = pre-blend; 16 = pre-ASSET.
    // Defaults reproduce the OLD behaviour so existing projects load unchanged.
    var _had_14 = (array_length(instructions[0]) == 14);
    var _had_16 = (array_length(instructions[0]) == 16);
    while (array_length(instructions[0]) < 19) {
        array_push(instructions[0], 0);
    }
    // WRITE COLL slots. [19] = toggle, [20] = BBT asset name. Appended blank for
    // pre-collision saves, which read as write_coll = 0 (byte-identical build).
    while (array_length(instructions[0]) < 21) {
        array_push(instructions[0], (array_length(instructions[0]) == 19) ? 0 : "");
    }
    if (!is_real(instructions[0][19])) { instructions[0][19] = 0; }
    if (_had_14) {
        instructions[0][14] = 1;
        instructions[0][15] = 1;
    }
    if (_had_14 || _had_16) {
        instructions[0][16] = 0;
        instructions[0][17] = "";
        instructions[0][18] = "";
    }
    var _src_bmp  = is_real(instructions[0][1])  ? real(instructions[0][1])  : 0x4000;
    var _dst_bmp  = is_real(instructions[0][2])  ? real(instructions[0][2])  : 0x4000;
    var _src_x    = is_real(instructions[0][3])  ? real(instructions[0][3])  : 0;
    var _src_y    = is_real(instructions[0][4])  ? real(instructions[0][4])  : 0;
    var _dst_x    = is_real(instructions[0][5])  ? real(instructions[0][5])  : 0;
    var _dst_y    = is_real(instructions[0][6])  ? real(instructions[0][6])  : 0;
    var _bw       = is_real(instructions[0][7])  ? real(instructions[0][7])  : 1;
    var _bh       = is_real(instructions[0][8])  ? real(instructions[0][8])  : 1;
    var _sxv      = string(instructions[0][9]);
    var _syv      = string(instructions[0][10]);
    var _dxv      = string(instructions[0][11]);
    var _dyv      = string(instructions[0][12]);
    var _col_on   = is_real(instructions[0][13]) ? real(instructions[0][13]) : 1;
    var _blend    = is_real(instructions[0][14]) ? real(instructions[0][14]) : 0;
    var _scr_on   = is_real(instructions[0][15]) ? real(instructions[0][15]) : 1;
    var _src_mode = is_real(instructions[0][16]) ? real(instructions[0][16]) : 0;
    var _rec_ast  = string(instructions[0][17]);
    var _entry_v  = string(instructions[0][18]);
    var _write_coll = is_real(instructions[0][19]) ? real(instructions[0][19]) : 0;
    var _bbt_asset  = string(instructions[0][20]);

    var _src_h = string_upper(decimal_to_hex(_src_bmp)); while (string_length(_src_h) < 4) _src_h = "0" + _src_h;
    var _dst_h = string_upper(decimal_to_hex(_dst_bmp)); while (string_length(_dst_h) < 4) _dst_h = "0" + _dst_h;

    var _c_edit = make_color_rgb(120, 220, 120);
    var _c_dim  = make_color_rgb(120, 120, 120);
    var _c_var  = make_color_rgb(180, 140, 220);
    var _c_ast  = make_color_rgb(255, 190, 90);

    draw_set_font(fnt_c64_tiny);
    var _ply = _y + _header_h + 4;

    // Row 1: SRC bitmap address
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "SRC BMP:");
    draw_set_color(c_aqua);
    draw_text(_draw_x + 70, _ply, "$" + _src_h);
    _ply += _line_h;

    // Row 2: DST bitmap address
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "DST BMP:");
    draw_set_color(c_yellow);
    draw_text(_draw_x + 70, _ply, "$" + _dst_h);
    _ply += _line_h;

    // Row 3: SRC MODE toggle — LIT (one block) vs ASSET (BYTE_DATA record list)
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "MODE:");
    if (_src_mode == 1) {
        draw_set_color(_c_ast);
        draw_text(_draw_x + 60, _ply, "ASSET LIST");
    } else {
        draw_set_color(make_color_rgb(120, 220, 255));
        draw_text(_draw_x + 60, _ply, "LIT BLOCK");
    }
    _ply += _line_h;

    if (_src_mode == 1) {
        // ── ASSET MODE ROWS ──
        // Row 4: BYTE_DATA asset
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "LIST:");
        if (_rec_ast == "") {
            draw_set_color(_c_dim);
            draw_text(_draw_x + 50, _ply, "<NONE>");
        } else {
            draw_set_color(_c_ast);
            draw_text(_draw_x + 50, _ply, _rec_ast);
        }
        _ply += _line_h;

        // Row 5: GROUP VAR — which run to draw (0-based).
        // A group is every record between two $FF sentinels. <NONE> draws group
        // 0 with no runtime seek at all. With a VAR, the runtime counts $FF
        // sentinels forward from the table base until it has skipped VAR of
        // them, so one byte addresses up to 255 groups.
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "GROUP:");
        if (_entry_v == "") {
            draw_set_color(_c_dim);
            draw_text(_draw_x + 58, _ply, "<NONE>");
        } else {
            draw_set_color(_c_var);
            draw_text(_draw_x + 58, _ply, _entry_v);
        }
        _ply += _line_h;

        // Record layout reminder — the inline BYTE_DATA editor shows raw hex,
        // so spell out what the six bytes mean.
        draw_set_font(fnt_c64_pico);
        draw_set_color(make_color_rgb(90, 110, 150));
        draw_text(_draw_x + 8, _ply +1, "USE: SX, SY, DX, DY, W, H, END: $FF");
        draw_set_font(fnt_c64_tiny);
        _ply += _line_h;

        // Resolve the asset's byte count so the user can sanity-check the list.
        if (_rec_ast != "" && instance_exists(obj_asset_manager)) {
            var _am_d   = obj_asset_manager;
            var _bd_sz  = -1;
            var _bd_adr = 0;
            for (var _di = 0; _di < ds_list_size(_am_d.asset_list); _di++) {
                var _a_d = ds_list_find_value(_am_d.asset_list, _di);
                if (_a_d.type == "BYTE_DATA" && _a_d.name == _rec_ast) {
                    _bd_adr = _a_d.address;
                    if (buffer_exists(_a_d.buffer)) {
                        _bd_sz = buffer_get_size(_a_d.buffer);
                    }
                    break;
                }
            }
            draw_set_font(fnt_c64_pico);
            if (_bd_sz < 0) {
                draw_set_color(make_color_rgb(230, 90, 90));
                draw_text(_draw_x + 8, _ply, "! LIST NOT FOUND");
            } else {
                var _bd_h = string_upper(decimal_to_hex(_bd_adr));
                while (string_length(_bd_h) < 4) _bd_h = "0" + _bd_h;
                draw_set_color(make_color_rgb(80, 120, 180));
                draw_text(_draw_x + 8, _ply,
                    "$" + _bd_h + "  " + string(_bd_sz) + "B  ~"
                    + string(floor(_bd_sz / 6)) + " RECS");
            }
            draw_set_font(fnt_c64_tiny);
            _ply += _line_h;
        }
    } else {
        // ── LIT MODE ROWS ──
        // Row 4: SRC X/Y (cell coords)
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8,  _ply, "SX:");
        draw_set_color(c_aqua);
        draw_text(_draw_x + 28, _ply, string(_src_x));
        draw_set_color(_c_edit);
        draw_text(_draw_x + 60, _ply, "SY:");
        draw_set_color(c_aqua);
        draw_text(_draw_x + 80, _ply, string(_src_y));
        _ply += _line_h;

        // Row 5: DST X/Y (cell coords)
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8,  _ply, "DX:");
        draw_set_color(c_yellow);
        draw_text(_draw_x + 28, _ply, string(_dst_x));
        draw_set_color(_c_edit);
        draw_text(_draw_x + 60, _ply, "DY:");
        draw_set_color(c_yellow);
        draw_text(_draw_x + 80, _ply, string(_dst_y));
        _ply += _line_h;

        // Row 6: W / H
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8,  _ply, "W:");
        draw_set_color(c_lime);
        draw_text(_draw_x + 28, _ply, string(_bw));
        draw_set_color(_c_edit);
        draw_text(_draw_x + 60, _ply, "H:");
        draw_set_color(c_lime);
        draw_text(_draw_x + 80, _ply, string(_bh));
        _ply += _line_h;

        // Rows 7-10: VAR pickers
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "+SXV:");
        if (_sxv == "") {
            draw_set_color(_c_dim);
            draw_text(_draw_x + 44, _ply, "<NONE>");
        } else {
            draw_set_color(_c_var);
            draw_text(_draw_x + 44, _ply, _sxv);
        }
        _ply += _line_h;

        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "+SYV:");
        if (_syv == "") {
            draw_set_color(_c_dim);
            draw_text(_draw_x + 44, _ply, "<NONE>");
        } else {
            draw_set_color(_c_var);
            draw_text(_draw_x + 44, _ply, _syv);
        }
        _ply += _line_h;

        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "+DXV:");
        if (_dxv == "") {
            draw_set_color(_c_dim);
            draw_text(_draw_x + 44, _ply, "<NONE>");
        } else {
            draw_set_color(_c_var);
            draw_text(_draw_x + 44, _ply, _dxv);
        }
        _ply += _line_h;

        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "+DYV:");
        if (_dyv == "") {
            draw_set_color(_c_dim);
            draw_text(_draw_x + 44, _ply, "<NONE>");
        } else {
            draw_set_color(_c_var);
            draw_text(_draw_x + 44, _ply, _dyv);
        }
        _ply += _line_h;
    }

    // ── SHARED ROWS (both modes) ──
    // BLEND toggle
    // MASK00 — source %00 pairs are holes; the destination shows through.
    // OPAQUE — straight clobber.
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "BLEND:");
    if (_blend == 0) {
        draw_set_color(make_color_rgb(120, 220, 255));
        draw_text(_draw_x + 60, _ply, "MASK 00");
    } else {
        draw_set_color(make_color_rgb(255, 160, 60));
        draw_text(_draw_x + 60, _ply, "OPAQUE");
    }
    _ply += _line_h;

    // SCREEN RAM toggle (source cell's col1/col2)
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "COPY SCR:");
    if (_scr_on == 1) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 70, _ply, "YES");
    } else {
        draw_set_color(c_red);
        draw_text(_draw_x + 70, _ply, "NO");
    }
    _ply += _line_h;

    // COLOUR RAM toggle (source cell's col3)
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "COPY COL:");
    if (_col_on == 1) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 70, _ply, "YES");
    } else {
        draw_set_color(c_red);
        draw_text(_draw_x + 70, _ply, "NO");
    }
    _ply += _line_h;

    // WRITE COLL toggle — stamps the source cells' collision tags into $0400 as
    // the block blits. ASSET-mode only (the map is rebuilt by walking records);
    // greyed with a note in LIT mode so the mismatch is visible.
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "WRITE COLL:");
    if (_src_mode == 1) {
        if (_write_coll == 1) {
            draw_set_color(c_lime);
            draw_text(_draw_x + 82, _ply, "YES");
        } else {
            draw_set_color(c_red);
            draw_text(_draw_x + 82, _ply, "NO");
        }
    } else {
        draw_set_color(make_color_rgb(120, 90, 50));
        draw_text(_draw_x + 82, _ply, "(ASSET ONLY)");
    }
    _ply += _line_h;

    // BBT picker — only when WRITE COLL is on in ASSET mode. Red when empty.
    if (_src_mode == 1 && _write_coll == 1) {
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, "TAGS:");
        var _bbt_set = (_bbt_asset != "" && _bbt_asset != "[clear]");
        if (_bbt_set) {
            draw_set_color(make_color_rgb(255, 140, 140));
            var _bbt_disp = _bbt_asset;
            if (string_length(_bbt_disp) > 16) {
                _bbt_disp = string_copy(_bbt_disp, 1, 16) + "...";
            }
            draw_text(_draw_x + 50, _ply, _bbt_disp);
        } else {
            draw_set_color(make_color_rgb(230, 90, 90));
            draw_text(_draw_x + 50, _ply, "< PICK BBT >");
        }
        _ply += _line_h;
    }

    // Palette note: MASK00 with both palette planes off means the stamped
    // pixels adopt the DESTINATION cell's colours, not the source's. Valid,
    // but it is not the "source owns the palette" default, so say so.
    if (_blend == 0 && _scr_on == 0 && _col_on == 0) {
        draw_set_font(fnt_c64_pico);
        draw_set_color(make_color_rgb(230, 170, 60));
        draw_text(_draw_x + 8, _ply, "! DEST PALETTE - SRC PIXELS RECOLOURED");
        _ply += _line_h;
        draw_set_font(fnt_c64_tiny);
    }

    // Footer: byte cost preview (LIT mode only — ASSET size is data-driven).
    if (_src_mode == 0) {
        var _bmp_bytes = _bw * _bh * 8;
        var _scr_bytes = 0;
        var _col_bytes = 0;
        if (_scr_on == 1) {
            _scr_bytes = _bw * _bh;
        }
        if (_col_on == 1) {
            _col_bytes = _bw * _bh;
        }
        draw_set_font(fnt_c64_pico);
        draw_set_color(make_color_rgb(80, 120, 180));
        var _cost = string(_bmp_bytes) + "B BMP";
        if (_scr_on == 1) {
            _cost += " + " + string(_scr_bytes) + "B SCR";
        }
        if (_col_on == 1) {
            _cost += " + " + string(_col_bytes) + "B COL";
        }
        draw_text(_draw_x + 8, _ply, _cost);
    }
}