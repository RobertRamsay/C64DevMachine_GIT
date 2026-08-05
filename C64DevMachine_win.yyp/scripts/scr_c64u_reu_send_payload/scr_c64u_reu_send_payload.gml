function scr_c64u_reu_send_payload()
{
    // Reset the C64 core before changing REU contents.
    // SocketDMA command $FF04, zero-length payload.
    var _reset_packet = buffer_create(
        4,
        buffer_fixed,
        1
    );

    buffer_poke(
        _reset_packet,
        0,
        buffer_u8,
        0x04
    );

    buffer_poke(
        _reset_packet,
        1,
        buffer_u8,
        0xFF
    );

    buffer_poke(
        _reset_packet,
        2,
        buffer_u8,
        0x00
    );

    buffer_poke(
        _reset_packet,
        3,
        buffer_u8,
        0x00
    );

    var _reset_sent = network_send_raw(
        global.c64u_reu_socket,
        _reset_packet,
        4
    );

    buffer_delete(_reset_packet);

    if (_reset_sent != 4)
    {
        global.c64u_reu_state =
            "retry";

        global.c64u_reu_deadline =
            current_time;

        global.c64u_status =
            "C64U REU: reset failed, retrying...";

        return false;
    }

    show_debug_message(
        "C64U REU: C64 reset requested"
    );

    var _image = buffer_load(global.reu_last_image);

    if (_image < 0) {
        return scr_c64u_reu_fail(
            "could not open generated image"
        );
    }

    var _total = min(
        buffer_get_size(_image),
        max(0x100, real(global.reu_last_used))
    );

    var _offset    = 0;
    var _chunk_max = 60000;

    while (_offset < _total)
    {
        var _chunk = min(
            _chunk_max,
            _total - _offset
        );

        // Ultimate SocketDMA:
        // command $FF07, payload length,
        // 24-bit REU address, then data.
        var _packet = buffer_create(
            7 + _chunk,
            buffer_fixed,
            1
        );

        buffer_poke(_packet, 0, buffer_u8, 0x07);
        buffer_poke(_packet, 1, buffer_u8, 0xFF);

        buffer_poke(
            _packet,
            2,
            buffer_u8,
            (_chunk + 3) & 0xFF
        );

        buffer_poke(
            _packet,
            3,
            buffer_u8,
            ((_chunk + 3) >> 8) & 0xFF
        );

        buffer_poke(
            _packet,
            4,
            buffer_u8,
            _offset & 0xFF
        );

        buffer_poke(
            _packet,
            5,
            buffer_u8,
            (_offset >> 8) & 0xFF
        );

        buffer_poke(
            _packet,
            6,
            buffer_u8,
            (_offset >> 16) & 0xFF
        );

        buffer_copy(
            _image,
            _offset,
            _chunk,
            _packet,
            7
        );

        var _sent = network_send_raw(
            global.c64u_reu_socket,
            _packet,
            7 + _chunk
        );

        buffer_delete(_packet);

        if (_sent != 7 + _chunk)
        {
            buffer_delete(_image);

            global.c64u_reu_state =
                "retry";

            global.c64u_reu_deadline =
                current_time;

            global.c64u_status =
                "C64U REU: write interrupted, retrying...";

            return false;
        }

        _offset += _chunk;
    }

    buffer_delete(_image);

    // REUWRITE has no acknowledgement.
    // IDENTIFY is sent as a completion barrier.
    var _confirm = buffer_create(
        4,
        buffer_fixed,
        1
    );

    buffer_poke(_confirm, 0, buffer_u8, 0x0E);
    buffer_poke(_confirm, 1, buffer_u8, 0xFF);
    buffer_poke(_confirm, 2, buffer_u8, 0x00);
    buffer_poke(_confirm, 3, buffer_u8, 0x00);

    var _confirm_sent = network_send_raw(
        global.c64u_reu_socket,
        _confirm,
        4
    );

    buffer_delete(_confirm);

    if (_confirm_sent != 4)
    {
        global.c64u_reu_state =
            "retry";

        global.c64u_reu_deadline =
            current_time;

        global.c64u_status =
            "C64U REU: confirmation failed, retrying...";

        return false;
    }

    global.c64u_reu_state =
        "confirm";

    global.c64u_reu_deadline =
        current_time + 15000;

    global.c64u_status =
        "C64U REU: verifying "
        + string(_total)
        + " bytes...";

    global.c64u_status_t = 600;

    show_debug_message(
        "C64U REU: sent "
        + string(_total)
        + " bytes, waiting for Ultimate confirmation"
    );

    return true;
}