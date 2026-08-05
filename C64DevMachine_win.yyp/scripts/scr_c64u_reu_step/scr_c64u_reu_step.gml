function scr_c64u_reu_step()
{
    if (global.c64u_reu_state == "idle") {
        return;
    }

    if (current_time <
        global.c64u_reu_deadline) {
        return;
    }

    if (global.c64u_reu_state == "settle")
    {
        scr_c64u_reu_continue();
        return;
    }

    if (global.c64u_reu_attempt <
        global.c64u_reu_max_attempts)
    {
        if (global.c64u_reu_socket >= 0) {
            network_destroy(
                global.c64u_reu_socket
            );
        }

        global.c64u_reu_socket = -1;
        global.c64u_reu_attempt += 1;

        var _socket = network_create_socket(
            network_socket_tcp
        );

        if (_socket < 0)
        {
            scr_c64u_reu_fail(
                "could not recreate TCP socket"
            );

            return;
        }

        global.c64u_reu_socket =
            _socket;

        global.c64u_reu_state =
            "connecting";

        global.c64u_reu_deadline =
            current_time + 15000;

        global.c64u_busy = true;

        global.c64u_status =
            "C64U REU: retry "
            + string(global.c64u_reu_attempt)
            + "/"
            + string(global.c64u_reu_max_attempts);

        global.c64u_status_t = 600;

        show_debug_message(
            global.c64u_status
        );

        var _result =
            network_connect_raw_async(
                _socket,
                global.c64u_ip,
                64
            );

        if (_result < 0)
        {
            global.c64u_reu_state =
                "retry";

            global.c64u_reu_deadline =
                current_time + 500;
        }

        return;
    }

    scr_c64u_reu_fail(
        "DMA upload failed after "
        + string(global.c64u_reu_max_attempts)
        + " attempts"
    );
}