/// scr_discord_report.gml - one-line notes and crash reports to a Discord
/// channel webhook (same approach as SettlersGM's scr_crash).
///
/// Sends: app opened (version, edition, platform, install tag), project file
/// opened (file NAME only, never the path), and the crash written by the
/// crash handler on the previous run. Nothing identifies a person: the
/// install tag is a random 8-hex id kept in install_tag.txt.
///
/// THE WEBHOOK URL IS PUBLIC once shipped (it is in the exe). Give it a channel
/// of its own; if it gets abused, delete the webhook in Discord and paste a new one.
/// Empty URL = nothing is ever sent.
///
/// Users can switch it off in c64devmachine.ini:  [report] enabled=0

#macro REPORT_WEBHOOK_URL  "https://discord.com/api/webhooks/1555264800861331476/prZvrVsdCA5U622SVyYh4CyJU453QLv0vTHUo84-jU_3IZxVsNnGqHUUQyGuGFjUzoSx"
#macro REPORT_CRASH_FILE   "c64dm_crash_report.txt"
#macro REPORT_TAG_FILE     "install_tag.txt"
#macro REPORT_DISCORD_MAX  1800
#macro REPORT_MIN_GAP_MS   2500

/// Called once from obj_workspace_manager Create, before the crash handler is set.
function scr_report_init() {
    global.report_queue      = [];
    global.report_request    = -1;
    global.report_in_flight  = undefined;
    global.report_last_ms    = -100000;
    global.report_tag        = "";
    global.report_crashing   = false;

    ini_open("c64devmachine.ini");
    global.report_enabled = ini_read_real("report", "enabled", 1);
    ini_write_real("report", "enabled", global.report_enabled);
    ini_close();
}

/// Random id for this installation, made once and kept.
function scr_report_install_tag() {
    if (global.report_tag != "") {
        return global.report_tag;
    }
    if (file_exists(REPORT_TAG_FILE)) {
        var _f = file_text_open_read(REPORT_TAG_FILE);
        if (_f != -1) {
            global.report_tag = string_trim(file_text_read_string(_f));
            file_text_close(_f);
        }
    }
    if (global.report_tag == "") {
        randomise();
        var _hex = "0123456789ABCDEF";
        for (var _i = 0; _i < 8; _i++) {
            global.report_tag += string_char_at(_hex, irandom(15) + 1);
        }
        var _w = file_text_open_write(REPORT_TAG_FILE);
        if (_w != -1) {
            file_text_write_string(_w, global.report_tag);
            file_text_close(_w);
        }
    }
    return global.report_tag;
}

function scr_report_platform() {
    switch (os_type) {
        case os_windows: return "windows";
        case os_macosx:  return "macos";
        case os_linux:   return "linux";
        default:         return "other";
    }
}

function scr_report_edition() {
    if (global.lite) {
        return "LITE";
    }
    return "FULL";
}

/// "v1.2.3 FULL windows #A1B2C3D4"
function scr_report_who() {
    return "v" + string(GM_version) + " " + scr_report_edition() + " "
         + scr_report_platform() + " #" + scr_report_install_tag();
}

/// Queue a message. _kind "info" or "crash" (a crash file is deleted only
/// once Discord has accepted it).
function scr_report_queue(_text, _kind) {
    if (REPORT_WEBHOOK_URL == "") {
        return;
    }
    if (global.report_enabled == 0) {
        return;
    }
    array_push(global.report_queue, { text : _text, kind : _kind });
}

function scr_report_app_opened() {
    scr_report_queue("**opened** - " + scr_report_who(), "info");
}

/// From scr_load_workspace_from_path after a successful load.
function scr_report_file_opened(_fname, _mcp) {
    var _how = "";
    if (_mcp) {
        _how = " (template/tour)";
    }
    scr_report_queue("**file** " + _fname + _how + " - "
                   + string(instance_number(obj_c64_node)) + " nodes - "
                   + scr_report_who(), "info");
}

/// Called once a frame from obj_workspace_manager Step. One request at a time.
function scr_report_step() {
    if (global.report_request >= 0) {
        return;
    }
    if (array_length(global.report_queue) == 0) {
        return;
    }
    if (current_time - global.report_last_ms < REPORT_MIN_GAP_MS) {
        return;
    }

    var _msg = global.report_queue[0];
    array_delete(global.report_queue, 0, 1);

    var _body = { content : _msg.text };
    var _headers = ds_map_create();
    ds_map_add(_headers, "Content-Type", "application/json");
    ds_map_add(_headers, "Accept", "application/json");
    // Discord refuses a request with no User-Agent (400).
    ds_map_add(_headers, "User-Agent", "C64DevMachine/" + string(GM_version) + " (report)");
    global.report_request   = http_request(REPORT_WEBHOOK_URL, "POST", _headers, json_stringify(_body));
    global.report_in_flight = _msg;
    global.report_last_ms   = current_time;
    ds_map_destroy(_headers);
}

/// From obj_workspace_manager Async HTTP. True when the reply was ours.
function scr_report_async(_async) {
    if (global.report_request < 0) {
        return false;
    }
    if (_async[? "id"] != global.report_request) {
        return false;
    }
    global.report_request = -1;

    var _status = _async[? "status"];
    if (_status == 1) {
        // Still in progress - keep waiting for the final event.
        global.report_request = _async[? "id"];
        return true;
    }
    var _http = _async[? "http_status"];
    show_debug_message("report: status " + string(_status) + ", http " + string(_http));

    var _ok = false;
    if (_status == 0) {
        if (_http >= 200 && _http < 300) {
            _ok = true;
        }
    }
    if (_ok) {
        if (global.report_in_flight.kind == "crash") {
            if (file_exists(REPORT_CRASH_FILE)) {
                file_delete(REPORT_CRASH_FILE);
            }
        }
    }
    global.report_in_flight = undefined;
    return true;
}

// ------------------------------------------------------------ crashes

/// From the unhandled exception handler. Writes only - no network from a
/// dying runtime. The next launch sends it.
function scr_report_write_crash(_ex) {
    if (global.report_crashing) {
        return;
    }
    global.report_crashing = true;

    var _txt = "C64 Dev Machine crash";
    _txt += "\n" + date_datetime_string(date_current_datetime());
    try {
        _txt += "\n" + scr_report_who();
        _txt += "\nfile " + string(global.current_filename);
        _txt += "\nnodes " + string(instance_number(obj_c64_node));
    } catch (_e0) {
        _txt += "\n(state unreadable)";
    }
    _txt += "\n\n--- error ---";
    try {
        if (is_struct(_ex)) {
            _txt += "\n" + string(_ex.message);
            _txt += "\nin " + string(_ex.script) + " line " + string(_ex.line);
            _txt += "\n" + string(_ex.longMessage);
            _txt += "\n\n--- stack ---";
            var _st = _ex.stacktrace;
            for (var _i = 0; _i < array_length(_st); _i++) {
                _txt += "\n" + string(_st[_i]);
            }
        } else {
            _txt += "\n" + string(_ex);
        }
    } catch (_e1) {
        _txt += "\n(exception unreadable: " + string(_e1.message) + ")";
    }

    var _b = buffer_create(string_byte_length(_txt) + 1, buffer_fixed, 1);
    buffer_write(_b, buffer_string, _txt);
    buffer_save(_b, REPORT_CRASH_FILE);
    buffer_delete(_b);

    global.report_crashing = false;
}

/// Called once from Create after scr_report_init: queue last run's crash.
function scr_report_check_previous_crash() {
    if (!file_exists(REPORT_CRASH_FILE)) {
        return;
    }
    var _b = buffer_load(REPORT_CRASH_FILE);
    if (_b == -1) {
        return;
    }
    var _txt = buffer_read(_b, buffer_string);
    buffer_delete(_b);

    if (string_length(_txt) > REPORT_DISCORD_MAX) {
        _txt = string_copy(_txt, 1, REPORT_DISCORD_MAX) + "\n... trimmed";
    }
    // Code fence so Discord shows the stack as written.
    scr_report_queue("**CRASH** - " + scr_report_who() + "\n```\n" + _txt + "\n```", "crash");
}
