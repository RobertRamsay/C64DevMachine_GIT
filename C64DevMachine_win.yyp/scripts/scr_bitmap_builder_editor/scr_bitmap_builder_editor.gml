/// @function scr_bitmap_builder_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my)
/// @desc Inline editor for BITMAP_BUILDER assets.
///
/// Two bitmap panels side by side: SOURCE (left, the tile sheet) and DEST
/// (right, the canvas being assembled). Drag a cell-rect on the source, then
/// click the dest to place it — that pair becomes one copy record
/// (sx,sy,dx,dy,w,h in char cells). The record list on the far right is the
/// source of truth; GENERATE emits it as a BYTE_DATA table for
/// MACRO_MOVE_BMP_BLOCK to consume in ASSET mode.
///
/// The dest panel shows a SCRATCH surface (meta.prev_surf), replayed from the
/// records — the real dest bitmap asset is untouched until BAKE.
function scr_bitmap_builder_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _m = _asset.meta;

    // ── UNDO / REDO ──
    // Snapshot architecture, same as MAP_DATA and META_TILESET: push a copy of
    // the record list BEFORE each mutation, restore on Ctrl+Z. Session-only —
    // the stacks are cleared on save/load rather than serialised, so a project
    // file never carries a history it can't meaningfully replay.
    //
    // The records are structs, so array_copy_shallow would alias them and an
    // undo could be silently mutated by later edits. Deep-copy each record.
    var _bb_snap = function(_mm) {
        var _snap = [];
        for (var _si = 0; _si < array_length(_mm.records); _si++) {
            var _r = _mm.records[_si];
            if (_r.kind == "END") {
                array_push(_snap, { kind : "END" });
            } else {
                array_push(_snap, {
                    kind : "REC",
                    sx   : _r.sx,
                    sy   : _r.sy,
                    dx   : _r.dx,
                    dy   : _r.dy,
                    w    : _r.w,
                    h    : _r.h
                });
            }
        }
        return _snap;
    };

    // Call immediately BEFORE mutating _m.records. Pushes the current state and
    // kills the redo branch — a fresh edit always ends the redo chain.
    var _bb_push_undo = function(_mm, _snapf) {
        array_push(_mm.undo_stack, {
            records    : _snapf(_mm),
            prev_entry : _mm.prev_entry,
            sel_rec    : _mm.sel_rec
        });
        if (array_length(_mm.undo_stack) > 50) {
            array_delete(_mm.undo_stack, 0, 1);
        }
        _mm.redo_stack = [];
    };

    // ── PANEL GEOMETRY ───────────────────────────────────────────────────
    // Two 320x200 panels at 2x, side by side, with the record list to the right.
    var _pz    = 2;                    // panel zoom
    var _pw    = 320 * _pz;            // 640
    var _ph    = 200 * _pz;            // 400
    var _gap   = 24;
    var _p_top = _cy + 96;             // room for the control rows above

    var _sx0 = _vx1 + 20;              // source panel origin
    var _sy0 = _p_top;
    var _dx0 = _sx0 + _pw + _gap;      // dest panel origin
    var _dy0 = _p_top;

    // Record list column, right of the dest panel.
    var _lx0 = _dx0 + _pw + _gap;
    var _lw  = 260;
    // No clamp to _vx2 — the record list is allowed to run past the viewer's
    // right bound. Clamping here silently truncated the column back to whatever
    // space happened to be left, so widening _lw had no visible effect.

    // ── RESOLVE THE TWO LINKED BITMAPS ───────────────────────────────────
    // The EDIT buttons below repoint obj_asset_manager.viewer_asset, which is
    // an asset_list INDEX, not a struct ref — so capture each bitmap's index
    // here alongside its struct.
    var _src = noone;
    var _dst = noone;
    var _src_idx = -1;
    var _dst_idx = -1;
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a.type != "BITMAP") {
                continue;
            }
            if (_a.name == _m.src_asset) {
                _src     = _a;
                _src_idx = _i;
            }
            if (_a.name == _m.dst_asset) {
                _dst     = _a;
                _dst_idx = _i;
            }
        }
    }

    // Rebuild the source bitmap's surface if it was lost (F11 / resize).
    if (_src != noone) {
        if (!variable_struct_exists(_src.meta, "preview_surf")
        ||  !surface_exists(_src.meta.preview_surf)) {
            if (buffer_exists(_src.buffer) && buffer_get_size(_src.buffer) >= 10003) {
                scr_asset_bmp_build_preview(_src);
            }
        }
    }
    if (_dst != noone) {
        if (!variable_struct_exists(_dst.meta, "preview_surf")
        ||  !surface_exists(_dst.meta.preview_surf)) {
            if (buffer_exists(_dst.buffer) && buffer_get_size(_dst.buffer) >= 10003) {
                scr_asset_bmp_build_preview(_dst);
            }
        }
    }

    // Rebuild the scratch preview when dirty or when its surface was lost.
    // Once a BBD table exists it is derived data — regenerate it in the same
    // tick so the BYTE_DATA the node reads can never drift from the records
    // on screen. Surface-loss (F11 / resize) does not dirty the records, so
    // only a genuine record/blend change triggers the emit.
    var _bb_recs_changed = _m.prev_dirty;

    if (_m.prev_dirty || !surface_exists(_m.prev_surf)) {
        scr_bitmap_builder_replay(_asset);
        _m.prev_dirty = false;
    }

    if (_bb_recs_changed && _m.bbd_name != "" && array_length(_m.records) > 0) {
        scr_bitmap_builder_generate(_asset);
    }

    // ═════════════════════════════════════════════════════════════════════
    // CONTROL ROWS (above the panels)
    // ═════════════════════════════════════════════════════════════════════
    // Filter ON is the resting state for this whole editor — fonts and vector
    // shapes want it. It gets flicked OFF only around raw C64 surface blits,
    // where any interpolation smears the 1x1 pixels.
    var _entry_filter = gpu_get_texfilter();
    gpu_set_texfilter(true);

    var _rowy = _cy;
    draw_set_font(fnt_c64_tiny);

    // ── ROW 1: SRC picker / DST picker / BLEND toggle ────────────────────
    // SRC
    draw_set_color(c_ltgray);
    draw_text(_vx1 + 20, _rowy + 4, "SRC BMP:");
    var _sbx1 = _vx1 + 88;
    var _sbx2 = _sbx1 + 150;
    var _sb_hov = point_in_rectangle(_mx, _my, _sbx1, _rowy, _sbx2, _rowy + 18);
    draw_set_color(_sb_hov ? make_color_rgb(40, 80, 60) : make_color_rgb(20, 35, 25));
    draw_rectangle(_sbx1, _rowy, _sbx2, _rowy + 18, false);
    draw_set_color((_m.src_asset != "") ? c_aqua : make_color_rgb(150, 150, 150));
    draw_text(_sbx1 + 6, _rowy + 4, (_m.src_asset != "") ? _m.src_asset : "-- PICK --");
    if (_sb_hov && mouse_check_button_pressed(mb_left)) {
        obj_asset_manager.bbuild_picker_open  = true;
        obj_asset_manager.bbuild_picker_field = "SRC";
        obj_asset_manager.bbuild_picker_x     = _sbx1;
        obj_asset_manager.bbuild_picker_y     = _rowy + 18;
        obj_asset_manager.bbuild_picker_hover = -1;
    }

    // DST
    draw_set_color(c_ltgray);
    draw_text(_sbx2 + 24, _rowy + 4, "DST BMP:");
    var _dbx1 = _sbx2 + 92;
    var _dbx2 = _dbx1 + 150;
    var _db_hov = point_in_rectangle(_mx, _my, _dbx1, _rowy, _dbx2, _rowy + 18);
    draw_set_color(_db_hov ? make_color_rgb(40, 80, 60) : make_color_rgb(20, 35, 25));
    draw_rectangle(_dbx1, _rowy, _dbx2, _rowy + 18, false);
    draw_set_color((_m.dst_asset != "") ? c_yellow : make_color_rgb(150, 150, 150));
    draw_text(_dbx1 + 6, _rowy + 4, (_m.dst_asset != "") ? _m.dst_asset : "-- PICK --");
    if (_db_hov && mouse_check_button_pressed(mb_left)) {
        obj_asset_manager.bbuild_picker_open  = true;
        obj_asset_manager.bbuild_picker_field = "DST";
        obj_asset_manager.bbuild_picker_x     = _dbx1;
        obj_asset_manager.bbuild_picker_y     = _rowy + 18;
        obj_asset_manager.bbuild_picker_hover = -1;
    }

    // BLEND — one per builder, so one builder yields one table.
    draw_set_color(c_ltgray);
    draw_text(_dbx2 + 24, _rowy + 4, "BLEND:");
    var _blx1 = _dbx2 + 76;
    var _blx2 = _blx1 + 90;
    var _bl_hov = point_in_rectangle(_mx, _my, _blx1, _rowy, _blx2, _rowy + 18);
    if (_m.blend == 1) {
        draw_set_color(_bl_hov ? make_color_rgb(120, 160, 200) : make_color_rgb(30, 70, 110));
        draw_rectangle(_blx1, _rowy, _blx2, _rowy + 18, false);
        draw_set_color(make_color_rgb(140, 210, 255));
        draw_text(_blx1 + 6, _rowy + 4, "MASK 00");
    } else {
        draw_set_color(_bl_hov ? make_color_rgb(200, 150, 80) : make_color_rgb(110, 70, 25));
        draw_rectangle(_blx1, _rowy, _blx2, _rowy + 18, false);
        draw_set_color(make_color_rgb(255, 190, 110));
        draw_text(_blx1 + 6, _rowy + 4, "SOLID");
    }
    if (_bl_hov && mouse_check_button_pressed(mb_left)) {
        if (_m.blend == 0) {
            _m.blend = 1;
        } else {
            _m.blend = 0;
        }
        _m.prev_dirty = true;
    }

    // BBD name readout
    draw_set_color(make_color_rgb(90, 90, 110));
    draw_text(_blx2 + 20, _rowy + 4, "TABLE:");
    draw_set_color((_m.bbd_name != "") ? make_color_rgb(180, 120, 255) : make_color_rgb(70, 70, 90));
    draw_text(_blx2 + 66, _rowy + 4, (_m.bbd_name != "") ? _m.bbd_name : "-- NOT GENERATED --");

    // ── TAG MODE + TYPE PICKER ───────────────────────────────────────────
    // TAG paints collision TYPE IDs onto the SOURCE sheet's char cells. The tags
    // live on the BITMAP asset (meta.coll_types) because they describe the
    // artwork — a platform cell is a platform wherever it lands, so every grab
    // of it carries its type along.
    //
    // GENERATE emits the grid as BBT_<builder> (1000 bytes, ONCE). At runtime
    // MACRO_MOVE_BMP_BLOCK writes each source cell's type into $0400 + dest_cell
    // as it blits — screen RAM is free in bitmap mode, and MACRO_COLL_ADV already
    // reads it. So the collision map builds itself from the same pass that draws
    // the pixels, at a flat 1000 bytes no matter how many rooms exist.
    //
    // Types run 0..16, matching the CHAR_SET tile_types range and COLL_ADV's
    // T1..T16 handler slots. The badge palette is the one the META_TILESET and
    // MAP_DATA tile strips use, so a T3 looks like a T3 everywhere in the tool.
    var _tag_x1  = _blx2 + 320;
    var _tag_x2  = _tag_x1 + 70;
    var _tag_hov = point_in_rectangle(_mx, _my, _tag_x1, _rowy, _tag_x2, _rowy + 18);
    if (_m.tag_mode == 1) {
        draw_set_color(_tag_hov ? make_color_rgb(220, 100, 100) : make_color_rgb(140, 40, 40));
        draw_rectangle(_tag_x1, _rowy, _tag_x2, _rowy + 18, false);
        draw_set_color(make_color_rgb(255, 180, 180));
        draw_set_halign(fa_center);
        draw_text((_tag_x1 + _tag_x2) * 0.5, _rowy + 4, "TAG ON");
        draw_set_halign(fa_left);
    } else {
        draw_set_color(_tag_hov ? make_color_rgb(80, 80, 110) : make_color_rgb(35, 35, 50));
        draw_rectangle(_tag_x1, _rowy, _tag_x2, _rowy + 18, false);
        draw_set_color(make_color_rgb(120, 120, 150));
        draw_set_halign(fa_center);
        draw_text((_tag_x1 + _tag_x2) * 0.5, _rowy + 4, "TAG OFF");
        draw_set_halign(fa_left);
    }
    if (_tag_hov && mouse_check_button_pressed(mb_left)) {
        if (_m.tag_mode == 0) {
            _m.tag_mode = 1;
            // Entering TAG mode drops any armed grab — the source panel becomes a
            // paint surface, and a half-finished grab would fire on the next dest
            // click the moment TAG is switched back off.
            _m.phase    = 0;
            _m.anchor_c = -1;
            _m.anchor_r = -1;
        } else {
            _m.tag_mode     = 0;
            _m.tag_painting = 0;
        }
    }

    // Badge palette — shared with the CHAR_SET / META_TILESET tile-type strips.
    var _bb_badge = [
        0,
        make_color_rgb(200,  60,  60),
        make_color_rgb( 60, 140, 220),
        make_color_rgb(200, 160,  60),
        make_color_rgb( 80, 200, 120),
        make_color_rgb(200,  80, 200),
        make_color_rgb(220, 220,  80),
        make_color_rgb( 80, 220, 220),
        make_color_rgb(220, 140,  60),
        make_color_rgb(140, 120, 250),
        make_color_rgb(120, 200,  60),
        make_color_rgb(220,  60, 140),
        make_color_rgb( 60, 200, 160),
        make_color_rgb(180, 100,  40),
        make_color_rgb(120, 130, 250),
        make_color_rgb(200, 200, 140),
        make_color_rgb(160, 160, 160)
    ];

    // Type stepper: < Tn >   (0 = erase)
    var _tt_px1   = _tag_x2 + 12;
    var _tt_px2   = _tt_px1 + 16;
    var _tt_p_hov = point_in_rectangle(_mx, _my, _tt_px1, _rowy, _tt_px2, _rowy + 18);
    draw_set_color(_tt_p_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_tt_px1, _rowy, _tt_px2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_tt_px1 + 8, _rowy + 4, "<");
    draw_set_halign(fa_left);
    if (_tt_p_hov && mouse_check_button_pressed(mb_left)) {
        _m.tag_type = (_m.tag_type + 16) mod 17;   // wraps 0 -> 16
    }

    var _tt_sw1 = _tt_px2 + 4;
    var _tt_sw2 = _tt_sw1 + 44;
    if (_m.tag_type == 0) {
        draw_set_color(make_color_rgb(30, 30, 40));
        draw_rectangle(_tt_sw1, _rowy, _tt_sw2, _rowy + 18, false);
        draw_set_color(make_color_rgb(90, 90, 110));
        draw_rectangle(_tt_sw1, _rowy, _tt_sw2, _rowy + 18, true);
        draw_set_color(make_color_rgb(140, 140, 160));
        draw_set_halign(fa_center);
        draw_text((_tt_sw1 + _tt_sw2) * 0.5, _rowy + 4, "ERASE");
        draw_set_halign(fa_left);
    } else {
        draw_set_color(_bb_badge[clamp(_m.tag_type, 1, 16)]);
        draw_rectangle(_tt_sw1, _rowy, _tt_sw2, _rowy + 18, false);
        draw_set_color(c_black);
        draw_rectangle(_tt_sw1, _rowy, _tt_sw2, _rowy + 18, true);
        draw_set_color(c_black);
        draw_set_halign(fa_center);
        draw_text((_tt_sw1 + _tt_sw2) * 0.5, _rowy + 4, "T" + string(_m.tag_type));
        draw_set_halign(fa_left);
    }

    var _tt_nx1   = _tt_sw2 + 4;
    var _tt_nx2   = _tt_nx1 + 16;
    var _tt_n_hov = point_in_rectangle(_mx, _my, _tt_nx1, _rowy, _tt_nx2, _rowy + 18);
    draw_set_color(_tt_n_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_tt_nx1, _rowy, _tt_nx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_tt_nx1 + 8, _rowy + 4, ">");
    draw_set_halign(fa_left);
    if (_tt_n_hov && mouse_check_button_pressed(mb_left)) {
        _m.tag_type = (_m.tag_type + 1) mod 17;
    }

    // BBT readout — the tag table the MOVE BMP BLK node reads.
    draw_set_color(make_color_rgb(90, 90, 110));
    draw_text(_tt_nx2 + 16, _rowy + 4, "TAGS:");
    draw_set_color((_m.bbt_name != "") ? make_color_rgb(255, 140, 140) : make_color_rgb(70, 70, 90));
    draw_text(_tt_nx2 + 58, _rowy + 4, (_m.bbt_name != "") ? _m.bbt_name : "-- NO TAGS --");

    _rowy += 24;

    // ── ROW 2: GROUP / REDRAW / GENERATE / BAKE ──────────────────────────
    var _total_recs = array_length(_m.records);

    // ── GROUP MAP ──
    // A GROUP is every record between two $FF sentinels. The node's ENTRY VAR
    // is a group index (0-based), and the runtime seeks by counting sentinels,
    // so the editor must speak the same language: prev_entry stays a raw record
    // cursor (it drives selection + highlighting), but the spinner steps whole
    // groups and the readout shows the group number you'd type into the node.
    //
    // _grp_of[i]    = which group record i belongs to
    // _grp_start[g] = first record index of group g
    var _grp_of    = array_create(max(1, _total_recs), 0);
    var _grp_start = [0];
    var _grp_walk  = 0;
    for (var _gi = 0; _gi < _total_recs; _gi++) {
        _grp_of[_gi] = _grp_walk;
        if (_m.records[_gi].kind == "END") {
            _grp_walk += 1;
            // A sentinel closes its group; the next record opens the next one.
            // A sentinel in the LAST slot means the list is fully terminated —
            // there is no group after it, so don't open one.
            if (_gi + 1 < _total_recs) {
                array_push(_grp_start, _gi + 1);
            }
        }
    }
    var _grp_count = array_length(_grp_start);

    // Which group is the cursor sitting in? A cursor parked ON a sentinel
    // belongs to the group that sentinel closes, which _grp_of already gives.
    //
    // Every group — including an empty one — is closed by its own sentinel now,
    // so the cursor always lands on a real record and _grp_of always answers.
    var _cur_grp = 0;
    if (_total_recs > 0) {
        var _ce = clamp(_m.prev_entry, 0, _total_recs - 1);
        _cur_grp = _grp_of[_ce];
    }

    // ── GROUP SELECTOR:   < GROUP ID: n >   [ + ADD ] ──
    // The record list below is FILTERED to this group, so you never scroll past
    // one run to reach the next. The underlying _m.records array is unchanged —
    // still one flat list with $FF sentinels between groups — so GENERATE and
    // the replay need no knowledge of any of this. It's a view, nothing more.
    draw_set_color(c_ltgray);
    draw_text(_vx1 + 20, _rowy + 4, "GROUP ID:");

    // Prev group
    var _gpx1   = _vx1 + 92;
    var _gpx2   = _gpx1 + 18;
    var _gp_hov = point_in_rectangle(_mx, _my, _gpx1, _rowy, _gpx2, _rowy + 18);
    draw_set_color(_gp_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_gpx1, _rowy, _gpx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_gpx1 + 9, _rowy + 4, "<");
    draw_set_halign(fa_left);
    if (_gp_hov && mouse_check_button_pressed(mb_left)) {
        // Park the cursor on the target group's first record. prev_entry stays a
        // raw record index (the replay + highlight both key off it); the group is
        // always derived from it, never stored separately, so the two can't drift.
        var _pg = max(0, _cur_grp - 1);
        _m.prev_entry  = _grp_start[_pg];
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
    }

    // Group number
    draw_set_color(make_color_rgb(255, 200, 100));
    draw_set_halign(fa_center);
    draw_text(_gpx2 + 22, _rowy + 4, string(_cur_grp));
    draw_set_halign(fa_left);

    // Next group
    var _gnx1   = _gpx2 + 38;
    var _gnx2   = _gnx1 + 18;
    var _gn_hov2 = point_in_rectangle(_mx, _my, _gnx1, _rowy, _gnx2, _rowy + 18);
    draw_set_color(_gn_hov2 ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_gnx1, _rowy, _gnx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_gnx1 + 9, _rowy + 4, ">");
    draw_set_halign(fa_left);
    if (_gn_hov2 && mouse_check_button_pressed(mb_left)) {
        var _ng = min(max(0, _grp_count - 1), _cur_grp + 1);
        _m.prev_entry  = _grp_start[_ng];
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
    }

    // Group count readout
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 90, 120));
    draw_text(_gnx2 + 8, _rowy + 6, "OF " + string(_grp_count));
    draw_set_font(fnt_c64_tiny);

    // + ADD — closes the current last group with an $FF and opens a fresh one.
    // Always appends at the END of the list regardless of which group is being
    // viewed: groups are positional, so inserting one mid-list would renumber
    // every group after it and silently repoint any ENTRY VAR pointing there.
    var _gax1   = _gnx2 + 44;
    var _gax2   = _gax1 + 70;
    var _ga_hov = point_in_rectangle(_mx, _my, _gax1, _rowy, _gax2, _rowy + 18);
    draw_set_color(_ga_hov ? make_color_rgb(60, 200, 80) : make_color_rgb(20, 100, 40));
    draw_rectangle(_gax1, _rowy, _gax2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_gax1 + _gax2) * 0.5, _rowy + 4, "+ ADD");
    draw_set_halign(fa_left);
    if (_ga_hov && mouse_check_button_pressed(mb_left)) {
        _bb_push_undo(_m, _bb_snap);
        // A group is the span of records BEFORE a sentinel, so an empty group
        // only exists once its OWN sentinel is in the array — a trailing
        // prev_entry with nothing behind it is invisible to _grp_of, which is
        // what made the new group show (and receive) the previous group's rows.
        //
        // So: close the current last group if it isn't already closed, then push
        // the new group's own sentinel. The array now always ends in a sentinel,
        // and the new (empty) group is the zero-length span before it.
        var _ga_len = array_length(_m.records);
        var _ga_closed = false;
        if (_ga_len > 0) {
            if (_m.records[_ga_len - 1].kind == "END") {
                _ga_closed = true;
            }
        }
        if (!_ga_closed) {
            array_push(_m.records, { kind : "END" });   // terminate the current last group
        }
        array_push(_m.records, { kind : "END" });       // the new group's own terminator

        // Park the cursor ON the new group's sentinel — _grp_of maps a sentinel
        // to the group it closes, so this selects the new empty group.
        _m.prev_entry  = array_length(_m.records) - 1;
        _m.sel_rec     = -1;
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
        _m.is_dirty    = true;
    }

    // RMB the group number to delete the whole group (its records AND its
    // closing sentinel). Blocked when only one group exists — there is always
    // at least one run.
    var _gd_hov = point_in_rectangle(_mx, _my, _gpx2, _rowy, _gnx1, _rowy + 18);
    if (_gd_hov && mouse_check_button_pressed(mb_right) && _grp_count > 1) {
        _bb_push_undo(_m, _bb_snap);
        var _del_from = _grp_start[_cur_grp];
        var _del_to   = _total_recs;              // exclusive
        if (_cur_grp + 1 < _grp_count) {
            _del_to = _grp_start[_cur_grp + 1];   // up to and including this group's $FF
        }
        array_delete(_m.records, _del_from, _del_to - _del_from);
        _m.prev_entry  = clamp(_del_from, 0, max(0, array_length(_m.records) - 1));
        _m.sel_rec     = -1;
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
        _m.is_dirty    = true;
    }

    // REDRAW — wipe the dest scratch and replay the current group.
    // Anchored off the + ADD button (_gax2), which is now the right-hand edge
    // of the group selector — the old ENTRY spinner's _epx2 is gone.
    var _rdx1 = _gax2 + 16;
    var _rdx2 = _rdx1 + 80;
    var _rd_hov = point_in_rectangle(_mx, _my, _rdx1, _rowy, _rdx2, _rowy + 18);
    draw_set_color(_rd_hov ? make_color_rgb(60, 160, 200) : make_color_rgb(25, 70, 95));
    draw_rectangle(_rdx1, _rowy, _rdx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_rdx1 + _rdx2) * 0.5, _rowy + 4, "REDRAW");
    draw_set_halign(fa_left);
    if (_rd_hov && mouse_check_button_pressed(mb_left)) {
        _m.prev_dirty = true;
    }

    // GENERATE — emit / update the BYTE_DATA table.
    var _gnx1 = _rdx2 + 16;
    var _gnx2 = _gnx1 + 110;
    var _gn_hov  = point_in_rectangle(_mx, _my, _gnx1, _rowy, _gnx2, _rowy + 18);
    var _gn_made = (_m.bbd_name != "");

    // After the first generate the table maintains itself — the button goes
    // passive and just reports that it's live.
    if (_gn_made) {
        draw_set_color(make_color_rgb(30, 60, 45));
        draw_rectangle(_gnx1, _rowy, _gnx2, _rowy + 18, false);
        draw_set_color(make_color_rgb(110, 190, 140));
        draw_set_halign(fa_center);
        draw_text((_gnx1 + _gnx2) * 0.5, _rowy + 4, "BBD AUTO");
        draw_set_halign(fa_left);
    } else {
        draw_set_color(_gn_hov ? make_color_rgb(60, 200, 80) : make_color_rgb(20, 100, 40));
        draw_rectangle(_gnx1, _rowy, _gnx2, _rowy + 18, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text((_gnx1 + _gnx2) * 0.5, _rowy + 4, "GENERATE BBD");
        draw_set_halign(fa_left);

        if (_gn_hov && mouse_check_button_pressed(mb_left)) {
            if (_total_recs == 0) {
                _m.warn_msg   = "NO RECORDS TO GENERATE";
                _m.warn_timer = game_get_speed(gamespeed_fps) * 3;
            } else {
                scr_bitmap_builder_generate(_asset);
                _m.warn_msg   = "TABLE -> " + _m.bbd_name + "  (NOW AUTO-UPDATES)";
                _m.warn_timer = game_get_speed(gamespeed_fps) * 3;
            }
        }
    }

    // BAKE — commit the scratch into the real dest bitmap asset.
    var _bkx1 = _gnx2 + 16;
    var _bkx2 = _bkx1 + 110;
    var _bk_hov = point_in_rectangle(_mx, _my, _bkx1, _rowy, _bkx2, _rowy + 18);
    draw_set_color(_bk_hov ? make_color_rgb(200, 120, 40) : make_color_rgb(100, 55, 15));
    draw_rectangle(_bkx1, _rowy, _bkx2, _rowy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_bkx1 + _bkx2) * 0.5, _rowy + 4, "BAKE -> DEST");
    draw_set_halign(fa_left);
    if (_bk_hov && mouse_check_button_pressed(mb_left)) {
        scr_bitmap_builder_bake(_asset);
    }

    // SHOW / HIDE DEST TAGS — overlay the source tag grid onto the dest preview,
    // remapped through each record so you can see where every grabbed cell's
    // collision TYPE lands once MOVE_BMP_BLOCK blits it. Toggle here or press T.
    var _stx1 = _bkx2 + 360;
    var _stx2 = _stx1 + 118;
    var _st_hov = point_in_rectangle(_mx, _my, _stx1, _rowy, _stx2, _rowy + 18);
    if (_m.show_dest_tags == 1) {
        if (_st_hov) {
            draw_set_color(make_color_rgb(220, 100, 100));
        } else {
            draw_set_color(make_color_rgb(140, 40, 40));
        }
        draw_rectangle(_stx1, _rowy, _stx2, _rowy + 18, false);
        draw_set_color(make_color_rgb(255, 180, 180));
        draw_set_halign(fa_center);
        draw_text((_stx1 + _stx2) * 0.5, _rowy + 4, "HIDE TAGS  T");
        draw_set_halign(fa_left);
    } else {
        if (_st_hov) {
            draw_set_color(make_color_rgb(80, 80, 110));
        } else {
            draw_set_color(make_color_rgb(35, 35, 50));
        }
        draw_rectangle(_stx1, _rowy, _stx2, _rowy + 18, false);
        draw_set_color(make_color_rgb(120, 120, 150));
        draw_set_halign(fa_center);
        draw_text((_stx1 + _stx2) * 0.5, _rowy + 4, "SHOW TAGS  T");
        draw_set_halign(fa_left);
    }
    // Click OR the T key flips the overlay. Plain key check — this editor has no
    // text field to steal keystrokes from.
    var _st_toggle = false;
    if (_st_hov && mouse_check_button_pressed(mb_left)) {
        _st_toggle = true;
    }
    if (keyboard_check_pressed(ord("T"))) {
        _st_toggle = true;
    }
    if (_st_toggle) {
        if (_m.show_dest_tags == 0) {
            _m.show_dest_tags = 1;
        } else {
            _m.show_dest_tags = 0;
        }
    }

    // Warning / status line
    if (_m.warn_timer > 0) {
        draw_set_color(make_color_rgb(255, 200, 90));
        draw_text(_stx2 + 20, _rowy + 4, _m.warn_msg);
        _m.warn_timer -= 1;
    }

    _rowy += 24;

    // ── ROW 3: hint line ─────────────────────────────────────────────────
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 110, 150));
    if (_m.tag_mode == 1) {
        draw_set_color(make_color_rgb(255, 160, 160));
        draw_text(_vx1 + 20, _rowy,
            "TAG MODE   |   LMB PAINTS T" + string(_m.tag_type)
            + " ON THE SOURCE SHEET   |   RMB ERASES   |   TAGS TRAVEL WITH EVERY GRAB OF THAT CELL");
    } else if (_m.phase == 0) {
        draw_text(_vx1 + 20, _rowy,
            "DRAG A CELL RECT ON THE SOURCE (LEFT)   |   MAX WIDTH 31 CELLS   |   RMB CANCELS");
    } else {
        draw_text(_vx1 + 20, _rowy,
            "SOURCE LOCKED " + string(_m.grab_w) + "x" + string(_m.grab_h)
            + " CELLS   |   CLICK THE DEST TO PLACE (REPEATS)   |   DRAG SOURCE TO RE-GRAB   |   RMB CANCELS");
    }
    draw_set_font(fnt_c64_tiny);

    // Node-setting reminder — the preview assumes both palette planes copy.
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(200, 150, 60));
    var _remind = "! ON THE MOVE BMP BLK NODE SET: BLEND="
                + ((_m.blend == 1) ? "MASK 00" : "OPAQUE")
                + "   COPY SCR=YES   COPY COL=YES   (PREVIEW ASSUMES BOTH PLANES COPY)";
    if (_m.bbt_name != "") {
        _remind += "     WRITE COLL=YES   TAGS=" + _m.bbt_name;
    }
    draw_text(_vx1 + 20, _rowy + 10, _remind);
    draw_set_font(fnt_c64_tiny);

    // ═════════════════════════════════════════════════════════════════════
    // PANELS
    // ═════════════════════════════════════════════════════════════════════
    // ── SOURCE PANEL ─────────────────────────────────────────────────────
    draw_set_color(c_black);
    draw_rectangle(_sx0, _sy0, _sx0 + _pw, _sy0 + _ph, false);
    if (_src != noone
    &&  variable_struct_exists(_src.meta, "preview_surf")
    &&  surface_exists(_src.meta.preview_surf)) {
        gpu_set_texfilter(false);
        draw_surface_stretched(_src.meta.preview_surf, _sx0, _sy0, _pw, _ph);
        gpu_set_texfilter(true);
    } else {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_set_halign(fa_center);
        draw_text(_sx0 + _pw * 0.5, _sy0 + _ph * 0.5, "NO SOURCE BITMAP LINKED");
        draw_set_halign(fa_left);
    }
    draw_set_color(make_color_rgb(90, 200, 220));
    draw_rectangle(_sx0, _sy0, _sx0 + _pw, _sy0 + _ph, true);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_aqua);
    draw_text(_sx0, _sy0 - 14, "SOURCE");

    // ── DEST PANEL (the scratch preview) ─────────────────────────────────
    draw_set_color(c_black);
    draw_rectangle(_dx0, _dy0, _dx0 + _pw, _dy0 + _ph, false);
    if (surface_exists(_m.prev_surf)) {
        gpu_set_texfilter(false);
        draw_surface_stretched(_m.prev_surf, _dx0, _dy0, _pw, _ph);
        gpu_set_texfilter(true);
    }
    draw_set_color(make_color_rgb(220, 200, 90));
    draw_rectangle(_dx0, _dy0, _dx0 + _pw, _dy0 + _ph, true);
    draw_set_color(c_yellow);
    draw_text(_dx0, _dy0 - 14, "DEST (PREVIEW - SCRATCH, NOT THE REAL ASSET)");

    // ── CELL GRIDS ───────────────────────────────────────────────────────
    // 8px cells at 2x = 16 screen px. Drawn on both panels so the user can see
    // exactly what a "cell" is.
    var _cs = 8 * _pz;
    draw_set_alpha(0.22);
    draw_set_color(make_color_rgb(70, 130, 150));
    for (var _gc = 0; _gc <= 40; _gc++) {
        draw_line(_sx0 + _gc * _cs, _sy0, _sx0 + _gc * _cs, _sy0 + _ph);
        draw_line(_dx0 + _gc * _cs, _dy0, _dx0 + _gc * _cs, _dy0 + _ph);
    }
    for (var _gr = 0; _gr <= 25; _gr++) {
        draw_line(_sx0, _sy0 + _gr * _cs, _sx0 + _pw, _sy0 + _gr * _cs);
        draw_line(_dx0, _dy0 + _gr * _cs, _dx0 + _pw, _dy0 + _gr * _cs);
    }
    draw_set_alpha(1.0);

    // ── MOUSE -> CELL, PER PANEL ─────────────────────────────────────────
    var _in_src = point_in_rectangle(_mx, _my, _sx0, _sy0, _sx0 + _pw, _sy0 + _ph);
    var _in_dst = point_in_rectangle(_mx, _my, _dx0, _dy0, _dx0 + _pw, _dy0 + _ph);

    var _sc = clamp(floor((_mx - _sx0) / _cs), 0, 39);
    var _sr = clamp(floor((_my - _sy0) / _cs), 0, 24);
    var _dc = clamp(floor((_mx - _dx0) / _cs), 0, 39);
    var _dr = clamp(floor((_my - _dy0) / _cs), 0, 24);

    // ── ALT-CLICK: PICK A RECORD UNDER THE DEST CURSOR ───────────────────
    // ALT+LMB in the dest panel selects whichever record's placed rect covers
    // the cell under the pointer, without starting a placement. Records can
    // overlap (a later stamp drawn over an earlier one), so scan the current
    // group BACKWARDS — the last-drawn record is the one actually visible at
    // that pixel, so it's the one "under the mouse" in any visual sense.
    // Only the current group is searched, matching what the dest preview
    // and record list are already filtered to.
    //
    // _alt_click_consumed stops this same press from also being read as a
    // placement click further down — without it, an alt-click on an empty
    // cell (no record found) would fall through and stamp a new copy.
    // Set below when an alt-click lands on a record, then consumed once the
    // record list's _view[] exists further down, to scroll that row into view.
    // -1 means "no pending scroll this frame".
    var _ac_center_row = -1;

    var _alt_click_consumed = false;
    if (_m.tag_mode == 0 && _in_dst && keyboard_check(vk_alt) && mouse_check_button_pressed(mb_left)) {
        _alt_click_consumed = true;
        var _ac_hit = -1;
        for (var _aci = array_length(_m.records) - 1; _aci >= 0; _aci--) {
            var _ac_grp = (_aci < array_length(_grp_of)) ? _grp_of[_aci] : (_grp_count - 1);
            if (_ac_grp != _cur_grp) {
                continue;
            }
            var _ac_rec = _m.records[_aci];
            if (_ac_rec.kind != "REC") {
                continue;
            }
            if (_dc >= _ac_rec.dx && _dc < _ac_rec.dx + _ac_rec.w
            &&  _dr >= _ac_rec.dy && _dr < _ac_rec.dy + _ac_rec.h) {
                _ac_hit = _aci;
                break;
            }
        }
        if (_ac_hit >= 0) {
            _m.sel_rec      = _ac_hit;
            _m.prev_entry   = _ac_hit;
            _m.prev_dirty   = true;
            _ac_center_row  = _ac_hit;
        }
    }
    // ── RESOLVE THE SOURCE SHEET'S TAG GRID ──────────────────────────────
    // Usually seeded when a BITMAP is created or its preview is rebuilt. Older
    // in-memory assets and freshly imported images can already have a valid
    // preview surface without ever passing through that initialisation path,
    // though. Repair the grid here so tagging works immediately and never
    // depends on a save/reload cycle.
    var _tags = noone;
    if (_src != noone) {
        if (!variable_struct_exists(_src.meta, "coll_types")
        ||  !is_array(_src.meta.coll_types)
        ||  array_length(_src.meta.coll_types) != 1000) {
            _src.meta.coll_types = array_create(1000, 0);
        }
        _tags = _src.meta.coll_types;
    }

    // ── TAG MODE: PAINT TYPES ONTO THE SOURCE SHEET ──────────────────────
    // LMB paints the active type, RMB erases. Drag-paints — the stroke flag is
    // on the builder, not the bitmap, so two builders open on one sheet can't
    // tangle each other's in-progress stroke.
    //
    // Undo is deliberately NOT the builder's problem here: its snapshot stack
    // covers records[], and a tag stroke doesn't touch those. Global undo
    // (scr_undo_snapshot) captures coll_types, so a tag edit IS recoverable —
    // but through one history rather than two divergent ones.
    if (_m.tag_mode == 1 && _tags != noone) {
        if (_in_src) {
            if (mouse_check_button_pressed(mb_left))  { _m.tag_painting = 1; }
            if (mouse_check_button_pressed(mb_right)) { _m.tag_painting = 2; }
        }
        if (!mouse_check_button(mb_left) && !mouse_check_button(mb_right)) {
            _m.tag_painting = 0;
        }
        if (_m.tag_painting != 0 && _in_src) {
            var _tg_idx = (_sr * 40) + _sc;
            var _tg_val = (_m.tag_painting == 1) ? (_m.tag_type & 0xFF) : 0;
            if (_tags[_tg_idx] != _tg_val) {
                _tags[_tg_idx] = _tg_val;
                // Records didn't change, but the DERIVED tag table did — dirty the
                // preview so the next frame regenerates BBT alongside BBD (the
                // generate path calls scr_bitmap_builder_gen_tags).
                _m.prev_dirty     = true;
                _m.is_dirty       = true;
                global.undo_dirty = true;
            }
        }
    }

    // ── PHASE 0: DRAG A SOURCE RECT ──────────────────────────────────────
    // Suppressed entirely in TAG mode: the source panel is a paint surface then,
    // and an armed grab underneath would fire on the next dest click the moment
    // TAG is switched off.
    if (_m.tag_mode == 1) {
        // no grab/place interaction while tagging
    } else if (_m.phase == 0) {
        if (_in_src && mouse_check_button_pressed(mb_left)) {
            _m.anchor_c = _sc;
            _m.anchor_r = _sr;
        }
        if (_m.anchor_c >= 0 && mouse_check_button_released(mb_left)) {
            var _gc0 = min(_m.anchor_c, _sc);
            var _gr0 = min(_m.anchor_r, _sr);
            var _gw  = abs(_sc - _m.anchor_c) + 1;
            var _gh  = abs(_sr - _m.anchor_r) + 1;

            // The ASSET-mode compile path clamps w at 31 cells (cmp #32 / bcc),
            // because w*8 must fit an 8-bit inner loop counter. Reject wider
            // grabs here rather than let the runtime silently truncate.
            if (_gw > 31) {
                _m.warn_msg   = "GRAB TOO WIDE (" + string(_gw) + ") - MAX 31 CELLS";
                _m.warn_timer = game_get_speed(gamespeed_fps) * 4;
                _m.anchor_c = -1;
                _m.anchor_r = -1;
            } else {
                _m.grab_c = _gc0;
                _m.grab_r = _gr0;
                _m.grab_w = _gw;
                _m.grab_h = _gh;
                _m.anchor_c = -1;
                _m.anchor_r = -1;
                _m.phase = 1;   // now awaiting a dest click
            }
        }

        // Live source rubber-band
        if (_m.anchor_c >= 0 && _in_src) {
            var _rc0 = min(_m.anchor_c, _sc);
            var _rr0 = min(_m.anchor_r, _sr);
            var _rc1 = max(_m.anchor_c, _sc) + 1;
            var _rr1 = max(_m.anchor_r, _sr) + 1;
            var _rx0 = _sx0 + _rc0 * _cs;
            var _ry0 = _sy0 + _rr0 * _cs;
            var _rx1 = _sx0 + _rc1 * _cs;
            var _ry1 = _sy0 + _rr1 * _cs;
            // Turn the band red once it exceeds the 31-cell hard limit.
            var _band_w = _rc1 - _rc0;
            if (_band_w > 31) {
                draw_set_color(c_red);
            } else {
                draw_set_color(c_yellow);
            }
            draw_rectangle(_rx0, _ry0, _rx1, _ry1, true);
            draw_set_alpha(0.18);
            draw_rectangle(_rx0, _ry0, _rx1, _ry1, false);
            draw_set_alpha(1.0);
            draw_set_font(fnt_c64_pico);
            draw_set_color(c_white);
            draw_text(_rx0 + 2, _ry0 - 10,
                string(_rc0) + "," + string(_rr0) + "  "
                + string(_band_w) + "x" + string(_rr1 - _rr0));
            draw_set_font(fnt_c64_tiny);
        }
    } else {
        // ── PHASE 1: LOCKED SOURCE, PLACE ON DEST ────────────────────────
        // The grab persists across drops, so a new drag on the SOURCE panel
        // must be able to replace it without first cancelling. Dropping back to
        // phase 0 on mouse-down hands the drag to the phase-0 rubber-band path
        // on the following frame.
        if (_in_src && mouse_check_button_pressed(mb_left)) {
            _m.phase    = 0;
            _m.anchor_c = _sc;
            _m.anchor_r = _sr;
        }

        // Locked source rect stays outlined so you can see what you're moving.
        var _lx1 = _sx0 + _m.grab_c * _cs;
        var _ly1 = _sy0 + _m.grab_r * _cs;
        var _lx2 = _sx0 + (_m.grab_c + _m.grab_w) * _cs;
        var _ly2 = _sy0 + (_m.grab_r + _m.grab_h) * _cs;
        draw_set_color(c_yellow);
        draw_rectangle(_lx1, _ly1, _lx2, _ly2, true);
        draw_rectangle(_lx1 - 1, _ly1 - 1, _lx2 + 1, _ly2 + 1, true);

        // Dest ghost, clamped so the block stays on the 40x25 grid.
        if (_in_dst) {
            var _pdc = _dc;
            var _pdr = _dr;
            if (_pdc + _m.grab_w > 40) {
                _pdc = 40 - _m.grab_w;
            }
            if (_pdr + _m.grab_h > 25) {
                _pdr = 25 - _m.grab_h;
            }
            if (_pdc < 0) {
                _pdc = 0;
            }
            if (_pdr < 0) {
                _pdr = 0;
            }

            var _gx1 = _dx0 + _pdc * _cs;
            var _gy1 = _dy0 + _pdr * _cs;
            var _gx2 = _dx0 + (_pdc + _m.grab_w) * _cs;
            var _gy2 = _dy0 + (_pdr + _m.grab_h) * _cs;

            // Live ghost of the actual source pixels at the drop point.
            if (_src != noone
            &&  variable_struct_exists(_src.meta, "preview_surf")
            &&  surface_exists(_src.meta.preview_surf)) {
                gpu_set_texfilter(false);
                draw_surface_part_ext(_src.meta.preview_surf,
                    _m.grab_c * 8, _m.grab_r * 8,
                    _m.grab_w * 8, _m.grab_h * 8,
                    _gx1, _gy1, _pz, _pz, c_white, 0.75);
                gpu_set_texfilter(true);
            }

            draw_set_color(c_aqua);
            draw_rectangle(_gx1, _gy1, _gx2, _gy2, true);
            draw_set_font(fnt_c64_pico);
            draw_set_color(c_white);
            draw_text(_gx1 + 2, _gy1 - 10, string(_pdc) + "," + string(_pdr));
            draw_set_font(fnt_c64_tiny);

            // Commit the record. The grab stays armed (phase 1) so the same
            // block can be stamped repeatedly — a fresh source drag or an RMB
            // is what clears it.
            //
            // The record joins the END of the ACTIVE GROUP, not the end of the
            // whole list: walk forward from the cursor to that group's $FF and
            // insert just before it. Appending to the list would drop the record
            // into the last group instead, so stamping while previewing group 1
            // of 3 would silently edit group 2.
            if (mouse_check_button_pressed(mb_left) && !_alt_click_consumed) {
                _bb_push_undo(_m, _bb_snap);
                var _new_rec = {
                    kind : "REC",
                    sx   : _m.grab_c,
                    sy   : _m.grab_r,
                    dx   : _pdc,
                    dy   : _pdr,
                    w    : _m.grab_w,
                    h    : _m.grab_h
                };

                // Find this group's closing sentinel, scanning forward from the
                // cursor. No sentinel ahead (the last group is unterminated in
                // the editor — GENERATE appends the trailing $FF) means the
                // group runs to the end of the list, so append.
                var _rc_ins  = array_length(_m.records);
                var _ins_pos = _rc_ins;
                if (_rc_ins > 0) {
                    var _scan = clamp(_m.prev_entry, 0, _rc_ins - 1);
                    // A cursor parked ON a sentinel belongs to the group above
                    // it, so that sentinel IS this group's terminator.
                    while (_scan < _rc_ins) {
                        if (_m.records[_scan].kind == "END") {
                            _ins_pos = _scan;
                            break;
                        }
                        _scan += 1;
                    }
                }

                array_insert(_m.records, _ins_pos, _new_rec);
                _m.sel_rec    = _ins_pos;
                _m.prev_dirty = true;
                _m.is_dirty   = true;
            }
        }
    }

    // RMB anywhere on either panel cancels the in-progress grab / placement,
    // and also clears the selected record — the pulsing highlight on both
    // panels (and the highlighted row in the list) tracks sel_rec, so this is
    // what makes "right click" read as "deselect" rather than just "cancel".
    if ((_in_src || _in_dst) && mouse_check_button_pressed(mb_right)) {
        _m.phase    = 0;
        _m.anchor_c = -1;
        _m.anchor_r = -1;
        _m.sel_rec  = -1;
    }

    // ── TAG OVERLAY ON THE SOURCE PANEL ──────────────────────────────────
    // Drawn ALWAYS, not just in TAG mode, so you can see at a glance which parts
    // of the sheet carry collision as you grab them. Dimmer when TAG is off —
    // context then, not the subject.
    if (_tags != noone) {
        var _ov_a = (_m.tag_mode == 1) ? 0.55 : 0.28;
        draw_set_font(fnt_c64_pico);
        for (var _tr = 0; _tr < 25; _tr++) {
            for (var _tc = 0; _tc < 40; _tc++) {
                var _tv = _tags[(_tr * 40) + _tc];
                if (_tv <= 0) {
                    continue;
                }
                var _tx1 = _sx0 + _tc * _cs;
                var _ty1 = _sy0 + _tr * _cs;
                draw_set_color(_bb_badge[clamp(_tv, 1, 16)]);
                draw_set_alpha(_ov_a);
                draw_rectangle(_tx1, _ty1, _tx1 + _cs, _ty1 + _cs, false);
                draw_set_alpha(1.0);
                if (_m.tag_mode == 1) {
                    draw_set_color(c_black);
                    draw_text(_tx1 + 1, _ty1 + 1, "T" + string(_tv));
                }
            }
        }
        draw_set_font(fnt_c64_tiny);
        draw_set_alpha(1.0);
    }

    // ── DEST TAG PREVIEW OVERLAY ─────────────────────────────────────────
    // Show where each source cell's collision TYPE lands on the dest once
    // MOVE_BMP_BLOCK blits it: replay the CURRENT GROUP's records, mapping each
    // grabbed cell's tag at (sx+i, sy+j) to its dest cell (dx+i, dy+j). Later
    // records overwrite earlier ones, exactly as the runtime blit does, so this
    // is the collision map the node will actually write into $0400.
    if (_m.show_dest_tags == 1 && _tags != noone) {
        var _dt_total = array_length(_m.records);
        var _dt_gmap  = array_length(_grp_of);
        var _dtag     = array_create(1000, 0);
        for (var _dvi = 0; _dvi < _dt_total; _dvi++) {
            // Same past-the-map guard the record list uses: anything appended
            // after _grp_of was built this frame belongs to the last group.
            var _dvg = _grp_count - 1;
            if (_dvi < _dt_gmap) {
                _dvg = _grp_of[_dvi];
            }
            if (_dvg != _cur_grp) {
                continue;
            }
            var _drec = _m.records[_dvi];
            if (_drec.kind != "REC") {
                continue;
            }
            for (var _dj = 0; _dj < _drec.h; _dj++) {
                for (var _di = 0; _di < _drec.w; _di++) {
                    var _scell = ((_drec.sy + _dj) * 40) + (_drec.sx + _di);
                    var _dcell = ((_drec.dy + _dj) * 40) + (_drec.dx + _di);
                    if (_scell < 0 || _scell >= 1000) {
                        continue;
                    }
                    if (_dcell < 0 || _dcell >= 1000) {
                        continue;
                    }
                    _dtag[_dcell] = _tags[_scell];
                }
            }
        }

        draw_set_font(fnt_c64_pico);
        for (var _dtr = 0; _dtr < 25; _dtr++) {
            for (var _dtc = 0; _dtc < 40; _dtc++) {
                var _dtv = _dtag[(_dtr * 40) + _dtc];
                if (_dtv <= 0) {
                    continue;
                }
                var _dtx1 = _dx0 + _dtc * _cs;
                var _dty1 = _dy0 + _dtr * _cs;
                draw_set_color(_bb_badge[clamp(_dtv, 1, 16)]);
                draw_set_alpha(0.75);
                draw_rectangle(_dtx1, _dty1, _dtx1 + _cs, _dty1 + _cs, false);
                draw_set_alpha(1.0);
                draw_set_color(c_black);
				draw_text(_dtx1 + 1, _dty1 + 1, "T" + string(_dtv));
            }
        }
        draw_set_font(fnt_c64_tiny);
        draw_set_alpha(1.0);
    }

    // ── TAG BRUSH CURSOR ─────────────────────────────────────────────────
    if (_m.tag_mode == 1 && _in_src && _tags != noone) {
        var _bx1 = _sx0 + _sc * _cs;
        var _by1 = _sy0 + _sr * _cs;
        if (_m.tag_type == 0) {
            draw_set_color(c_white);
        } else {
            draw_set_color(_bb_badge[clamp(_m.tag_type, 1, 16)]);
        }
        draw_rectangle(_bx1, _by1, _bx1 + _cs, _by1 + _cs, true);
        draw_rectangle(_bx1 - 1, _by1 - 1, _bx1 + _cs + 1, _by1 + _cs + 1, true);
        draw_set_font(fnt_c64_pico);
        draw_set_color(c_white);
        draw_text(_bx1 + 2, _by1 - 10,
            (_m.tag_type == 0) ? "ERASE" : ("T" + string(_m.tag_type)));
        draw_set_font(fnt_c64_tiny);
    }

    // ── HIGHLIGHT THE SELECTED RECORD ON BOTH PANELS ─────────────────────
    if (_m.sel_rec >= 0 && _m.sel_rec < array_length(_m.records)) {
        var _sel = _m.records[_m.sel_rec];
        if (_sel.kind == "REC") {
            var _hs_x1 = _sx0 + _sel.sx * _cs;
            var _hs_y1 = _sy0 + _sel.sy * _cs;
            var _hs_x2 = _sx0 + (_sel.sx + _sel.w) * _cs;
            var _hs_y2 = _sy0 + (_sel.sy + _sel.h) * _cs;
            var _hd_x1 = _dx0 + _sel.dx * _cs;
            var _hd_y1 = _dy0 + _sel.dy * _cs;
            var _hd_x2 = _dx0 + (_sel.dx + _sel.w) * _cs;
            var _hd_y2 = _dy0 + (_sel.dy + _sel.h) * _cs;
            var _pulse = 0.35 + 0.25 * sin(current_time / 150);
            draw_set_color(make_color_rgb(120, 255, 140));
            draw_set_alpha(_pulse);
            draw_rectangle(_hs_x1, _hs_y1, _hs_x2, _hs_y2, false);
            draw_rectangle(_hd_x1, _hd_y1, _hd_x2, _hd_y2, false);
            draw_set_alpha(1.0);
            draw_rectangle(_hs_x1, _hs_y1, _hs_x2, _hs_y2, true);
            draw_rectangle(_hd_x1, _hd_y1, _hd_x2, _hd_y2, true);
        }
    }

    // ── LIVE CELL READOUT UNDER THE PANELS ───────────────────────────────
    // Two independent readouts, each parked under its own panel: SOURCE beneath
    // the source panel (_sx0), DEST beneath the dest panel (_dx0). Each lights up
    // only while the mouse is over that panel, so both can show at once when the
    // cursor sits over one — and the other simply reads "--" rather than blanking
    // the whole line the way the old shared if/else did.
    draw_set_font(fnt_c64_tiny);
    var _ry_out = _sy0 + _ph + 6;

    // SOURCE readout (under the source panel)
    draw_set_color(make_color_rgb(90, 90, 120));
    draw_text(_sx0, _ry_out, "CELL:");
    if (_in_src) {
        draw_set_color(c_aqua);
        draw_text(_sx0 + 48, _ry_out, "COL " + string(_sc) + "   ROW " + string(_sr));
    } else {
        draw_set_color(make_color_rgb(60, 60, 80));
        draw_text(_sx0 + 48, _ry_out, "--");
    }

    // DEST readout (under the dest panel)
    draw_set_color(make_color_rgb(90, 90, 120));
    draw_text(_dx0, _ry_out, "CELL:");
    if (_in_dst) {
        draw_set_color(c_yellow);
        draw_text(_dx0 + 48, _ry_out, "COL " + string(_dc) + "   ROW " + string(_dr));
    } else {
        draw_set_color(make_color_rgb(60, 60, 80));
        draw_text(_dx0 + 48, _ry_out, "--");
    }

    // ── EDIT BUTTONS (jump straight into the linked bitmap's pixel editor) ─
    // SRC and DST are already linked, so there's no picker: each button knows
    // its asset. Clicking one repoints the asset viewer at that bitmap and arms
    // edit mode — the exact state you'd reach by opening it from the asset panel
    // and pressing EDIT, minus that second click.
    //
    // The BITMAP viewer case lazily rebuilds its own undo stack, pixel backup
    // and (from the file) its surface, so this only has to guarantee a canvas
    // surface exists first — otherwise an unedited, never-imported bitmap would
    // land the user on a "NO FILE LOADED" panel while nominally in edit mode.
    var _bb_edit_bitmap = function(_bmp_idx, _bmp_asset) {
        var _bm = _bmp_asset.meta;
        if (!surface_exists(_bm.preview_surf)) {
            if (buffer_exists(_bmp_asset.buffer) && buffer_get_size(_bmp_asset.buffer) >= 10003) {
                scr_asset_bmp_build_preview(_bmp_asset);
            } else if (_bmp_asset.file != "" && file_exists(_bmp_asset.file)) {
                scr_asset_kla_reload(_bmp_asset);
            } else {
                // Brand-new empty bitmap — seed a blank BG-filled canvas.
                _bm.preview_surf = surface_create(320, 200);
                surface_set_target(_bm.preview_surf);
                draw_clear(scr_c64_pepto_colour(_bm.bg_col));
                surface_reset_target();
            }
        }
        _bm.is_editing                 = true;
        // Seed the paint-tool fields the BITMAP editor reads mid-draw. The normal
        // click-to-open path initialises these lazily, but jumping straight into
        // edit mode skips that, so an un-opened dest bitmap would hit the draw
        // tools with active_color (and friends) unset. Only fill what's missing —
        // never clobber a value the user already has.
        if (!variable_struct_exists(_bm, "active_color"))       _bm.active_color       = 1;
        if (!variable_struct_exists(_bm, "bg_col"))             _bm.bg_col             = 0;
        if (!variable_struct_exists(_bm, "active_tool"))        _bm.active_tool        = "DRAW";
        if (!variable_struct_exists(_bm, "dither_mode"))        _bm.dither_mode        = "NONE";
        if (!variable_struct_exists(_bm, "dither_invert"))      _bm.dither_invert      = false;
        if (!variable_struct_exists(_bm, "replace_mode"))       _bm.replace_mode       = false;
        if (!variable_struct_exists(_bm, "replace_col_detect")) _bm.replace_col_detect = 0;
        if (!variable_struct_exists(_bm, "replace_col_target")) _bm.replace_col_target = 1;
        if (!variable_struct_exists(_bm, "brush_size"))         _bm.brush_size         = 0;
        // Breadcrumb: remember which builder sent us here so the BITMAP viewer
        // can offer a RETURN button. Stored as the builder's asset_list index,
        // resolved via viewer_asset (that's what this editor is running for).
        // -1 elsewhere means "not from a builder", so the button stays hidden.
        obj_asset_manager.bb_return_asset = obj_asset_manager.viewer_asset;
        obj_asset_manager.viewer_asset    = _bmp_idx;
    };

    var _eb_y = _ry_out + 16;
    var _eb_h = 18;
    var _eb_w = 120;

    // SOURCE — aligned to the source panel's left edge.
    var _esb_x1  = _sx0;
    var _esb_x2  = _esb_x1 + _eb_w;
    var _esb_hov = point_in_rectangle(_mx, _my, _esb_x1, _eb_y, _esb_x2, _eb_y + _eb_h);
    if (_src != noone) {
        if (_esb_hov) {
            draw_set_color(make_color_rgb(90, 200, 220));
        } else {
            draw_set_color(make_color_rgb(25, 90, 105));
        }
        draw_rectangle(_esb_x1, _eb_y, _esb_x2, _eb_y + _eb_h, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text((_esb_x1 + _esb_x2) * 0.5, _eb_y + 4, "EDIT SOURCE");
        draw_set_halign(fa_left);
        if (_esb_hov && mouse_check_button_pressed(mb_left)) {
            _bb_edit_bitmap(_src_idx, _src);
        }
    } else {
        draw_set_color(make_color_rgb(30, 30, 40));
        draw_rectangle(_esb_x1, _eb_y, _esb_x2, _eb_y + _eb_h, false);
        draw_set_color(make_color_rgb(80, 80, 100));
        draw_rectangle(_esb_x1, _eb_y, _esb_x2, _eb_y + _eb_h, true);
        draw_set_color(make_color_rgb(90, 90, 110));
        draw_set_halign(fa_center);
        draw_text((_esb_x1 + _esb_x2) * 0.5, _eb_y + 4, "NO SRC LINKED");
        draw_set_halign(fa_left);
    }

    // DEST — aligned to the dest panel's left edge.
    var _edb_x1  = _dx0;
    var _edb_x2  = _edb_x1 + _eb_w;
    var _edb_hov = point_in_rectangle(_mx, _my, _edb_x1, _eb_y, _edb_x2, _eb_y + _eb_h);
    if (_dst != noone) {
        if (_edb_hov) {
            draw_set_color(make_color_rgb(220, 200, 90));
        } else {
            draw_set_color(make_color_rgb(105, 90, 25));
        }
        draw_rectangle(_edb_x1, _eb_y, _edb_x2, _eb_y + _eb_h, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text((_edb_x1 + _edb_x2) * 0.5, _eb_y + 4, "EDIT DEST");
        draw_set_halign(fa_left);
        if (_edb_hov && mouse_check_button_pressed(mb_left)) {
            _bb_edit_bitmap(_dst_idx, _dst);
        }
    } else {
        draw_set_color(make_color_rgb(30, 30, 40));
        draw_rectangle(_edb_x1, _eb_y, _edb_x2, _eb_y + _eb_h, false);
        draw_set_color(make_color_rgb(80, 80, 100));
        draw_rectangle(_edb_x1, _eb_y, _edb_x2, _eb_y + _eb_h, true);
        draw_set_color(make_color_rgb(90, 90, 110));
        draw_set_halign(fa_center);
        draw_text((_edb_x1 + _edb_x2) * 0.5, _eb_y + 4, "NO DST LINKED");
        draw_set_halign(fa_left);
    }

    // ── CONTROLS / HELP ──────────────────────────────────────────────────
    // Static reference block filling the space below the EDIT buttons — two
    // columns (MOUSE / KEYS) under the source and dest panels respectively,
    // matching the width those panels already occupy. Data-driven with a
    // loop rather than one draw_text per line, since the row count here is
    // only going to grow as controls get added.
    var _hlp_y0    = _eb_y + _eb_h + 20;
    var _hlp_row_h = 16;

    draw_set_font(fnt_c64_pico);

    var _hlp_mouse = [
        ["DRAG on SOURCE",        "grab a cell rect"],
        ["CLICK on DEST",         "place / stamp (repeats)"],
        ["ALT + CLICK on DEST",   "select record under cursor"],
        ["RMB on either panel",   "cancel grab, deselect"],
        ["DRAG a list row",       "reorder within group"],
        ["WHEEL over list",       "scroll the record list"]
    ];
    var _hlp_keys = [
        ["UP / DOWN",             "move selection"],
        ["SHIFT + UP / DOWN",     "reorder selected record"],
        ["T",                     "toggle dest tag overlay"]
    ];

    draw_set_color(make_color_rgb(120, 190, 210));
    draw_text(_sx0, _hlp_y0, "MOUSE");
    draw_set_color(make_color_rgb(220, 200, 120));
    draw_text(_dx0, _hlp_y0, "KEYS");

    for (var _hi = 0; _hi < array_length(_hlp_mouse); _hi++) {
        var _hy = _hlp_y0 + 18 + (_hi * _hlp_row_h);
        draw_set_color(make_color_rgb(180, 180, 200));
        draw_text(_sx0, _hy, _hlp_mouse[_hi][0]);
        draw_set_color(make_color_rgb(100, 100, 120));
        draw_text(_sx0 + 170, _hy, "- " + _hlp_mouse[_hi][1]);
    }

    for (var _hk = 0; _hk < array_length(_hlp_keys); _hk++) {
        var _hyk = _hlp_y0 + 18 + (_hk * _hlp_row_h);
        draw_set_color(make_color_rgb(180, 180, 200));
        draw_text(_dx0, _hyk, _hlp_keys[_hk][0]);
        draw_set_color(make_color_rgb(100, 100, 120));
        draw_text(_dx0 + 170, _hyk, "- " + _hlp_keys[_hk][1]);
    }

    draw_set_font(fnt_c64_tiny);

    // ═════════════════════════════════════════════════════════════════════
    // RECORD LIST
    // ═════════════════════════════════════════════════════════════════════
    var _ly0    = _sy0;
    var _row_h  = 15;
    var _list_h = _ph + 240;                     // extends 300px below the bitmap panels
    var _vis    = max(0, floor(_list_h / _row_h));
    var _rcount = array_length(_m.records);

    // ── FILTER TO THE CURRENT GROUP ──
    // _view[] holds the RECORD indices of the rows on screen. Everything below
    // still reads and mutates _m.records by real index, so delete / up / down
    // keep working on the flat array unchanged — only which rows are shown moves.
    // The group's closing $FF IS included, as the visible end-of-run marker.
    // _grp_of was built at the top of this frame, but the buttons above (+ ADD,
    // group delete) and the stamp commit all mutate _m.records mid-frame — so
    // _rcount can now exceed the map. Anything past the map's extent was appended
    // after it was built, which by definition puts it in the LAST group, so treat
    // it as such rather than indexing off the end. The map is rebuilt correctly on
    // the next frame; this only has to survive the one where they disagree.
    var _gmap_len = array_length(_grp_of);
    var _view = [];
    for (var _vi2 = 0; _vi2 < _rcount; _vi2++) {
        var _vg = (_vi2 < _gmap_len) ? _grp_of[_vi2] : (_grp_count - 1);
        if (_vg == _cur_grp) {
            array_push(_view, _vi2);
        }
    }
    var _vcount = array_length(_view);

    // Centre the list on a row just picked via alt-click, so the selection is
    // visible without hunting through the scroll. Centred rather than
    // top/bottom because the click can land anywhere in a long group and a
    // mid-list jump reads clearer than a row pinned to either edge.
    if (_ac_center_row >= 0) {
        var _ac_view_pos = -1;
        for (var _acvi = 0; _acvi < _vcount; _acvi++) {
            if (_view[_acvi] == _ac_center_row) {
                _ac_view_pos = _acvi;
                break;
            }
        }
        if (_ac_view_pos >= 0) {
            _m.list_scroll = _ac_view_pos - floor(_vis / 2);
        }
    }

    _m.list_scroll = clamp(_m.list_scroll, 0, max(0, _vcount - _vis));

    draw_set_font(fnt_c64_tiny);
    // Every slot — data record AND $FF sentinel — is a full 6-byte record.
    // MOVE_BMP_BLOCK seeks with base + (entry * 6), so the stride must not vary.
    // A trailing sentinel is always appended by scr_bitmap_builder_generate, so
    // account for it here if the list doesn't already end in one.
    var _has_end_tail = false;
    if (_rcount > 0) {
        if (_m.records[_rcount - 1].kind == "END") {
            _has_end_tail = true;
        }
    }
    var _emit_recs = _rcount;
    if (!_has_end_tail) {
        _emit_recs += 1;
    }
    // ── MIRRORED GROUP SELECTOR (over the record list) ──
    // Same controls as the toolbar pair at the top-left, echoed here so you can
    // switch groups without dragging the mouse back across the whole panel. Both
    // sets write the same state (prev_entry / list_scroll / records), so they
    // stay in lockstep by construction — there's no second source of truth.
    var _mgy = _ly0 - 78;

    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(_lx0, _mgy + 4, "GROUP ID:");

    // Prev
    var _mpx1   = _lx0 + 72;
    var _mpx2   = _mpx1 + 18;
    var _mp_hov = point_in_rectangle(_mx, _my, _mpx1, _mgy, _mpx2, _mgy + 18);
    draw_set_color(_mp_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_mpx1, _mgy, _mpx2, _mgy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_mpx1 + 9, _mgy + 4, "<");
    draw_set_halign(fa_left);
    if (_mp_hov && mouse_check_button_pressed(mb_left)) {
        var _mpg = max(0, _cur_grp - 1);
        _m.prev_entry  = _grp_start[_mpg];
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
    }

    // Number
    draw_set_color(make_color_rgb(255, 200, 100));
    draw_set_halign(fa_center);
    draw_text(_mpx2 + 22, _mgy + 4, string(_cur_grp));
    draw_set_halign(fa_left);

    // Next
    var _mnx1   = _mpx2 + 38;
    var _mnx2   = _mnx1 + 18;
    var _mn_hov = point_in_rectangle(_mx, _my, _mnx1, _mgy, _mnx2, _mgy + 18);
    draw_set_color(_mn_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_mnx1, _mgy, _mnx2, _mgy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_mnx1 + 9, _mgy + 4, ">");
    draw_set_halign(fa_left);
    if (_mn_hov && mouse_check_button_pressed(mb_left)) {
        var _mng = min(max(0, _grp_count - 1), _cur_grp + 1);
        _m.prev_entry  = _grp_start[_mng];
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
    }

    // Count
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 90, 120));
    draw_text(_mnx2 + 8, _mgy + 6, "OF " + string(_grp_count));
    draw_set_font(fnt_c64_tiny);

    // + ADD — identical behaviour to the toolbar copy: close the current last
    // group if it isn't already closed, then push the new group's own sentinel.
    var _max1   = _mnx2 + 44;
    var _max2   = _max1 + 70;
    var _ma_hov = point_in_rectangle(_mx, _my, _max1, _mgy, _max2, _mgy + 18);
    draw_set_color(_ma_hov ? make_color_rgb(60, 200, 80) : make_color_rgb(20, 100, 40));
    draw_rectangle(_max1, _mgy, _max2, _mgy + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_max1 + _max2) * 0.5, _mgy + 4, "+ ADD");
    draw_set_halign(fa_left);
    if (_ma_hov && mouse_check_button_pressed(mb_left)) {
        _bb_push_undo(_m, _bb_snap);
        var _ma_len = array_length(_m.records);
        var _ma_closed = false;
        if (_ma_len > 0) {
            if (_m.records[_ma_len - 1].kind == "END") {
                _ma_closed = true;
            }
        }
        if (!_ma_closed) {
            array_push(_m.records, { kind : "END" });
        }
        array_push(_m.records, { kind : "END" });
        _m.prev_entry  = array_length(_m.records) - 1;
        _m.sel_rec     = -1;
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
        _m.is_dirty    = true;
    }

    // RMB the number to delete this group (records + its sentinel).
    var _md_hov = point_in_rectangle(_mx, _my, _mpx2, _mgy, _mnx1, _mgy + 18);
    if (_md_hov && mouse_check_button_pressed(mb_right) && _grp_count > 1) {
        _bb_push_undo(_m, _bb_snap);
        var _mdel_from = _grp_start[_cur_grp];
        var _mdel_to   = _total_recs;
        if (_cur_grp + 1 < _grp_count) {
            _mdel_to = _grp_start[_cur_grp + 1];
        }
        array_delete(_m.records, _mdel_from, _mdel_to - _mdel_from);
        _m.prev_entry  = clamp(_mdel_from, 0, max(0, array_length(_m.records) - 1));
        _m.sel_rec     = -1;
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
        _m.is_dirty    = true;
    }

    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    // Group's own row count and byte cost on the left; the WHOLE table's byte
    // cost on the right, since that's what the BYTE_DATA asset actually
    // occupies. _vcount already includes this group's own $FF terminator (see
    // the _view filter above), so _vcount * 6 is its true byte cost.
    draw_text(_lx0, _ly0 - 54, "GROUP " + string(_cur_grp)
        + " (" + string(_vcount) + ")  "
        + string(_vcount * 6) + "B     ALL: "
        + string(_emit_recs) + "x6 = "
        + string(_emit_recs * 6) + "B");

    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_lx0 - 4, _ly0 - 2, _lx0 + _lw + 4, _ly0 + _vis * _row_h + 2, false);
    draw_set_color(make_color_rgb(50, 50, 70));
    draw_rectangle(_lx0 - 4, _ly0 - 2, _lx0 + _lw + 4, _ly0 + _vis * _row_h + 2, true);

    // Column header
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(90, 90, 120));
    draw_text(_lx0 + 44, _ly0 - 16, "SX  SY   DX  DY    W   H");
    draw_set_font(fnt_c64_tiny);

    for (var _r = 0; _r < _vis; _r++) {
        var _vrow = _r + _m.list_scroll;
        if (_vrow >= _vcount) {
            break;
        }
        var _ridx = _view[_vrow];   // real index into _m.records
        var _rec  = _m.records[_ridx];
        var _rry  = _ly0 + _r * _row_h;
        var _rhov = point_in_rectangle(_mx, _my, _lx0, _rry, _lx0 + _lw, _rry + _row_h);
        var _rsel = (_m.sel_rec == _ridx);

        if (_rsel) {
            draw_set_color(make_color_rgb(30, 80, 60));
            draw_rectangle(_lx0, _rry, _lx0 + _lw, _rry + _row_h, false);
        } else if (_rhov) {
            draw_set_color(make_color_rgb(40, 40, 60));
            draw_rectangle(_lx0, _rry, _lx0 + _lw, _rry + _row_h, false);
        }

        // The ENTRY marker: this is the record the preview replay starts from.
        if (_ridx == _m.prev_entry) {
            draw_set_color(make_color_rgb(255, 200, 100));
            draw_text(_lx0 + 2, _rry, ">");
        }

        draw_set_color(make_color_rgb(100, 100, 140));
        draw_text(_lx0 + 12, _rry, string(_ridx));

        // Group tag — the number you feed the node's ENTRY VAR to draw this run.
        // Highlighted on the group the preview is currently showing.
        var _row_grp = (_ridx < _gmap_len) ? _grp_of[_ridx] : (_grp_count - 1);
        if (_row_grp == _cur_grp) {
            draw_set_color(make_color_rgb(255, 200, 100));
        } else {
            draw_set_color(make_color_rgb(70, 90, 120));
        }
        draw_set_font(fnt_c64_pico);
        draw_text(_lx0 + 28, _rry + 2, "G" + string(_row_grp) + " :  ");
        draw_set_font(fnt_c64_tiny);

        if (_rec.kind == "END") {
            draw_set_color(make_color_rgb(255, 120, 120));
            draw_text(_lx0 + 42, _rry, "--- $FF  END OF RUN ---");
        } else {
            draw_set_color(c_white);
            draw_text(_lx0 + 42, _rry,
                string(_rec.sx) + "  " + string(_rec.sy) + "   "
              + string(_rec.dx) + "  " + string(_rec.dy) + "    "
              + string(_rec.w)  + "   " + string(_rec.h));
        }

        // Delete button.
        // A sentinel is a GROUP BOUNDARY, not a record — deleting the only one
        // leaves a list with no terminator at all, and the whole group model
        // (here and in the 6502 seek) is built on there being at least one.
        // Guard it: the last remaining sentinel can't be removed, so the [X]
        // greys out on that row. Group deletion (RMB the group number) is the
        // supported way to lose a boundary, and that path already refuses to
        // drop the final group.
        var _dl_locked = false;
        if (_rec.kind == "END") {
            var _sent_count = 0;
            for (var _sci2 = 0; _sci2 < _rcount; _sci2++) {
                if (_m.records[_sci2].kind == "END") {
                    _sent_count += 1;
                }
            }
            if (_sent_count <= 1) {
                _dl_locked = true;
            }
        }

        var _dlx = _lx0 + _lw - 22;
        var _dhov = point_in_rectangle(_mx, _my, _dlx, _rry, _dlx + 22, _rry + _row_h);
        if (_dl_locked) {
            draw_set_color(make_color_rgb(55, 45, 45));
        } else {
            draw_set_color(_dhov ? c_red : make_color_rgb(120, 60, 60));
        }
        draw_text(_dlx, _rry, "[X]");
        if (_dhov && !_dl_locked && mouse_check_button_pressed(mb_left)) {
            _bb_push_undo(_m, _bb_snap);
            array_delete(_m.records, _ridx, 1);
            if (_m.sel_rec >= array_length(_m.records)) {
                _m.sel_rec = array_length(_m.records) - 1;
            }
            _m.prev_entry = clamp(_m.prev_entry, 0, max(0, array_length(_m.records) - 1));
            _m.prev_dirty = true;
            _m.is_dirty   = true;
            break;  // array mutated — stop iterating this frame
        }

        // Row select / drag start. Clicking a row also makes it the preview
        // ENTRY, so you can click a run's first record and immediately see
        // that run redraw. The same press arms a potential drag — whether it
        // ends up being a plain select or a reorder is decided on release,
        // based on whether the mouse ever left this row.
        if (_rhov && !_dhov && mouse_check_button_pressed(mb_left)) {
            _m.sel_rec        = _ridx;
            _m.prev_entry     = _ridx;
            _m.prev_dirty     = true;
            // Sentinels are group boundaries, not draggable rows — only a
            // REC row arms a drag. Clicking an END row still selects it, it
            // just can't be picked up and moved.
            if (_rec.kind == "REC") {
                _m.list_drag_row  = _ridx;
                _m.list_drag_over = _ridx;
            }
        }

        // While a drag is in progress, track which row the mouse is over and
        // draw an insertion line so it's clear where the record will land.
        if (_m.list_drag_row >= 0 && _rhov) {
            _m.list_drag_over = _ridx;
        }
        if (_m.list_drag_row >= 0 && _m.list_drag_over == _ridx) {
            draw_set_color(c_yellow);
            draw_line(_lx0, _rry, _lx0 + _lw, _rry);
        }
    }

    // ── DRAG COMMIT ──────────────────────────────────────────────────────
    // Release anywhere ends the drag. Only reorder if the pointer actually
    // moved to a different row than it started on — otherwise this was a
    // plain click, already handled as a select above, and re-inserting the
    // record at its own position would be a no-op wrapped in an undo push.
    if (_m.list_drag_row >= 0 && mouse_check_button_released(mb_left)) {
        var _drag_from = _m.list_drag_row;
        var _drag_to   = _m.list_drag_over;
        // Dropping on the group's END row is allowed and intentional: the
        // insert position below lands just BEFORE that sentinel, which makes
        // the dragged record the last one in the group. It can never end up
        // AFTER the sentinel, so this never crosses into the next group.
        if (_drag_to >= 0 && _drag_to != _drag_from
        &&  _drag_from < array_length(_m.records)
        &&  _drag_to   < array_length(_m.records)) {
            _bb_push_undo(_m, _bb_snap);
            var _drag_rec = _m.records[_drag_from];
            array_delete(_m.records, _drag_from, 1);
            var _drag_ins = _drag_to;
            if (_drag_to > _drag_from) {
                _drag_ins -= 1;   // the delete above shifted everything after it back by one
            }
            array_insert(_m.records, _drag_ins, _drag_rec);
            _m.sel_rec    = _drag_ins;
            _m.prev_entry = _drag_ins;
            _m.prev_dirty = true;
            _m.is_dirty   = true;
        }
        _m.list_drag_row  = -1;
        _m.list_drag_over = -1;
    }

    // List wheel scroll
    if (point_in_rectangle(_mx, _my, _lx0 - 4, _ly0 - 2, _lx0 + _lw + 4, _ly0 + _vis * _row_h + 2)) {
        if (mouse_wheel_up()) {
            _m.list_scroll = max(0, _m.list_scroll - 1);
        }
        if (mouse_wheel_down()) {
            _m.list_scroll = min(max(0, _vcount - _vis), _m.list_scroll + 1);
        }
    }

    // ── KEYBOARD NAVIGATION ──────────────────────────────────────────────
    // Plain UP/DOWN walk the selection through the CURRENT GROUP's visible
    // rows only, same as clicking a row, so the cursor never jumps into a
    // different group. SHIFT+UP/DOWN reorders the selected record and reuses
    // the exact swap logic the UP/DOWN buttons use, so both paths can never
    // drift apart.
    var _sel_view_pos = -1;
    for (var _svi = 0; _svi < _vcount; _svi++) {
        if (_view[_svi] == _m.sel_rec) {
            _sel_view_pos = _svi;
            break;
        }
    }

    var _kb_shift = keyboard_check(vk_shift);

    if (keyboard_check_pressed(vk_up)) {
        if (_kb_shift) {
            if (_m.sel_rec > 0 && _m.sel_rec < array_length(_m.records)) {
                _bb_push_undo(_m, _bb_snap);
                var _tmp_ku = _m.records[_m.sel_rec - 1];
                _m.records[_m.sel_rec - 1] = _m.records[_m.sel_rec];
                _m.records[_m.sel_rec]     = _tmp_ku;
                _m.sel_rec    -= 1;
                _m.prev_entry  = _m.sel_rec;
                _m.prev_dirty  = true;
                _m.is_dirty    = true;
            }
        } else {
            if (_sel_view_pos > 0) {
                _m.sel_rec    = _view[_sel_view_pos - 1];
                _m.prev_entry = _m.sel_rec;
                _m.prev_dirty = true;
            } else if (_sel_view_pos == -1 && _vcount > 0) {
                _m.sel_rec    = _view[_vcount - 1];
                _m.prev_entry = _m.sel_rec;
                _m.prev_dirty = true;
            }
        }
    }

    if (keyboard_check_pressed(vk_down)) {
        if (_kb_shift) {
            if (_m.sel_rec >= 0 && _m.sel_rec < array_length(_m.records) - 1) {
                _bb_push_undo(_m, _bb_snap);
                var _tmp_kd = _m.records[_m.sel_rec + 1];
                _m.records[_m.sel_rec + 1] = _m.records[_m.sel_rec];
                _m.records[_m.sel_rec]     = _tmp_kd;
                _m.sel_rec    += 1;
                _m.prev_entry  = _m.sel_rec;
                _m.prev_dirty  = true;
                _m.is_dirty    = true;
            }
        } else {
            if (_sel_view_pos >= 0 && _sel_view_pos < _vcount - 1) {
                _m.sel_rec    = _view[_sel_view_pos + 1];
                _m.prev_entry = _m.sel_rec;
                _m.prev_dirty = true;
            } else if (_sel_view_pos == -1 && _vcount > 0) {
                _m.sel_rec    = _view[0];
                _m.prev_entry = _m.sel_rec;
                _m.prev_dirty = true;
            }
        }
    }

    // Keep the selected row scrolled into view after any of the moves above.
    _sel_view_pos = -1;
    for (var _svi2 = 0; _svi2 < _vcount; _svi2++) {
        if (_view[_svi2] == _m.sel_rec) {
            _sel_view_pos = _svi2;
            break;
        }
    }
    if (_sel_view_pos >= 0) {
        if (_sel_view_pos < _m.list_scroll) {
            _m.list_scroll = _sel_view_pos;
        }
        if (_sel_view_pos >= _m.list_scroll + _vis) {
            _m.list_scroll = _sel_view_pos - _vis + 1;
        }
    }

    // ── LIST BUTTONS ─────────────────────────────────────────────────────
    var _by = _ly0 + _vis * _row_h + 10;

    // + END — pushes an $FF divider. Everything after it is a new run, and the
    // ENTRY VAR on the node picks which run gets drawn at runtime.
    var _aex1 = _lx0;
    var _aex2 = _aex1 + 80;
    var _ae_hov = point_in_rectangle(_mx, _my, _aex1, _by, _aex2, _by + 18);
    draw_set_color(_ae_hov ? make_color_rgb(180, 70, 70) : make_color_rgb(90, 30, 30));
    draw_rectangle(_aex1, _by, _aex2, _by + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_aex1 + _aex2) * 0.5, _by + 4, "+ $FF END");
    draw_set_halign(fa_left);
    // Same as the + ADD button above — kept for muscle memory. See there for why
    // this pushes up to two sentinels rather than one.
    if (_ae_hov && mouse_check_button_pressed(mb_left)) {
        _bb_push_undo(_m, _bb_snap);
        var _ae_len = array_length(_m.records);
        var _ae_closed = false;
        if (_ae_len > 0) {
            if (_m.records[_ae_len - 1].kind == "END") {
                _ae_closed = true;
            }
        }
        if (!_ae_closed) {
            array_push(_m.records, { kind : "END" });
        }
        array_push(_m.records, { kind : "END" });
        _m.prev_entry  = array_length(_m.records) - 1;
        _m.sel_rec     = -1;
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
        _m.is_dirty    = true;
    }

    // MOVE UP / MOVE DOWN — reorder the selected record.
    var _upx1 = _aex2 + 8;
    var _upx2 = _upx1 + 34;
    var _up_hov = point_in_rectangle(_mx, _my, _upx1, _by, _upx2, _by + 18);
    draw_set_color(_up_hov ? make_color_rgb(80, 80, 110) : make_color_rgb(40, 40, 60));
    draw_rectangle(_upx1, _by, _upx2, _by + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_upx1 + _upx2) * 0.5, _by + 4, "UP");
    draw_set_halign(fa_left);
    if (_up_hov && mouse_check_button_pressed(mb_left)) {
        if (_m.sel_rec > 0 && _m.sel_rec < array_length(_m.records)) {
            _bb_push_undo(_m, _bb_snap);
            var _tmp_u = _m.records[_m.sel_rec - 1];
            _m.records[_m.sel_rec - 1] = _m.records[_m.sel_rec];
            _m.records[_m.sel_rec]     = _tmp_u;
            _m.sel_rec   -= 1;
            _m.prev_dirty = true;
            _m.is_dirty   = true;
        }
    }

    var _dnx1 = _upx2 + 6;
    var _dnx2 = _dnx1 + 46;
    var _dn_hov = point_in_rectangle(_mx, _my, _dnx1, _by, _dnx2, _by + 18);
    draw_set_color(_dn_hov ? make_color_rgb(80, 80, 110) : make_color_rgb(40, 40, 60));
    draw_rectangle(_dnx1, _by, _dnx2, _by + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_dnx1 + _dnx2) * 0.5, _by + 4, "DOWN");
    draw_set_halign(fa_left);
    if (_dn_hov && mouse_check_button_pressed(mb_left)) {
        if (_m.sel_rec >= 0 && _m.sel_rec < array_length(_m.records) - 1) {
            _bb_push_undo(_m, _bb_snap);
            var _tmp_d = _m.records[_m.sel_rec + 1];
            _m.records[_m.sel_rec + 1] = _m.records[_m.sel_rec];
            _m.records[_m.sel_rec]     = _tmp_d;
            _m.sel_rec   += 1;
            _m.prev_dirty = true;
            _m.is_dirty   = true;
        }
    }

    // CLEAR ALL
    var _clx1 = _dnx2 + 8;
    var _clx2 = _clx1 + 70;
    var _cl_hov = point_in_rectangle(_mx, _my, _clx1, _by, _clx2, _by + 18);
    draw_set_color(_cl_hov ? make_color_rgb(200, 60, 60) : make_color_rgb(120, 30, 30));
    draw_rectangle(_clx1, _by, _clx2, _by + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_clx1 + _clx2) * 0.5, _by + 4, "CLR GRP");
    draw_set_halign(fa_left);
    // CLEAR wipes the CURRENT GROUP only — its records go, its closing sentinel
    // stays. Nuking the whole list from a filtered view would be a nasty
    // surprise: you can only see one group, so that's the only one you'd expect
    // to lose. _view already holds this group's record indices; delete them back
    // to front so the earlier indices stay valid as the array shrinks, and skip
    // the sentinel so the group (and every group after it) survives.
    if (_cl_hov && mouse_check_button_pressed(mb_left)) {
        _bb_push_undo(_m, _bb_snap);
        for (var _cvi = _vcount - 1; _cvi >= 0; _cvi--) {
            var _cri = _view[_cvi];
            if (_cri >= array_length(_m.records)) {
                continue;
            }
            if (_m.records[_cri].kind == "END") {
                continue;   // the group's terminator stays put
            }
            array_delete(_m.records, _cri, 1);
        }
        // Park the cursor on the group's own sentinel — that's what an empty
        // group looks like, and it keeps _cur_grp pointing at this group.
        _m.prev_entry  = clamp(_grp_start[_cur_grp], 0, max(0, array_length(_m.records) - 1));
        _m.sel_rec     = -1;
        _m.list_scroll = 0;
        _m.prev_dirty  = true;
        _m.is_dirty    = true;
    }

    // Reset draw state so nothing leaks.
    gpu_set_texfilter(_entry_filter);
    draw_set_alpha(1.0);
    draw_set_color(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}
