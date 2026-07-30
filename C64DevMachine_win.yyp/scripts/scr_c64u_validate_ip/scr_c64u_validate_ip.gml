/// @function scr_c64u_validate_ip(ip_string)
/// @description Validates a dotted-quad IPv4 string. Returns true on pass.
/// @param {String} ip_string  Candidate IP, e.g. "192.168.1.64"
function scr_c64u_validate_ip(ip_string)
{
    var _trimmed = string_trim(ip_string);
    if (string_length(_trimmed) < 7)
    {
        return false;
    }

    var _parts      = string_split(_trimmed, ".");
    var _part_count = array_length(_parts);

    if (_part_count != 4)
    {
        return false;
    }

    var _i = 0;
    repeat (4)
    {
        var _seg = _parts[_i];
        var _seg_len = string_length(_seg);

        if (_seg_len < 1 || _seg_len > 3)
        {
            return false;
        }

        // All characters must be digits
        var _j = 1;
        repeat (_seg_len)
        {
            var _ch = string_char_at(_seg, _j);
            if (_ch < "0" || _ch > "9")
            {
                return false;
            }
            _j += 1;
        }

        var _val = real(_seg);
        if (_val < 0 || _val > 255)
        {
            return false;
        }

        _i += 1;
    }

    return true;
}