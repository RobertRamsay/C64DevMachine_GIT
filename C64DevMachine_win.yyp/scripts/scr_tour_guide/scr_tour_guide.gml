/// scr_tour_guide - Guided tours (DOCUMENTS > GUIDED TOURS).
///
/// A tour is an array of steps. Each step has a title, body text, a list of
/// highlight targets (first one found on screen wins) and a check code that
/// auto-advances the tour when the user has done the thing.
///
/// Highlight targets:
///   PAL:<title>         opcode palette button   (captured by workspace Draw GUI)
///   ARROW:L / ARROW:R   palette page arrows     (captured)
///   MENU:<n>            menu bar button n       (captured)
///   MAC:<type>          MACROS dropdown row     (captured)
///   NODEOP:<op>         first connected NORMAL node using that opcode
///   NODETYPE:<type>     first connected node of that type
///   OPERAND0:<op>       operand of a connected NORMAL node still at 0 (captured)
///   FIELD:<type>:<name> one editable field on a macro node        (captured)
///   ASSET:ADD           [ADD ASSET +] button
///   ASSET:TYPE:<type>   row in the add-asset dropdown (only while open)
///   ASSET:PANEL         the asset list
///
/// Captured targets are written by scr_tour_capture() from the existing draw
/// loops, so the highlight always sits exactly on what was drawn this frame.

/// @desc Start (or restart) tour _id.
function scr_tour_start(_id) {
    if (instance_exists(obj_tour_guide)) {
        instance_destroy(obj_tour_guide);
    }
    // Depth doubles as the draw z. GameMaker clips anything at or beyond
    // +/-16000, so -16000 drew nothing at all. -14000 keeps it above the
    // colour pickers (-9999) and inside the visible range.
    var _t = instance_create_depth(0, 0, -14000, obj_tour_guide);
    with (_t) {
        tour_id    = _id;
        tour_title = scr_tour_title(_id);
        steps      = scr_tour_define(_id);
        step_idx   = 0;

        // The palette is hidden in expert mode; show it for the tour and put
        // the user's setting back when the tour ends.
        if (obj_workspace_manager.expert_mode) {
            obj_workspace_manager.expert_mode = false;
            restore_expert = true;
        }
        scr_tour_enter_step();
    }
    global.tour_active = true;
}

/// @desc Tour names, shown in the caption header.
function scr_tour_title(_id) {
    var _list = scr_tour_list();
    if (_id >= 0 && _id < array_length(_list)) {
        return _list[_id].title;
    }
    return "TOUR";
}

/// @desc Every tour, in menu order. Index = tour id used by scr_tour_define.
///       Add new tours here and give them a matching block in scr_tour_define.
function scr_tour_list() {
    return [
        { title: "BORDER & BACKGROUND", blurb: "Drag in opcodes and set the border and background colours." },
        { title: "YOUR FIRST MACRO",    blurb: "Drag in the PRINT macro and put a message on screen." },
        { title: "BITMAP BASICS",       blurb: "Paint a bitmap asset and show it with the BITMAP macro." },
    ];
}

/// @desc Welcome panel tour list geometry. Shared by Step (clicks) and
///       Draw GUI (drawing) so the two can never disagree.
function scr_tour_welcome_geom(_px, _py, _pw, _ph) {
    var _btn_w  = 190;
    var _btn_h  = 30;
    var _btn_x2 = _px + _pw - 20;
    var _btn_y1 = _py + _ph - 46;
    var _row_h  = 40;
    var _list_y1 = _py + 96;
    var _list_y2 = _py + _ph - 60;
    return {
        btn   : [_btn_x2 - _btn_w, _btn_y1, _btn_x2, _btn_y1 + _btn_h],
        list  : [_px + 20, _list_y1, _px + _pw - 20, _list_y2],
        row_h : _row_h,
        rows  : floor((_list_y2 - _list_y1) / _row_h)
    };
}

/// @desc Step builder.
function scr_tour_step(_title, _text, _targets, _check) {
    return { title: _title, text: _text, targets: _targets, check: _check };
}

/// @desc The three starter tours.
function scr_tour_define(_id) {
    var _s = [];

    if (_id == 0) {
        array_push(_s, scr_tour_step("WELCOME",
            "This tour builds a tiny program that changes the C64 border and background colours using real 6502 opcodes.\n\nEach step waits for you to do it. Click NEXT to skip a step.",
            [], "NONE"));
        array_push(_s, scr_tour_step("DRAG IN LDA_IMM",
            "LDA #value loads a number into the A register.\n\nDrag LDA_IMM from the opcode palette and drop it on the spine under SYSTEM INIT.",
            ["PAL:LDA_IMM", "ARROW:L"], "OP_LDA_IMM"));
        array_push(_s, scr_tour_step("CHOOSE A COLOUR",
            "Click the value on your LDA node, type 2 (red) and press ENTER.\n\nC64 colours run from 0 to 15.",
            ["OPERAND0:lda_imm", "NODEOP:lda_imm"], "LDA_NONZERO"));
        array_push(_s, scr_tour_step("DRAG IN STA_ABS",
            "STA stores the A register into memory.\n\nDrag STA_ABS onto the spine, under your LDA node.",
            ["PAL:STA_ABS", "ARROW:L"], "OP_STA_ABS"));
        array_push(_s, scr_tour_step("POINT IT AT THE BORDER",
            "Click the STA value and type $D020, then press ENTER.\n\n$D020 is the VIC-II border colour register.",
            ["OPERAND0:sta_abs", "NODEOP:sta_abs"], "STA_D020"));
        array_push(_s, scr_tour_step("NOW THE BACKGROUND",
            "Same again for the background.\n\nDrag another LDA_IMM onto the spine, under your STA node.",
            ["PAL:LDA_IMM", "ARROW:L"], "OP_LDA_IMM_2"));
        array_push(_s, scr_tour_step("CHOOSE A COLOUR",
            "Click the value on the new LDA node, type 7 (yellow) and press ENTER.",
            ["OPERAND0:lda_imm", "NODEOP:lda_imm"], "LDA_NONZERO_2"));
        array_push(_s, scr_tour_step("DRAG IN STA_ABS",
            "Drag another STA_ABS onto the spine, under the new LDA node.",
            ["PAL:STA_ABS", "ARROW:L"], "OP_STA_ABS_2"));
        array_push(_s, scr_tour_step("POINT IT AT THE BACKGROUND",
            "Click the new STA value, type $D021 and press ENTER.\n\n$D021 is the VIC-II background colour register.",
            ["OPERAND0:sta_abs", "NODEOP:sta_abs"], "STA_D021"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5 to build and launch.\n\nIf you are asked about a missing loop or RTS, choose YES to add an RTS.",
            [], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Your border should now be red and your background yellow.\n\nTry changing the numbers and pressing F5 again. More tours are in DOCUMENTS > GUIDED TOURS.",
            [], "NONE"));
    }

    if (_id == 1) {
        array_push(_s, scr_tour_step("WELCOME",
            "Macros are ready made nodes that write lots of 6502 for you.\n\nIn this tour you will print a message on the screen.",
            [], "NONE"));
        array_push(_s, scr_tour_step("OPEN THE MACROS MENU",
            "Click MACROS in the menu bar.",
            ["MENU:0"], "MENU_MACROS"));
        array_push(_s, scr_tour_step("DRAG IN PRINT",
            "Drag PRINT out of the list and drop it on the spine under SYSTEM INIT.",
            ["MAC:MACRO_PRINT", "MENU:0"], "HAS_PRINT"));
        array_push(_s, scr_tour_step("TYPE A MESSAGE",
            "Click the text field on the PRINT node, type HELLO C64 and press ENTER.",
            ["FIELD:MACRO_PRINT:text", "NODETYPE:MACRO_PRINT"], "PRINT_TEXT"));
        array_push(_s, scr_tour_step("MOVE IT DOWN",
            "Set the Y value on the PRINT node to 10 so the message sits mid screen.",
            ["FIELD:MACRO_PRINT:y", "NODETYPE:MACRO_PRINT"], "PRINT_Y"));
        array_push(_s, scr_tour_step("PICK A COLOUR",
            "Click the colour swatch on the PRINT node and choose any colour except white.",
            ["FIELD:MACRO_PRINT:col", "NODETYPE:MACRO_PRINT"], "PRINT_COL"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5 to build and launch.\n\nIf you are asked about a missing loop or RTS, choose YES to add an RTS.",
            [], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Your message should be on screen in your colour.\n\nEvery macro works the same way: drag it in, fill in its fields, build.",
            [], "NONE"));
    }

    if (_id == 2) {
        array_push(_s, scr_tour_step("WELCOME",
            "In this tour you will make a multicolour bitmap, paint on it and show it on the C64.",
            [], "NONE"));
        array_push(_s, scr_tour_step("ADD AN ASSET",
            "Click [ADD ASSET +] at the top of the asset panel.",
            ["ASSET:ADD"], "ADD_OPEN"));
        array_push(_s, scr_tour_step("CHOOSE BITMAP",
            "Pick BITMAP from the list. A new bitmap asset appears in the panel.",
            ["ASSET:TYPE:BITMAP", "ASSET:ADD"], "BMP_ADDED"));
        array_push(_s, scr_tour_step("OPEN THE EDITOR",
            "Click the lower half of your new BITMAP row to open the bitmap editor.",
            ["ASSET:PANEL"], "BMP_OPEN"));
        array_push(_s, scr_tour_step("DRAW SOMETHING",
            "Pick a colour and draw on the canvas with the left mouse button.",
            [], "BMP_PAINTED"));
        array_push(_s, scr_tour_step("FLOOD FILL",
            "Choose the FILL tool, pick another colour and click inside a shape to fill it.",
            [], "BMP_FILLED"));
        array_push(_s, scr_tour_step("CLOSE THE EDITOR",
            "Close the bitmap editor with its close button, top right of the viewer.",
            [], "BMP_CLOSED"));
        array_push(_s, scr_tour_step("DRAG IN BITMAP",
            "Open MACROS and drag BITMAP onto the spine under SYSTEM INIT.",
            ["MAC:MACRO_BMP", "MENU:0"], "HAS_BMP_NODE"));
        array_push(_s, scr_tour_step("LINK YOUR PICTURE",
            "Click the asset field on the BITMAP node and choose the bitmap you painted.",
            ["FIELD:MACRO_BMP:asset", "NODETYPE:MACRO_BMP"], "BMP_LINKED"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5 to build and launch.\n\nIf you are asked about a missing loop or RTS, choose YES to add an RTS.",
            [], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Your picture should be on the C64 screen.\n\nThe bitmap editor also has lines, shapes, gradients and dithering to explore.",
            [], "NONE"));
    }

    return _s;
}

/// @desc Called on the tour object whenever step_idx changes.
function scr_tour_enter_step() {
    step_timer = 0;
    done_timer = 0;
    hl_have    = false;

    var _targets = [];
    if (step_idx >= 0 && step_idx < array_length(steps)) {
        _targets = steps[step_idx].targets;
    }
    global.tour_keys   = _targets;
    global.tour_rects  = array_create(array_length(_targets), 0);
    global.tour_stamps = array_create(array_length(_targets), -1);
    for (var _i = 0; _i < array_length(_targets); _i++) {
        global.tour_rects[_i] = [0, 0, 0, 0];
    }

    base_bmp_count = scr_tour_bitmap_count();
    base_undo_top  = undefined;
    base_undo_name = "";
    base_build     = global.tour_build_count;
}

/// @desc Draw loops call this with the rect they just drew for _key.
function scr_tour_capture(_key, _x1, _y1, _x2, _y2) {
    if (!global.tour_active) {
        return;
    }
    for (var _i = 0; _i < array_length(global.tour_keys); _i++) {
        if (global.tour_keys[_i] == _key) {
            global.tour_rects[_i]  = [_x1, _y1, _x2, _y2];
            global.tour_stamps[_i] = global.tour_frame;
            return;
        }
    }
}

/// @desc Same as scr_tour_capture, but for rects drawn in world space (node
///       Draw events). Converted to GUI with the workspace camera.
function scr_tour_capture_world(_key, _x1, _y1, _x2, _y2) {
    if (!global.tour_active) {
        return;
    }
    var _wm = obj_workspace_manager;
    scr_tour_capture(_key,
        (_x1 - _wm.cam_x) / _wm.cam_zoom, (_y1 - _wm.cam_y) / _wm.cam_zoom,
        (_x2 - _wm.cam_x) / _wm.cam_zoom, (_y2 - _wm.cam_y) / _wm.cam_zoom);
}

/// @desc Operand as a number: reals pass through, "$D020" and "53280" parse.
function scr_tour_num(_v) {
    if (is_real(_v) || is_int64(_v)) {
        return _v;
    }
    if (!is_string(_v)) {
        return 0;
    }
    var _s = string_upper(string_trim(_v));
    if (_s == "") {
        return 0;
    }
    if (string_char_at(_s, 1) == "$") {
        var _hex = "0123456789ABCDEF";
        var _n   = 0;
        for (var _i = 2; _i <= string_length(_s); _i++) {
            var _d = string_pos(string_char_at(_s, _i), _hex) - 1;
            if (_d < 0) {
                return _n;
            }
            _n = (_n * 16) + _d;
        }
        return _n;
    }
    if (string_digits(_s) == _s) {
        return real(_s);
    }
    return 0;
}

/// @desc Connected NORMAL node that uses opcode _op. Prefers one whose
///       operand is still 0 (the one the user has not edited yet).
function scr_tour_node_by_op(_op) {
    var _any   = noone;
    var _fresh = noone;
    with (obj_c64_node) {
        if (is_connected && node_type == "NORMAL") {
            for (var _i = 0; _i < array_length(instructions); _i++) {
                if (string_lower(string(instructions[_i][0])) == _op) {
                    if (_any == noone) {
                        _any = id;
                    }
                    if (_fresh == noone && scr_tour_num(instructions[_i][1]) == 0) {
                        _fresh = id;
                    }
                }
            }
        }
    }
    if (_fresh != noone) {
        return _fresh;
    }
    return _any;
}

/// @desc Any connected NORMAL node with opcode _op whose operand is _val.
///       _val < 0 means "any non-zero operand".
function scr_tour_has_op_value(_op, _val) {
    var _found = false;
    with (obj_c64_node) {
        if (is_connected && node_type == "NORMAL") {
            for (var _i = 0; _i < array_length(instructions); _i++) {
                if (string_lower(string(instructions[_i][0])) == _op) {
                    var _n = scr_tour_num(instructions[_i][1]);
                    if (_val < 0) {
                        if (_n != 0) {
                            _found = true;
                        }
                    } else {
                        if (_n == _val) {
                            _found = true;
                        }
                    }
                }
            }
        }
    }
    return _found;
}

/// @desc How many connected NORMAL nodes use opcode _op.
///       _nonzero: only count ones whose operand has been set.
function scr_tour_count_op(_op, _nonzero) {
    var _c = 0;
    with (obj_c64_node) {
        if (is_connected && node_type == "NORMAL") {
            for (var _i = 0; _i < array_length(instructions); _i++) {
                if (string_lower(string(instructions[_i][0])) == _op) {
                    if (!_nonzero || scr_tour_num(instructions[_i][1]) != 0) {
                        _c++;
                    }
                }
            }
        }
    }
    return _c;
}

/// @desc First connected node of _type, or noone.
function scr_tour_node_by_type(_type) {
    var _hit = noone;
    with (obj_c64_node) {
        if (_hit == noone && is_connected && node_type == _type) {
            _hit = id;
        }
    }
    return _hit;
}

/// @desc Number of BITMAP assets in the asset list.
function scr_tour_bitmap_count() {
    var _c = 0;
    if (!instance_exists(obj_asset_manager)) {
        return 0;
    }
    var _list = obj_asset_manager.asset_list;
    for (var _i = 0; _i < ds_list_size(_list); _i++) {
        var _a = ds_list_find_value(_list, _i);
        if (_a.type == "BITMAP") {
            _c++;
        }
    }
    return _c;
}

/// @desc The BITMAP asset open in the viewer, or undefined.
function scr_tour_viewer_bitmap() {
    if (!instance_exists(obj_asset_manager)) {
        return undefined;
    }
    var _am = obj_asset_manager;
    if (!_am.viewer_open) {
        return undefined;
    }
    if (_am.viewer_asset < 0 || _am.viewer_asset >= ds_list_size(_am.asset_list)) {
        return undefined;
    }
    var _a = ds_list_find_value(_am.asset_list, _am.viewer_asset);
    if (_a.type != "BITMAP") {
        return undefined;
    }
    return _a;
}

/// @desc True once a new undo entry lands on the open bitmap.
///       _need_fill: only count it while the FILL tool is selected.
function scr_tour_bitmap_changed(_need_fill) {
    var _a = scr_tour_viewer_bitmap();
    if (is_undefined(_a)) {
        base_undo_name = "";
        return false;
    }
    var _stack = _a.meta[$ "undo_stack"];
    if (!is_array(_stack)) {
        return false;
    }
    var _top = undefined;
    if (array_length(_stack) > 0) {
        _top = _stack[array_length(_stack) - 1];
    }
    var _tool_ok = true;
    if (_need_fill) {
        _tool_ok = (_a.meta[$ "active_tool"] == "FILL");
    }
    // Re-base while the editor settles (it pushes its own first entry on
    // open), when the open asset changes, or while the wrong tool is held.
    if (step_timer < 20 || base_undo_name != _a.name || !_tool_ok) {
        base_undo_name = _a.name;
        base_undo_top  = _top;
        return false;
    }
    if (is_undefined(_top)) {
        return false;
    }
    return (_top != base_undo_top);
}

/// @desc Evaluate a step's check code. Runs on the tour object.
function scr_tour_check(_code) {
    var _n = noone;
    switch (_code) {
        case "NONE":
            return false;
        case "OP_LDA_IMM":
            return (scr_tour_node_by_op("lda_imm") != noone);
        case "LDA_NONZERO":
            return scr_tour_has_op_value("lda_imm", -1);
        case "OP_STA_ABS":
            return (scr_tour_node_by_op("sta_abs") != noone);
        case "STA_D020":
            return scr_tour_has_op_value("sta_abs", 0xD020);
        case "STA_D021":
            return scr_tour_has_op_value("sta_abs", 0xD021);
        case "OP_LDA_IMM_2":
            return (scr_tour_count_op("lda_imm", false) >= 2);
        case "LDA_NONZERO_2":
            return (scr_tour_count_op("lda_imm", true) >= 2);
        case "OP_STA_ABS_2":
            return (scr_tour_count_op("sta_abs", false) >= 2);
        case "BUILT":
            return (global.tour_build_count > base_build);
        case "MENU_MACROS":
            if (obj_workspace_manager.gui_menu_open == 0) {
                return true;
            }
            return (scr_tour_node_by_type("MACRO_PRINT") != noone);
        case "HAS_PRINT":
            return (scr_tour_node_by_type("MACRO_PRINT") != noone);
        case "PRINT_TEXT":
            _n = scr_tour_node_by_type("MACRO_PRINT");
            if (_n == noone) {
                return false;
            }
            return (string(_n.instructions[0][5]) != "");
        case "PRINT_Y":
            _n = scr_tour_node_by_type("MACRO_PRINT");
            if (_n == noone) {
                return false;
            }
            return (scr_tour_num(_n.instructions[0][2]) != 0);
        case "PRINT_COL":
            _n = scr_tour_node_by_type("MACRO_PRINT");
            if (_n == noone) {
                return false;
            }
            return (scr_tour_num(_n.instructions[0][3]) != 1);
        case "ADD_OPEN":
            if (obj_asset_manager.add_dropdown_open) {
                return true;
            }
            return (scr_tour_bitmap_count() > base_bmp_count);
        case "BMP_ADDED":
            return (scr_tour_bitmap_count() > base_bmp_count);
        case "BMP_OPEN":
            return !is_undefined(scr_tour_viewer_bitmap());
        case "BMP_PAINTED":
            return scr_tour_bitmap_changed(false);
        case "BMP_FILLED":
            return scr_tour_bitmap_changed(true);
        case "BMP_CLOSED":
            return !obj_asset_manager.viewer_open;
        case "HAS_BMP_NODE":
            return (scr_tour_node_by_type("MACRO_BMP") != noone);
        case "BMP_LINKED":
            _n = scr_tour_node_by_type("MACRO_BMP");
            if (_n == noone) {
                return false;
            }
            return (string(_n.instructions[0][1]) != "");
    }
    return false;
}

/// @desc GUI rect of a node (world -> GUI via the workspace camera).
function scr_tour_node_rect(_n) {
    var _wm = obj_workspace_manager;
    var _nx = _n.x + _n.x_indent;
    var _x1 = (_nx - _wm.cam_x) / _wm.cam_zoom;
    var _y1 = (_n.y - _wm.cam_y) / _wm.cam_zoom;
    var _x2 = (_nx + _n.width - _wm.cam_x) / _wm.cam_zoom;
    var _y2 = (_n.y + _n.height - _wm.cam_y) / _wm.cam_zoom;
    return [_x1, _y1, _x2, _y2];
}

/// @desc Resolve the current step's highlight. Returns [x1,y1,x2,y2] or
///       undefined when nothing is on screen.
function scr_tour_resolve_rect() {
    var _keys = global.tour_keys;
    for (var _i = 0; _i < array_length(_keys); _i++) {
        var _k = _keys[_i];

        if (global.tour_stamps[_i] == global.tour_frame) {
            return global.tour_rects[_i];
        }

        if (string_copy(_k, 1, 7) == "NODEOP:") {
            var _no = scr_tour_node_by_op(string_delete(_k, 1, 7));
            if (_no != noone) {
                return scr_tour_node_rect(_no);
            }
        }
        if (string_copy(_k, 1, 9) == "NODETYPE:") {
            var _nt = scr_tour_node_by_type(string_delete(_k, 1, 9));
            if (_nt != noone) {
                return scr_tour_node_rect(_nt);
            }
        }

        if (instance_exists(obj_asset_manager)) {
            var _am    = obj_asset_manager;
            var _right = global.gui_w - 2;
            if (_k == "ASSET:ADD" && !_am.viewer_open) {
                return [_am.panel_x + 4, _am.panel_y + 4, _right - 4, _am.panel_y + 26];
            }
            if (_k == "ASSET:PANEL" && !_am.viewer_open) {
                return [_am.panel_x, _am.panel_y + 66, _right, display_get_gui_height() - 100];
            }
            if (string_copy(_k, 1, 11) == "ASSET:TYPE:" && _am.add_dropdown_open) {
                var _want = string_delete(_k, 1, 11);
                for (var _t = 0; _t < array_length(_am.asset_types); _t++) {
                    if (_am.asset_types[_t] == _want) {
                        var _dy = _am.panel_y + 28 + (_t * 20);
                        return [_am.panel_x, _dy, _right, _dy + 20];
                    }
                }
            }
        }
    }
    return undefined;
}

/// @desc End the tour and put anything it changed back.
function scr_tour_end() {
    if (instance_exists(obj_tour_guide)) {
        instance_destroy(obj_tour_guide);
    }
}
