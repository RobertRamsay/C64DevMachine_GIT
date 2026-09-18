// Native asynchronous text input. Clear first so a callback can open another prompt.
if (!variable_global_exists("text_prompt") || !is_struct(global.text_prompt)) exit;
var _prompt = global.text_prompt;
if (async_load[? "id"] != _prompt.request) exit;
global.text_prompt = undefined;
io_clear();
if (!instance_exists(_prompt.owner)) exit;
var _result = async_load[? "status"] ? string(async_load[? "result"]) : "";
script_execute_ext(_prompt.callback, [_result, _prompt.context]);
