/// Deferred bitmap-preview queue.
///
/// Decoding one bitmap into a 320x200 preview costs 64000 pixel writes, a
/// 64000-entry mask and a surface upload. A project holding a 60-frame REU
/// animation therefore pays that 60 times before the workspace can draw its
/// first frame, which is why a sub-1MB .json can take many seconds to open:
/// the file is small, but it describes a lot of pictures to rebuild.
///
/// Nothing about that work has to happen before the workspace appears. The
/// loader pushes each bitmap here instead of decoding it inline, the queue
/// drains under a per-frame time budget, and the user watches a bar instead
/// of a frozen window. Assets whose turn has not come yet simply have no
/// preview surface for a few frames, which every consumer already handles -
/// surfaces are volatile on this platform and are re-checked before use.

function scr_bmp_preview_queue_reset() {
    global.bmp_preview_queue = [];
    global.bmp_preview_done  = 0;
    global.bmp_preview_total = 0;
}

function scr_bmp_preview_queue_push(_asset) {
    array_push(global.bmp_preview_queue, _asset);
    global.bmp_preview_total = global.bmp_preview_total + 1;
}

function scr_bmp_preview_queue_active() {
    return array_length(global.bmp_preview_queue) > 0;
}

/// Build as many queued previews as fit in _budget_ms of this frame. The
/// budget is wall-clock rather than a fixed count because bitmaps are not
/// all equal - a HiRes asset also seeds three role arrays - and because a
/// fixed count either stutters on a slow machine or crawls on a fast one.
function scr_bmp_preview_queue_drain(_budget_ms) {
    if (array_length(global.bmp_preview_queue) == 0) {
        return;
    }

    var _deadline = current_time + _budget_ms;

    while (array_length(global.bmp_preview_queue) > 0) {
        var _asset = global.bmp_preview_queue[0];
        array_delete(global.bmp_preview_queue, 0, 1);
        global.bmp_preview_done = global.bmp_preview_done + 1;

        if (is_struct(_asset) && buffer_exists(_asset.buffer)) {
            scr_asset_bmp_build_preview(_asset);
        }

        if (current_time >= _deadline) {
            break;
        }
    }

    if (array_length(global.bmp_preview_queue) == 0) {
        global.bmp_preview_done  = 0;
        global.bmp_preview_total = 0;
    }
}

/// Drawn from the Draw GUI event, above everything, while the queue has
/// work left. Deliberately drawn before the hideui bail-out so a project
/// that opens with the UI hidden still shows that something is happening.
function scr_bmp_preview_queue_draw() {
    if (array_length(global.bmp_preview_queue) == 0) {
        return;
    }
    if (global.bmp_preview_total <= 0) {
        return;
    }

    var _gw = global.gui_w;
    var _gh = display_get_gui_height();

    var _bw = min(420, _gw - 80);
    var _bh = 22;
    var _bx = (_gw - _bw) / 2;
    var _by = _gh - 96;

    var _frac = global.bmp_preview_done / global.bmp_preview_total;
    _frac = clamp(_frac, 0, 1);

    draw_set_alpha(0.88);
    draw_set_color(make_color_rgb(18, 18, 22));
    draw_rectangle(_bx - 12, _by - 30, _bx + _bw + 12, _by + _bh + 12, false);
    draw_set_alpha(1);

    draw_set_color(make_color_rgb(70, 70, 80));
    draw_rectangle(_bx, _by, _bx + _bw, _by + _bh, true);

    draw_set_color(make_color_rgb(80, 180, 240));
    draw_rectangle(_bx + 1, _by + 1, _bx + 1 + (_bw - 2) * _frac, _by + _bh - 1, false);

    draw_set_color(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_text_l(_bx, _by - 24, L("REBUILDING BITMAP PREVIEWS")
        + "  " + string(global.bmp_preview_done)
        + " / " + string(global.bmp_preview_total));
}
