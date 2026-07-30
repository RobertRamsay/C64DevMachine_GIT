/// @function scr_c64u_overlay_step()
/// @description Per-frame input for the IP entry overlay. Handles ESC, ENTER,
///              typing, mouse clicks on Cancel/Save buttons. ENTER triggers a
///              ping; the IP is only saved when the ping succeeds.
function scr_c64u_overlay_step()
{
    if (global.c64u_overlay_active == false)
    {
        return;
    }

    // --- ESC = cancel (full reset) ---
    if (keyboard_check_pressed(vk_escape) == true)
    {
        global.c64u_overlay_active = false;
		obj_workspace_manager.alarm[6]=10; // reset the use of nodes
		
        global.c64u_overlay_text   = "";
        global.c64u_overlay_error  = "";
        global.c64u_overlay_after  = "";
        keyboard_clear(vk_escape);
        keyboard_string = "";

        // Also discard any in-flight ping
        global.c64u_ping_id        = -1;
        global.c64u_ping_candidate = "";
        global.c64u_ping_after     = "";
        // Note: leave c64u_busy alone — async handler will clean up if a request comes back

        global.c64u_status   = "C64U: cancelled";
        global.c64u_status_t = 120;
        return;
    }

    // --- Mouse click handling for Cancel / Save buttons ---
    if (mouse_check_button_pressed(mb_left) == true)
    {
        var _mx = global.gui_mouse_x;
        var _my = global.gui_mouse_y;

        // Cancel button
        if (_mx >= global.c64u_cancel_x1 && _mx <= global.c64u_cancel_x2
            && _my >= global.c64u_cancel_y1 && _my <= global.c64u_cancel_y2)
        {
            global.c64u_overlay_active = false;
            global.c64u_overlay_text   = "";
            global.c64u_overlay_error  = "";
            global.c64u_overlay_after  = "";
            global.c64u_ping_id        = -1;
            global.c64u_ping_candidate = "";
            global.c64u_ping_after     = "";
            global.c64u_status   = "C64U: cancelled";
            global.c64u_status_t = 120;
			obj_workspace_manager.alarm[6]=20; // reset the use of nodes
            return;
        }

        // Save button
        if (_mx >= global.c64u_save_x1 && _mx <= global.c64u_save_x2
            && _my >= global.c64u_save_y1 && _my <= global.c64u_save_y2)
        {
            scr_c64u_overlay_try_confirm();
            return;
        }
    }

    // --- ENTER = try to confirm ---
    if (keyboard_check_pressed(vk_enter) == true)
    {
        scr_c64u_overlay_try_confirm();
        keyboard_clear(vk_enter);
        keyboard_string = "";
        return;
    }

    // --- BACKSPACE ---
    if (keyboard_check_pressed(vk_backspace) == true)
    {
        var _len = string_length(global.c64u_overlay_text);
        if (_len > 0)
        {
            global.c64u_overlay_text = string_copy(global.c64u_overlay_text, 1, _len - 1);
            global.c64u_overlay_error = ""; // clear stale error on edit
        }
        keyboard_clear(vk_backspace);
        keyboard_string = "";
        return;
    }

    // --- Character input: digits and dot only, max 15 chars ---
    if (keyboard_string != "")
    {
        var _in  = keyboard_string;
        var _len = string_length(_in);
        var _i   = 1;
        var _changed = false;
        repeat (_len)
        {
            var _ch = string_char_at(_in, _i);
            var _ok = false;

            if (_ch >= "0" && _ch <= "9")
            {
                _ok = true;
            }
            if (_ch == ".")
            {
                _ok = true;
            }

            if (_ok == true)
            {
                if (string_length(global.c64u_overlay_text) < 15)
                {
                    global.c64u_overlay_text += _ch;
                    _changed = true;
                }
            }

            _i += 1;
        }
        keyboard_string = "";

        if (_changed == true)
        {
            global.c64u_overlay_error = ""; // clear stale error on edit
        }
    }
}
