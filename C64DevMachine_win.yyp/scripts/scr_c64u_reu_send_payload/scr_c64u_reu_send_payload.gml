/// @function scr_c64u_reu_send_payload(_skip_reset)
/// @description Streams the generated REU image to the Ultimate over SocketDMA.
///              Called twice per attempt: first with no argument, which issues
///              the C64 reset and parks in the "reset_wait" state, then again
///              from scr_c64u_reu_step() with _skip_reset = true once the
///              Ultimate has had time to finish resetting and return to
///              reading its socket.
function scr_c64u_reu_send_payload(_skip_reset)
{
    var _do_reset = true;

    if (argument_count > 0)
    {
        if (_skip_reset == true)
        {
            _do_reset = false;
        }
    }

    if (_do_reset == true)
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

    // The Ultimate performs the reset on the same thread that reads this
    // socket, so it consumes nothing while the C64 restarts. Streaming the
    // image straight away fills the OS send buffer (~64K) and then stalls
    // permanently. Park here and let scr_c64u_reu_step() resume the upload.
    global.c64u_reu_state =
        "reset_wait";

    global.c64u_reu_deadline =
        current_time + 2000;

    global.c64u_reu_trace =
        "C64 reset sent, waiting for Ultimate";

    global.c64u_status =
        "C64U REU: resetting C64...";

    global.c64u_status_t = 240;

    show_debug_message(
        "C64U REU: C64 reset requested"
    );

    return true;
    }

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

    global.c64u_reu_total   = _total;
    global.c64u_reu_sent    = 0;
    global.c64u_reu_packets = 0;
    global.c64u_reu_trace   = "reset ok, starting "
                            + string(_total)
                            + " byte upload";

    var _offset    = 0;
    var _chunk_max = 8192;

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

        // network_send_raw() can accept fewer bytes than requested once the
        // OS send buffer fills. That is NOT fatal: the Ultimate blocks in
        // readSocket() until it has the full declared length, so the tail is
        // simply pushed as a continuation of the same command.
        var _packet_size = 7 + _chunk;
        var _sent_total  = 0;
        var _sent        = 0;

        // Wall-clock budget, not an iteration count. The kernel transmits
        // independently of this loop, so we keep offering the tail until the
        // Ultimate opens its receive window again. The old counter expired in
        // about a millisecond, long before the Ultimate could respond.
        var _wait_until = current_time + 10000;

        while (_sent_total < _packet_size)
        {
            var _remain = _packet_size - _sent_total;
            var _out    = buffer_create(_remain, buffer_fixed, 1);
            buffer_copy(_packet, _sent_total, _remain, _out, 0);

            var _pushed = network_send_raw(
                global.c64u_reu_socket,
                _out,
                _remain
            );

            buffer_delete(_out);

            if (_pushed > 0)
            {
                _sent_total += _pushed;
                _wait_until = current_time + 10000;
            }
            else
            {
                if (current_time > _wait_until)
                {
                    break;
                }
            }
        }

        if (_sent_total != _packet_size)
        {
            global.c64u_reu_trace =
                "short write at REU $"
                + string_upper(decimal_to_hex(_offset))
                + " ("
                + string(_sent_total)
                + " of "
                + string(_packet_size)
                + " bytes)";

            show_debug_message(
                "C64U REU: " + global.c64u_reu_trace
            );
        }

        _sent = _sent_total;

        buffer_delete(_packet);

        if (_sent != _packet_size)
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

        global.c64u_reu_sent    += _chunk;
        global.c64u_reu_packets += 1;

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

    global.c64u_reu_trace =
        "all "
        + string(_total)
        + " bytes written in "
        + string(global.c64u_reu_packets)
        + " packets, awaiting IDENTIFY";

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