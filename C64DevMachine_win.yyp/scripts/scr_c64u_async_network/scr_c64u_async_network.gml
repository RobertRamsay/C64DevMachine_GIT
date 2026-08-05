function scr_c64u_async_network()
{
    if (global.c64u_reu_state == "idle") {
        return false;
    }

    if (async_load[? "id"] !=
        global.c64u_reu_socket) {
        return false;
    }

    var _type = async_load[? "type"];

    if (_type ==
        network_type_non_blocking_connect)
    {
        if (async_load[? "succeeded"] != 1)
        {
            global.c64u_reu_state =
                "retry";

            global.c64u_reu_deadline =
                current_time;

            return false;
        }

        if (global.c64u_password != "") {
            return scr_c64u_reu_send_auth();
        }

        return scr_c64u_reu_send_payload();
    }

    if (_type == network_type_data &&
        global.c64u_reu_state == "auth")
    {
        var _buf  = async_load[? "buffer"];
        var _size = async_load[? "size"];

        if (_size < 1 ||
            buffer_peek(
                _buf,
                0,
                buffer_u8
            ) != 1)
        {
            return scr_c64u_reu_fail(
                "DMA password rejected"
            );
        }

        return scr_c64u_reu_send_payload();
    }

    if (_type == network_type_data &&
        global.c64u_reu_state == "confirm")
    {
        if (async_load[? "size"] < 1)
        {
            global.c64u_reu_state =
                "retry";

            global.c64u_reu_deadline =
                current_time;

            return false;
        }

        global.c64u_reu_state =
            "settle";

        global.c64u_reu_deadline =
            current_time + 750;

        global.c64u_status =
            "C64U REU: upload confirmed";

        global.c64u_status_t = 240;

        show_debug_message(
            "C64U REU: Ultimate confirmed upload on attempt "
            + string(global.c64u_reu_attempt)
        );

        return true;
    }

    if (_type == network_type_disconnect)
    {
        global.c64u_reu_state =
            "retry";

        global.c64u_reu_deadline =
            current_time;

        return false;
    }

    return true;
}