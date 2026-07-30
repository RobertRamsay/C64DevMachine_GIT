// =============================================================
// Version check response
// =============================================================
if (async_load[? "id"] == version_check_request)
{
    var _status = async_load[? "status"];
    var _http   = async_load[? "http_status"];
    
    // status: 0 = success, 1 = in progress, -1 = error
    if (_status == 0 && _http == 200)
    {
        var _body = async_load[? "result"];
        scr_version_check_parse(_body);
    }
    else if (_status < 0 || (_status == 0 && _http != 200))
    {
        version_check_done   = true;
        version_check_failed = true;
        version_check_request = -1;
    }
}

scr_c64u_async_http();