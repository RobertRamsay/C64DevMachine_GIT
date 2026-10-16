// =============================================================
// COMMENT ARROWS
// Every expanded COMMENT has three yellow handles on its bottom edge (left,
// middle, right). Drag from one and drop anywhere: an arrow then runs from
// that handle to the drop point, a fixed spot in the workspace. The handle
// end follows the comment when it moves; the point end never does. Dropping
// back on the handle removes its arrow.
//
// comment_arrows on the node is three [on, target_x, target_y] entries, one
// per handle. Nothing here touches the spine, so a comment can point at code
// without being wired into it.
//
// Hidden while the comment is folded, while comments are hidden (F3), and
// when OPTIONS > COMMENT ARROWS is OFF.
// =============================================================

#macro COMMENT_ARROW_R     5     // handle radius, world px
#macro COMMENT_ARROW_HIT   9     // handle grab radius, world px
#macro COMMENT_ARROW_COL   make_color_rgb(255, 214, 40)

function scr_comment_arrows_init() {
    global.comment_arrow_drag_node = noone;
    global.comment_arrow_drag_idx  = -1;
    global.comment_arrow_hot       = false;
}

/// Fresh empty arrow set: three handles, none pointing anywhere.
function scr_comment_arrows_empty() {
    return [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
}

/// A clean three-entry copy of a saved / snapshotted arrow set. Anything
/// malformed (old projects, hand-edited files) comes back as empty handles.
function scr_comment_arrows_sanitize(_src) {
    var _out = scr_comment_arrows_empty();
    if (!is_array(_src)) return _out;
    for (var _i = 0; _i < min(3, array_length(_src)); _i++) {
        var _e = _src[_i];
        if (!is_array(_e) || array_length(_e) < 3) continue;
        if (!is_numeric(_e[1]) || !is_numeric(_e[2])) continue;
        var _on = 0;
        if (_e[0] == true || _e[0] == 1) _on = 1;
        _out[_i] = [_on, _e[1], _e[2]];
    }
    return _out;
}

/// Handle centre in world space: on the bottom edge, left / middle / right.
/// The right one sits clear of the resize corner.
function scr_comment_arrow_handle_x(_n, _i) {
    var _x1 = _n.x + _n.x_indent;
    if (_i == 0) return _x1 + 14;
    if (_i == 1) return _x1 + round(_n.width / 2);
    return _x1 + _n.width - 30;
}

function scr_comment_arrow_handle_y(_n) {
    return _n.y + _n.height;
}

/// Whether this node's handles and arrows are shown at all.
function scr_comment_arrows_live(_n) {
    if (_n.node_type != "COMMENT") return false;
    if (!global.comments_visible || !global.comment_arrows_on) return false;
    if (_n.collapsed) return false;
    if (scr_node_is_hidden(_n)) return false;
    return true;
}

/// Sets (or with _on false, clears) one arrow. Builds a new array rather than
/// writing into the old one, so a copied node never shares its arrows.
function scr_comment_arrow_set(_n, _i, _on, _tx, _ty) {
    var _a = scr_comment_arrows_sanitize(_n.comment_arrows);
    _a[_i] = [_on ? 1 : 0, round(_tx), round(_ty)];
    _n.comment_arrows = _a;
}

// --------------------------------------------------------------------
// BEGIN STEP - grab and drop. Runs before any node Step, so a press on a
// handle never also starts a node drag or a caret click.
// --------------------------------------------------------------------
function scr_comment_arrows_begin_step() {
    global.comment_arrow_hot = false;

    // A drag in progress: follow the pointer until release, then commit.
    var _dn = global.comment_arrow_drag_node;
    if (_dn != noone) {
        if (!instance_exists(_dn) || !scr_comment_arrows_live(_dn)) {
            global.comment_arrow_drag_node = noone;
            global.comment_arrow_drag_idx  = -1;
            exit;
        }
        global.comment_arrow_hot = true;
        global.drag_claim_taken  = true;
        if (!mouse_check_button(mb_left)) {
            var _i  = global.comment_arrow_drag_idx;
            var _hx = scr_comment_arrow_handle_x(_dn, _i);
            var _hy = scr_comment_arrow_handle_y(_dn);
            // Let go on (or right next to) the handle: no arrow.
            var _on = point_distance(_hx, _hy, mouse_x, mouse_y) > COMMENT_ARROW_HIT * 2;
            scr_comment_arrow_set(_dn, _i, _on, mouse_x, mouse_y);
            global.comment_arrow_drag_node = noone;
            global.comment_arrow_drag_idx  = -1;
            global.undo_dirty     = true;
            global.autosave_dirty = true;
        }
        exit;
    }

    if (!global.comments_visible || !global.comment_arrows_on) exit;
    if (!instance_exists(obj_workspace_manager)) exit;
    if (scr_workspace_input_blocked())             exit;
    if (!global.canEditNode)                       exit;
    if (global.mcp_turn_lock)                      exit;
    if (global.gui_mouse_y < 50)                   exit;
    if (global.showcode_mouse_over)                exit;
    if (global.any_picker_open)                    exit;
    if (global.creator_card_hot)                   exit;
    if (global.creator_tab_hot != noone)           exit;
    if (global.org_collapse_hot != noone)          exit;
    if (obj_workspace_manager.gui_menu_open != -1) exit;
    if (obj_workspace_manager.code_editor_open)    exit;
    if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) exit;
    if (variable_global_exists("mouse_in_asset_panel") && global.mouse_in_asset_panel) exit;
    if (!scr_workspace_mouse_check_button_pressed(mb_left)) exit;

    // Front-most comment wins where handles overlap.
    var _best   = noone;
    var _best_i = -1;
    var _mx = mouse_x;
    var _my = mouse_y;
    with (obj_c64_node) {
        if (!scr_comment_arrows_live(id)) continue;
        // Being typed into: the bottom edge belongs to the caret.
        if (obj_workspace_manager.is_entering_text && obj_workspace_manager.input_target_node == id) continue;
        if (_best != noone && depth >= _best.depth) continue;
        var _hy = scr_comment_arrow_handle_y(id);
        for (var _i = 0; _i < 3; _i++) {
            if (point_distance(_mx, _my, scr_comment_arrow_handle_x(id, _i), _hy) <= COMMENT_ARROW_HIT) {
                _best   = id;
                _best_i = _i;
                break;
            }
        }
    }
    if (_best == noone) exit;

    scr_undo_snapshot();
    global.comment_arrow_drag_node = _best;
    global.comment_arrow_drag_idx  = _best_i;
    global.comment_arrow_hot       = true;
    global.drag_claim_taken        = true;
    global.ui_click_consumed       = true;
}

// --------------------------------------------------------------------
// DRAW (world space, Draw End) - over every node, so an arrow is never
// hidden under the code it points at, and never clipped by a node's cached
// image.
// --------------------------------------------------------------------
function scr_comment_arrow_draw_one(_x1, _y1, _x2, _y2, _z, _alpha) {
    var _len = point_distance(_x1, _y1, _x2, _y2);
    if (_len < 1) return;
    var _dir  = point_direction(_x1, _y1, _x2, _y2);
    var _lw   = max(2, 2 * _z);
    var _head = min(_len, max(12, 10 * _z));
    var _hw   = _head * 0.5;
    // The line stops at the back of the head so its end is not drawn over it.
    var _bx = _x2 - lengthdir_x(_head, _dir);
    var _by = _y2 - lengthdir_y(_head, _dir);
    var _lx = lengthdir_x(_hw, _dir + 90);
    var _ly = lengthdir_y(_hw, _dir + 90);

    // Dark under-stroke so the arrow reads on any background.
    draw_set_alpha(_alpha * 0.6);
    draw_set_color(c_black);
    draw_line_width(_x1, _y1, _bx, _by, _lw + 2 * _z);
    draw_triangle(_x2 + lengthdir_x(_z, _dir), _y2 + lengthdir_y(_z, _dir),
                  _bx + _lx * 1.25, _by + _ly * 1.25, _bx - _lx * 1.25, _by - _ly * 1.25, false);

    draw_set_alpha(_alpha);
    draw_set_color(COMMENT_ARROW_COL);
    draw_line_width(_x1, _y1, _bx, _by, _lw);
    draw_triangle(_x2, _y2, _bx + _lx, _by + _ly, _bx - _lx, _by - _ly, false);
}

function scr_comment_arrows_draw() {
    if (!global.comments_visible || !global.comment_arrows_on) exit;
    if (!instance_exists(obj_workspace_manager)) exit;
    if (obj_workspace_manager.code_editor_open) exit;
    if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) exit;

    var _z  = obj_workspace_manager.cam_zoom;
    // Zoomed out the map shows names only - no arrows.
    if (_z >= 2.0) exit;
    var _vx1 = obj_workspace_manager.cam_x - 200;
    var _vy1 = obj_workspace_manager.cam_y - 200;
    var _vx2 = obj_workspace_manager.cam_x + 1920 * _z + 200;
    var _vy2 = obj_workspace_manager.cam_y + 1080 * _z + 200;
    var _dn  = global.comment_arrow_drag_node;
    var _di  = global.comment_arrow_drag_idx;
    var _show_handles = (_z < 3.5);
    var _mx = mouse_x;
    var _my = mouse_y;

    with (obj_c64_node) {
        if (!scr_comment_arrows_live(id)) continue;
        var _arr = comment_arrows;
        var _hy  = scr_comment_arrow_handle_y(id);
        var _ok_arr = is_array(_arr) && array_length(_arr) >= 3;
        var _editing = obj_workspace_manager.is_entering_text && obj_workspace_manager.input_target_node == id;

        for (var _i = 0; _i < 3; _i++) {
            var _hx = scr_comment_arrow_handle_x(id, _i);
            var _dragging = (_dn == id && _di == _i);
            var _on = false;
            var _tx = 0;
            var _ty = 0;
            if (_dragging) {
                _on = true;
                _tx = _mx;
                _ty = _my;
            } else if (_ok_arr && is_array(_arr[_i]) && array_length(_arr[_i]) >= 3 && _arr[_i][0]) {
                _on = true;
                _tx = _arr[_i][1];
                _ty = _arr[_i][2];
            }

            if (_on && !(max(_hx, _tx) < _vx1 || min(_hx, _tx) > _vx2
                      || max(_hy, _ty) < _vy1 || min(_hy, _ty) > _vy2)) {
                scr_comment_arrow_draw_one(_hx, _hy, _tx, _ty, _z, _dragging ? 1.0 : 0.9);
            }

            if (!_show_handles || _editing) continue;
            if (_hx < _vx1 || _hx > _vx2 || _hy < _vy1 || _hy > _vy2) continue;
            var _hov = point_distance(_mx, _my, _hx, _hy) <= COMMENT_ARROW_HIT;
            var _r   = COMMENT_ARROW_R + ((_hov || _dragging) ? 1.5 : 0);
            draw_set_alpha(1.0);
            draw_set_color(c_black);
            draw_circle(_hx, _hy, _r + 1.5, false);
            draw_set_color(COMMENT_ARROW_COL);
            if (!_on && !_hov) draw_set_alpha(0.6);
            draw_circle(_hx, _hy, _r, false);
            if (_hov || _dragging) {
                draw_set_alpha(1.0);
                draw_set_color(c_white);
                draw_circle(_hx, _hy, _r + 1.5, true);
            }
        }
    }
    draw_set_alpha(1.0);
    draw_set_color(c_white);
}
