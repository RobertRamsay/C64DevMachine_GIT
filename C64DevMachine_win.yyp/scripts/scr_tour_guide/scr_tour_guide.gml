/// scr_tour_guide - Guided tours (DOCUMENTS > GUIDED TOURS).
///
/// A tour is an array of steps. Each step has a title, body text, a list of
/// highlight targets (first one found on screen wins) and a check code that
/// auto-advances the tour when the user has done the thing.
///
/// Highlight targets:
///   PAL:<title>         opcode palette button   (captured by workspace Draw GUI)
///   ARROW:L / ARROW:R   palette page arrows     (captured)
///   MENU:<n>            menu bar button n       (captured)
///   MAC:<type>          MACROS dropdown row     (captured)
///   NODEOP:<op>         first connected NORMAL node using that opcode
///   NODETYPE:<type>     first connected node of that type
///   OPERAND0:<op>       operand of a connected NORMAL node still at 0 (captured)
///   FIELD:<type>:<name> one editable field on a macro node        (captured)
///   ASSET:ADD           [ADD ASSET +] button
///   ASSET:TYPE:<type>   row in the add-asset dropdown (only while open)
///   ASSET:PANEL         the asset list
///   ASSET:CLOSE         CLOSE button on any asset viewer            (captured)
///   UI:<label>          right-hand shortcut button, e.g. UI:BUILD & RUN (captured)
///   ASSET:SPR_EDIT      EDIT SPRITES button in a SPRITE_SET viewer      (captured)
///   ASSET:MUS_GEN       GENERATE NODES button in the Music Maker        (captured)
///   FIELD:MACRO_JOY:<d> a direction cell on a JOYSTICK node, e.g. LF    (captured)
///   FIELD:<keys>:<k>    a key cell on a KEYS node, e.g. FIELD:MACRO_LETTERS:B
///   LABELNAME:<name>    LABEL node with that name, attached or not
///   LASTTYPE:<type>     lowest attached node of that type
///   FREELABEL           first LABEL not yet attached to anything
///
/// Captured targets are written by scr_tour_capture() from the existing draw
/// loops, so the highlight always sits exactly on what was drawn this frame.

/// @desc Ask to start tour _id. A tour needs a clean workspace, so if the
///       workspace differs from the one the app started with, the user is
///       asked (and offered a save) before it is cleared with a restart.
function scr_tour_request(_id) {
    if (scr_tour_is_default()) {
        scr_tour_start(_id);
        return;
    }
    global.tour_waiting = _id;
    if (scr_workspace_has_changes()) {
        scr_show_question("Starting a tour clears the workspace.\n\nSave your changes first?", "tour_save");
    } else {
        scr_show_question("Starting a tour clears the workspace.\nYour saved project is not changed.\n\nClear it and start the tour?", "tour_clear");
    }
}

/// @desc True when the workspace still matches the startup default.
function scr_tour_is_default() {
    if (global.tour_default_hash == "") {
        return false;
    }
    return (scr_save_workspace_as_path("", true) == global.tour_default_hash);
}

/// @desc Clear the workspace the same way PROJECT > RESET/CLEAR does, and
///       have the fresh session start tour _id once it has settled.
function scr_tour_restart_into(_id) {
    ini_open("c64devmachine.ini");
    ini_write_real("Tour", "pending", _id);
    ini_close();
    game_restart();
}

/// @desc Answers to the tour clear / save questions. Called every Step.
function scr_tour_question_step() {
    var _r = global.question_result;
    if (_r == "tour_save_yes") {
        global.question_result = "";
        var _default = "my_project.json";
        if (global.workspace_path != "") {
            _default = filename_name(global.workspace_path);
        }
        var _path = get_save_filename("C64 Node Project|*.json", _default);
        io_clear();
        if (_path == "") {
            global.tour_waiting = -1;
            return;
        }
        scr_save_workspace_as_path(_path);
        // Only clear once the save is confirmed on disk.
        var _verified = false;
        if (file_exists(_path)) {
            var _saved = buffer_load(_path);
            if (_saved != -1) {
                _verified = (md5_string_utf8(buffer_read(_saved, buffer_text)) == global.saved_hash);
                buffer_delete(_saved);
            }
        }
        if (_verified) {
            scr_tour_restart_into(global.tour_waiting);
        } else {
            global.tour_waiting = -1;
            scr_show_message("The save could not be verified. Your current project has been kept.");
        }
        return;
    }
    if (_r == "tour_save_no") {
        global.question_result = "";
        scr_show_question("Discard your changes and start the tour?\nNO keeps your current project.", "tour_discard");
        return;
    }
    if (_r == "tour_discard_yes" || _r == "tour_clear_yes") {
        global.question_result = "";
        scr_tour_restart_into(global.tour_waiting);
        return;
    }
    if (_r == "tour_discard_no" || _r == "tour_clear_no") {
        global.question_result = "";
        global.tour_waiting = -1;
        return;
    }
}

/// @desc Start (or restart) tour _id on the current workspace.
function scr_tour_start(_id) {
    if (instance_exists(obj_tour_guide)) {
        instance_destroy(obj_tour_guide);
    }
    // Depth doubles as the draw z. GameMaker clips anything at or beyond
    // +/-16000, so -16000 drew nothing at all. -14000 keeps it above the
    // colour pickers (-9999) and inside the visible range.
    // Tours that build on earlier ones start from a ready-made workspace.
    // Done before the tour object exists so its step baselines see it.
    scr_tour_setup(_id);
    var _t = instance_create_depth(0, 0, -14000, obj_tour_guide);
    with (_t) {
        tour_id    = _id;
        tour_title = scr_tour_title(_id);
        steps      = scr_tour_define(_id);
        step_idx   = 0;

        // The palette is hidden in expert mode; show it for the tour and put
        // the user's setting back when the tour ends.
        if (obj_workspace_manager.expert_mode) {
            obj_workspace_manager.expert_mode = false;
            restore_expert = true;
        }
        // The floating SHOW CODE panel can sit over the opcode palette the
        // tour points at. Hide it for the tour and restore it afterwards.
        if (obj_workspace_manager.showcode_enabled) {
            obj_workspace_manager.showcode_enabled = false;
            restore_showcode = true;
        }
        scr_tour_enter_step();
    }
    global.tour_active = true;
}

/// @desc Tour names, shown in the caption header.
function scr_tour_title(_id) {
    var _list = scr_tour_list();
    if (_id >= 0 && _id < array_length(_list)) {
        return _list[_id].title;
    }
    return "TOUR";
}

/// @desc Every tour, in menu order. Index = tour id used by scr_tour_define.
///       Add new tours here and give them a matching block in scr_tour_define.
function scr_tour_list() {
    return [
        { title: "BORDER & BACKGROUND", blurb: "Drag in opcodes and set the border and background colours." },
        { title: "YOUR FIRST MACRO",    blurb: "Drag in the PRINT macro and put a message on screen." },
        { title: "BITMAP BASICS",       blurb: "Paint a bitmap asset and show it with the BITMAP macro." },
        { title: "YOUR FIRST SPRITE",   blurb: "Draw a sprite and put it on screen with the SPRITE macro." },
        { title: "THE GAME LOOP",       blurb: "Build a MAIN loop with VWAIT, RANDOM and JMP to flash the border." },
        { title: "JOYSTICK CONTROL",    blurb: "Fly a ship left and right with the JOYSTICK and MOVE macros." },
        { title: "KEYBOARD INPUT",      blurb: "Use KEYS A-Z so a key press changes the border colour." },
        { title: "SCROLLING TEXT",      blurb: "Clear the screen and run a scrolling message with TXT SCROLL." },
        { title: "SPRITE COLLISION",    blurb: "Flash the border when two ships touch, using COLLIDE." },
        { title: "MAKE SOME MUSIC",     blurb: "Turn a Music Maker tune into nodes and play it on the C64." },
    ];
}

/// @desc Welcome panel tour list geometry. Shared by Step (clicks) and
///       Draw GUI (drawing) so the two can never disagree.
function scr_tour_welcome_geom(_px, _py, _pw, _ph) {
    var _btn_w  = 190;
    var _btn_h  = 30;
    var _btn_x2 = _px + _pw - 20;
    var _btn_y1 = _py + _ph - 46;
    var _row_h  = 40;
    var _list_y1 = _py + 96;
    var _list_y2 = _py + _ph - 60;
    return {
        btn   : [_btn_x2 - _btn_w, _btn_y1, _btn_x2, _btn_y1 + _btn_h],
        list  : [_px + 20, _list_y1, _px + _pw - 20, _list_y2],
        row_h : _row_h,
        rows  : floor((_list_y2 - _list_y1) / _row_h)
    };
}

/// @desc Step builder.
function scr_tour_step(_title, _text, _targets, _check) {
    return { title: _title, text: _text, targets: _targets, check: _check };
}

/// @desc Every tour's steps, by tour id.
function scr_tour_define(_id) {
    var _s = [];

    if (_id == 0) {
        array_push(_s, scr_tour_step("WELCOME",
            "This tour builds a tiny program that changes the C64 border and background colours using real 6502 opcodes.\n\nEach step waits for you to do it. Click NEXT to skip a step.",
            [], "NONE"));
        array_push(_s, scr_tour_step("DRAG IN LDA_IMM",
            "LDA #value loads a number into the A register.\n\nDrag LDA_IMM from the opcode palette and drop it on the spine under SYSTEM INIT.",
            ["PAL:LDA_IMM", "ARROW:L"], "OP_LDA_IMM"));
        array_push(_s, scr_tour_step("CHOOSE A COLOUR",
            "Click the value on your LDA node, type 2 (red) and press ENTER.\n\nC64 colours run from 0 to 15.",
            ["OPERAND0:lda_imm", "NODEOP:lda_imm"], "LDA_NONZERO"));
        array_push(_s, scr_tour_step("DRAG IN STA_ABS",
            "STA stores the A register into memory.\n\nDrag STA_ABS onto the spine, under your LDA node.",
            ["PAL:STA_ABS", "ARROW:L"], "OP_STA_ABS"));
        array_push(_s, scr_tour_step("POINT IT AT THE BORDER",
            "Click the STA value and type $D020, then press ENTER.\n\n$D020 is the VIC-II border colour register.",
            ["OPERAND0:sta_abs", "NODEOP:sta_abs"], "STA_D020"));
        array_push(_s, scr_tour_step("NOW THE BACKGROUND",
            "Same again for the background.\n\nDrag another LDA_IMM onto the spine, under your STA node.",
            ["PAL:LDA_IMM", "ARROW:L"], "OP_LDA_IMM_2"));
        array_push(_s, scr_tour_step("CHOOSE A COLOUR",
            "Click the value on the new LDA node, type 7 (yellow) and press ENTER.",
            ["OPERAND0:lda_imm", "NODEOP:lda_imm"], "LDA_NONZERO_2"));
        array_push(_s, scr_tour_step("DRAG IN STA_ABS",
            "Drag another STA_ABS onto the spine, under the new LDA node.",
            ["PAL:STA_ABS", "ARROW:L"], "OP_STA_ABS_2"));
        array_push(_s, scr_tour_step("POINT IT AT THE BACKGROUND",
            "Click the new STA value, type $D021 and press ENTER.\n\n$D021 is the VIC-II background colour register.",
            ["OPERAND0:sta_abs", "NODEOP:sta_abs"], "STA_D021"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.\n\nIf you are asked about a missing loop or RTS, choose YES to add an RTS.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Your border should now be red and your background yellow.\n\nTry changing the numbers and pressing F5 again. More tours are in DOCUMENTS > GUIDED TOURS.",
            [], "NONE"));
    }

    if (_id == 1) {
        array_push(_s, scr_tour_step("WELCOME",
            "Macros are ready made nodes that write lots of 6502 for you.\n\nIn this tour you will print a message on the screen.",
            [], "NONE"));
        array_push(_s, scr_tour_step("OPEN THE MACROS 1 MENU",
            "Click MACROS 1 in the menu bar.",
            ["MENU:0"], "MENU_MACROS"));
        array_push(_s, scr_tour_step("DRAG IN PRINT",
            "Drag PRINT out of the list and drop it on the spine under SYSTEM INIT.",
            ["MAC:MACRO_PRINT", "MENU:0"], "HAS_PRINT"));
        array_push(_s, scr_tour_step("TYPE A MESSAGE",
            "Click the text field on the PRINT node, type HELLO C64 and press ENTER.",
            ["FIELD:MACRO_PRINT:text", "NODETYPE:MACRO_PRINT"], "PRINT_TEXT"));
        array_push(_s, scr_tour_step("MOVE IT DOWN",
            "Set the Y value on the PRINT node to 10 so the message sits mid screen.",
            ["FIELD:MACRO_PRINT:y", "NODETYPE:MACRO_PRINT"], "PRINT_Y"));
        array_push(_s, scr_tour_step("PICK A COLOUR",
            "Click the colour swatch on the PRINT node and choose any colour except white.",
            ["FIELD:MACRO_PRINT:col", "NODETYPE:MACRO_PRINT"], "PRINT_COL"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.\n\nIf you are asked about a missing loop or RTS, choose YES to add an RTS.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Your message should be on screen in your colour.\n\nEvery macro works the same way: drag it in, fill in its fields, build.",
            [], "NONE"));
    }

    if (_id == 2) {
        array_push(_s, scr_tour_step("WELCOME",
            "In this tour you will make a multicolour bitmap, paint on it and show it on the C64.",
            [], "NONE"));
        array_push(_s, scr_tour_step("ADD AN ASSET",
            "Click [ADD ASSET +] at the top of the asset panel.",
            ["ASSET:ADD"], "ADD_OPEN"));
        array_push(_s, scr_tour_step("CHOOSE BITMAP",
            "Pick BITMAP from the list. A new bitmap asset appears in the panel.",
            ["ASSET:TYPE:BITMAP", "ASSET:ADD"], "BMP_ADDED"));
        array_push(_s, scr_tour_step("OPEN THE EDITOR",
            "Click EDIT on your new BITMAP row to open the bitmap editor.",
            ["ASSET:EDIT:BITMAP", "ASSET:PANEL"], "BMP_OPEN"));
        array_push(_s, scr_tour_step("CREATE THE CANVAS",
            "A new bitmap starts empty, so there is nothing to draw on yet.\n\nClick CREATE at the top of the viewer to make a blank canvas and switch painting on.",
            ["ASSET:BMP_EDIT"], "BMP_EDITING"));
        array_push(_s, scr_tour_step("DRAW SOMETHING",
            "Pick a colour and draw on the canvas with the left mouse button.",
            [], "BMP_PAINTED"));
        array_push(_s, scr_tour_step("FLOOD FILL",
            "Choose the FILL tool, pick another colour and click inside a shape to fill it.",
            [], "BMP_FILLED"));
        array_push(_s, scr_tour_step("CLOSE THE EDITOR",
            "Click CLOSE at the top right of the viewer, or press ESC.",
            ["ASSET:CLOSE"], "BMP_CLOSED"));
        array_push(_s, scr_tour_step("DRAG IN BITMAP",
            "Open MACROS 1 and drag BITMAP onto the spine under SYSTEM INIT.",
            ["MAC:MACRO_BMP", "MENU:0"], "HAS_BMP_NODE"));
        array_push(_s, scr_tour_step("LINK YOUR PICTURE",
            "Click the asset field on the BITMAP node and choose the bitmap you painted.",
            ["FIELD:MACRO_BMP:asset", "NODETYPE:MACRO_BMP"], "BMP_LINKED"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.\n\nIf you are asked about a missing loop or RTS, choose YES to add an RTS.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Your picture should be on the C64 screen.\n\nThe bitmap editor also has lines, shapes, gradients and dithering to explore.",
            [], "NONE"));
    }

    if (_id == 3) {
        array_push(_s, scr_tour_step("WELCOME",
            "Sprites are the C64's hardware objects: 24 x 21 pixel shapes that move freely over the screen.\n\nIn this tour you will draw one and put it on screen with the SPRITE macro.",
            [], "NONE"));
        array_push(_s, scr_tour_step("ADD AN ASSET",
            "Click [ADD ASSET +] at the top of the asset panel.",
            ["ASSET:ADD"], "ADD_OPEN_SPR"));
        array_push(_s, scr_tour_step("CHOOSE SPRITE_SET",
            "Pick SPRITE_SET from the list. A new sprite asset appears in the panel.",
            ["ASSET:TYPE:SPRITE_SET", "ASSET:ADD"], "SPR_ADDED"));
        array_push(_s, scr_tour_step("OPEN IT",
            "Click EDIT on your new SPRITE_SET row to open its viewer.",
            ["ASSET:EDIT:SPRITE_SET", "ASSET:PANEL"], "SPR_VIEW"));
        array_push(_s, scr_tour_step("OPEN THE SPRITE EDITOR",
            "Click EDIT SPRITES to open the sprite editor.",
            ["ASSET:SPR_EDIT"], "SPR_V2_OPEN"));
        array_push(_s, scr_tour_step("DRAW YOUR SPRITE",
            "Draw a shape in the big grid with the left mouse button. Right click rubs out.\n\nA small, chunky shape shows up best.",
            [], "SPR_DRAWN"));
        array_push(_s, scr_tour_step("CLOSE THE VIEWER",
            "Click CLOSE at the top right of the viewer, or press ESC. Your drawing is kept.",
            ["ASSET:CLOSE"], "SPR_CLOSED"));
        array_push(_s, scr_tour_step("DRAG IN SPRITE",
            "Open MACROS 1 and drag SPRITE onto the spine under SYSTEM INIT.",
            ["MAC:MACRO_SPR", "MENU:0"], "HAS_SPR"));
        array_push(_s, scr_tour_step("LINK YOUR SPRITE",
            "Click the asset name on the SPRITE node and choose the sprite set you just drew.",
            ["NODETYPE:MACRO_SPR"], "SPR_LINKED"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.\n\nIf you are asked about a missing loop or RTS, choose YES to add an RTS.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Your sprite should be in the middle of the screen.\n\nTry changing X and Y on the SPRITE node and building again. The JOYSTICK tour makes it move.",
            [], "NONE"));
    }

    if (_id == 4) {
        array_push(_s, scr_tour_step("WELCOME",
            "Every game runs in a loop: wait for the next frame, update everything, jump back and do it again.\n\nIn this tour you will build that loop and use it to flash the border.",
            [], "NONE"));
        array_push(_s, scr_tour_step("MAKE A LABEL",
            "A label is a named place in your program that you can jump back to.\n\nMove the mouse over an empty part of the canvas and press A.",
            [], "LABEL_EXISTS"));
        array_push(_s, scr_tour_step("ATTACH THE LABEL",
            "Drag the new ADDRESS LABEL onto the spine under SYSTEM INIT.",
            ["FREELABEL", "NODETYPE:LABEL"], "LABEL_CONNECTED"));
        array_push(_s, scr_tour_step("NAME IT MAIN",
            "Click the label's name, type MAIN and press ENTER.",
            ["NODETYPE:LABEL"], "LABEL_MAIN"));
        array_push(_s, scr_tour_step("WAIT FOR THE FRAME",
            "Open MACROS 1 and drag VWAIT onto the spine under MAIN.\n\nVWAIT waits for the screen to be redrawn, so the loop runs 50 times a second.",
            ["MAC:MACRO_VWAIT", "MENU:0"], "HAS_VWAIT"));
        array_push(_s, scr_tour_step("PICK A RANDOM NUMBER",
            "Open MACROS 2 and drag RANDOM onto the spine under VWAIT.\n\nIt leaves a random number in the A register.",
            ["MAC:MACRO_RANDOM", "MENU:1"], "HAS_RANDOM"));
        array_push(_s, scr_tour_step("DRAG IN STA_ABS",
            "Drag STA_ABS from the opcode palette onto the spine under RANDOM.",
            ["PAL:STA_ABS", "ARROW:L"], "OP_STA_ABS"));
        array_push(_s, scr_tour_step("POINT IT AT THE BORDER",
            "Click the STA value, type $D020 and press ENTER.",
            ["OPERAND0:sta_abs", "NODEOP:sta_abs"], "STA_D020"));
        array_push(_s, scr_tour_step("DRAG IN JMP_ABS",
            "JMP_ABS is on a later palette page. Use the arrows to find it, then drag it onto the spine under STA.",
            ["PAL:JMP_ABS", "ARROW:R"], "OP_JMP"));
        array_push(_s, scr_tour_step("JUMP BACK TO MAIN",
            "Click the JMP value and choose MAIN from the list.\n\nThis closes the loop.",
            ["NODEOP:jmp_abs"], "JMP_MAIN"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "The border changes to a random colour every frame.\n\nMAIN, VWAIT, your code, JMP MAIN: this is the shape of every game loop. The next tours build on it.",
            [], "NONE"));
    }

    if (_id == 5) {
        array_push(_s, scr_tour_step("WELCOME",
            "A ship sprite and a game loop (MAIN, VWAIT, JMP MAIN) are already set up for you.\n\nIn this tour you will steer the ship left and right with a joystick.",
            [], "NONE"));
        array_push(_s, scr_tour_step("DRAG IN JOYSTICK",
            "Open MACROS 1 and drag JOYSTICK onto the spine between VWAIT and JMP MAIN.\n\nIt reads the stick once per frame.",
            ["MAC:MACRO_JOY", "MENU:0"], "JOY_IN_LOOP"));
        array_push(_s, scr_tour_step("TURN ON LEFT",
            "Click LF on the JOYSTICK node.\n\nA label called LF appears beside it. The joystick calls it whenever the stick is pushed left.",
            ["FIELD:MACRO_JOY:LF", "NODETYPE:MACRO_JOY"], "JOY_LF"));
        array_push(_s, scr_tour_step("TURN ON RIGHT",
            "Click RT on the JOYSTICK node. A label called RT appears too.",
            ["FIELD:MACRO_JOY:RT", "NODETYPE:MACRO_JOY"], "JOY_RT"));
        array_push(_s, scr_tour_step("ATTACH LF",
            "Drag the LF label onto the spine below JMP MAIN.\n\nCode below the JMP only runs when something calls it.",
            ["LABELNAME:LF"], "LF_BELOW"));
        array_push(_s, scr_tour_step("DRAG IN MOVE",
            "Open MACROS 1 and drag MOVE onto the spine under LF.",
            ["MAC:MACRO_MOVE", "MENU:0"], "MOVE_AFTER_LF"));
        array_push(_s, scr_tour_step("MOVE LEFT",
            "Click the DX value on the MOVE node, type -2 and press ENTER.\n\nDX is how far the sprite moves across each frame.",
            ["NODETYPE:MACRO_MOVE"], "MOVE_NEG"));
        array_push(_s, scr_tour_step("RETURN",
            "Drag RTS from the opcode palette onto the spine under MOVE.\n\nRTS returns to the joystick, so the loop carries on.",
            ["PAL:RTS", "ARROW:R"], "RTS_1"));
        array_push(_s, scr_tour_step("ATTACH RT",
            "Drag the RT label onto the spine under that RTS.",
            ["LABELNAME:RT"], "RT_BELOW"));
        array_push(_s, scr_tour_step("ANOTHER MOVE",
            "Drag another MOVE from MACROS 1 onto the spine under RT.",
            ["MAC:MACRO_MOVE", "MENU:0"], "MOVE_2"));
        array_push(_s, scr_tour_step("MOVE RIGHT",
            "Set DX on the new MOVE node to 2 and press ENTER.",
            ["LASTTYPE:MACRO_MOVE"], "MOVE_POS"));
        array_push(_s, scr_tour_step("RETURN AGAIN",
            "Drag another RTS onto the spine under the new MOVE.",
            ["PAL:RTS", "ARROW:R"], "RTS_2"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Push the joystick in port 2 left and right to fly the ship.\n\nIn VICE, map port 2 to your keyboard or numpad in the joystick settings. Try UP and DN with DY next.",
            [], "NONE"));
    }

    if (_id == 6) {
        array_push(_s, scr_tour_step("WELCOME",
            "A game loop (MAIN, VWAIT, JMP MAIN) is already set up for you.\n\nIn this tour a key press will change the border colour.",
            [], "NONE"));
        array_push(_s, scr_tour_step("DRAG IN KEYS A-Z",
            "Open MACROS 1 and drag KEYS A-Z onto the spine between VWAIT and JMP MAIN.",
            ["MAC:MACRO_LETTERS", "MENU:0"], "KEYS_IN_LOOP"));
        array_push(_s, scr_tour_step("TURN ON B",
            "Click B on the KEYS A-Z node.\n\nA label called KEY_B appears beside it. It is called every frame B is held.",
            ["FIELD:MACRO_LETTERS:B", "NODETYPE:MACRO_LETTERS"], "KEY_B_ON"));
        array_push(_s, scr_tour_step("ATTACH KEY_B",
            "Drag the KEY_B label onto the spine below JMP MAIN.",
            ["LABELNAME:KEY_B"], "KEYB_BELOW"));
        array_push(_s, scr_tour_step("DRAG IN INC_ABS",
            "INC adds one to a memory location.\n\nFind INC_ABS in the opcode palette and drag it onto the spine under KEY_B.",
            ["PAL:INC_ABS", "ARROW:R"], "OP_INC_ABS"));
        array_push(_s, scr_tour_step("POINT IT AT THE BORDER",
            "Click the INC value, type $D020 and press ENTER.",
            ["OPERAND0:inc_abs", "NODEOP:inc_abs"], "INC_D020"));
        array_push(_s, scr_tour_step("RETURN",
            "Drag RTS onto the spine under INC.",
            ["PAL:RTS", "ARROW:R"], "RTS_1"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Hold B and the border cycles through the colours.\n\nTurn on more letters and give each its own label for menus, cheats or controls.",
            [], "NONE"));
    }

    if (_id == 7) {
        array_push(_s, scr_tour_step("WELCOME",
            "A game loop (MAIN, VWAIT, JMP MAIN) is already set up for you.\n\nIn this tour you will add a smooth scrolling message.",
            [], "NONE"));
        array_push(_s, scr_tour_step("CLEAR THE SCREEN",
            "Open MACROS 1 and drag CLR SCRN RAM onto the spine between SYSTEM INIT and MAIN.\n\nIt runs once, before the loop starts.",
            ["MAC:MACRO_CLR_SCREEN", "MENU:0"], "CLR_BEFORE_LOOP"));
        array_push(_s, scr_tour_step("DRAG IN TXT SCROLL",
            "Drag TXT SCROLL from MACROS 1 onto the spine between VWAIT and JMP MAIN.",
            ["MAC:MACRO_TEXT_SCROLL", "MENU:0"], "TXT_IN_LOOP"));
        array_push(_s, scr_tour_step("WRITE YOUR MESSAGE",
            "Click the TEXT field on the TXT SCROLL node, type your own message and press ENTER.\n\nEnd it with a space so it wraps neatly.",
            ["NODETYPE:MACRO_TEXT_SCROLL"], "TXT_CHANGED"));
        array_push(_s, scr_tour_step("PICK A COLOUR",
            "Click the COLOUR on the node and choose any colour except white.",
            ["NODETYPE:MACRO_TEXT_SCROLL"], "TXT_COL"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Your message scrolls along the bottom of the screen.\n\nTry the SPEED setting, or move it up the screen.",
            [], "NONE"));
    }

    if (_id == 8) {
        array_push(_s, scr_tour_step("WELCOME",
            "Two ships, a game loop and joystick steering are already set up. This is where the JOYSTICK tour ended, plus a second ship.\n\nIn this tour the border flashes when the ships touch.",
            [], "NONE"));
        array_push(_s, scr_tour_step("MAKE A LABEL",
            "Move the mouse over an empty part of the canvas and press A.",
            [], "LABEL_EXISTS"));
        array_push(_s, scr_tour_step("NAME IT HIT",
            "Click the new label's name, type HIT and press ENTER.",
            ["FREELABEL"], "LBL_HIT"));
        array_push(_s, scr_tour_step("ATTACH HIT",
            "Drag HIT onto the spine under the last RTS.",
            ["LABELNAME:HIT"], "HIT_BELOW"));
        array_push(_s, scr_tour_step("DRAG IN INC_ABS",
            "Find INC_ABS in the opcode palette and drag it onto the spine under HIT.",
            ["PAL:INC_ABS", "ARROW:R"], "OP_INC_ABS"));
        array_push(_s, scr_tour_step("POINT IT AT THE BORDER",
            "Click the INC value, type $D020 and press ENTER.",
            ["OPERAND0:inc_abs", "NODEOP:inc_abs"], "INC_D020"));
        array_push(_s, scr_tour_step("RETURN",
            "Drag RTS onto the spine under INC.",
            ["PAL:RTS", "ARROW:R"], "RTS_3"));
        array_push(_s, scr_tour_step("DRAG IN COLLIDE",
            "Open MACROS 1 and drag COLLIDE onto the spine between JOYSTICK and JMP MAIN.\n\nIt checks the C64's sprite collision hardware every frame.",
            ["MAC:MACRO_COLLISION", "MENU:0"], "COLL_IN_LOOP"));
        array_push(_s, scr_tour_step("CALL HIT",
            "Click the JSR label field at the bottom of the COLLIDE node and choose HIT.",
            ["NODETYPE:MACRO_COLLISION"], "COLL_HIT"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "Fly your ship into the other one. The border flashes while they overlap.\n\nSwap INC for anything you like: a sound, a score, losing a life.",
            [], "NONE"));
    }

    if (_id == 9) {
        array_push(_s, scr_tour_step("WELCOME",
            "A short tune called TOUR_TUNE is already in your asset panel.\n\nIn this tour you will hear it, turn it into nodes and play it on the C64.",
            [], "NONE"));
        array_push(_s, scr_tour_step("OPEN MUSIC MAKER",
            "Click EDIT on the TOUR_TUNE row to open the Music Maker.",
            ["ASSET:EDIT:MUSIC_MAKER", "ASSET:PANEL"], "MUS_OPEN"));
        array_push(_s, scr_tour_step("HAVE A LISTEN",
            "Press F1 to play the song and F4 to stop it.\n\nClick NEXT when you are ready.",
            [], "NONE"));
        array_push(_s, scr_tour_step("GENERATE NODES",
            "Click GENERATE NODES.\n\nMusic Maker builds the player, the play call and a CORE LOOP on your workspace for you.",
            ["ASSET:MUS_GEN"], "MUS_GENERATED"));
        array_push(_s, scr_tour_step("CLOSE THE EDITOR",
            "Click CLOSE at the top right, or press ESC, and look at the new nodes.",
            ["ASSET:CLOSE"], "MUS_CLOSED"));
        array_push(_s, scr_tour_step("BUILD AND RUN",
            "Press F5, or click BUILD & RUN on the right, to build and launch.",
            ["UI:BUILD & RUN"], "BUILT"));
        array_push(_s, scr_tour_step("DONE!",
            "The tune plays on the C64.\n\nOpen the Music Maker again to change notes, then GENERATE NODES and build to hear your edits.",
            [], "NONE"));
    }

    return _s;
}

/// @desc Called on the tour object whenever step_idx changes.
function scr_tour_enter_step() {
    step_timer = 0;
    done_timer = 0;
    hl_have    = false;

    var _targets = [];
    if (step_idx >= 0 && step_idx < array_length(steps)) {
        _targets = steps[step_idx].targets;
    }
    global.tour_keys   = _targets;
    global.tour_rects  = array_create(array_length(_targets), 0);
    global.tour_stamps = array_create(array_length(_targets), -1);
    for (var _i = 0; _i < array_length(_targets); _i++) {
        global.tour_rects[_i] = [0, 0, 0, 0];
    }

    base_bmp_count   = scr_tour_bitmap_count();
    base_spr_count   = scr_tour_asset_count("SPRITE_SET");
    base_label_count = scr_tour_count_type("LABEL", false);
    base_undo_top  = undefined;
    base_undo_name = "";
    base_build     = global.tour_build_count;
}

/// @desc Draw loops call this with the rect they just drew for _key.
function scr_tour_capture(_key, _x1, _y1, _x2, _y2) {
    if (!global.tour_active) {
        return;
    }
    for (var _i = 0; _i < array_length(global.tour_keys); _i++) {
        if (global.tour_keys[_i] == _key) {
            global.tour_rects[_i]  = [_x1, _y1, _x2, _y2];
            global.tour_stamps[_i] = global.tour_frame;
            return;
        }
    }
}

/// @desc Same as scr_tour_capture, but for rects drawn in world space (node
///       Draw events). Converted to GUI with the workspace camera.
function scr_tour_capture_world(_key, _x1, _y1, _x2, _y2) {
    if (!global.tour_active) {
        return;
    }
    var _wm = obj_workspace_manager;
    scr_tour_capture(_key,
        (_x1 - _wm.cam_x) / _wm.cam_zoom, (_y1 - _wm.cam_y) / _wm.cam_zoom,
        (_x2 - _wm.cam_x) / _wm.cam_zoom, (_y2 - _wm.cam_y) / _wm.cam_zoom);
}

/// @desc Operand as a number: reals pass through, "$D020" and "53280" parse.
function scr_tour_num(_v) {
    if (is_real(_v) || is_int64(_v)) {
        return _v;
    }
    if (!is_string(_v)) {
        return 0;
    }
    var _s = string_upper(string_trim(_v));
    if (_s == "") {
        return 0;
    }
    if (string_char_at(_s, 1) == "$") {
        var _hex = "0123456789ABCDEF";
        var _n   = 0;
        for (var _i = 2; _i <= string_length(_s); _i++) {
            var _d = string_pos(string_char_at(_s, _i), _hex) - 1;
            if (_d < 0) {
                return _n;
            }
            _n = (_n * 16) + _d;
        }
        return _n;
    }
    if (string_digits(_s) == _s) {
        return real(_s);
    }
    return 0;
}

/// @desc Connected NORMAL node that uses opcode _op. Prefers one whose
///       operand is still 0 (the one the user has not edited yet).
function scr_tour_node_by_op(_op) {
    var _any   = noone;
    var _fresh = noone;
    with (obj_c64_node) {
        if (is_connected && node_type == "NORMAL") {
            for (var _i = 0; _i < array_length(instructions); _i++) {
                if (string_lower(string(instructions[_i][0])) == _op) {
                    if (_any == noone) {
                        _any = id;
                    }
                    if (_fresh == noone && scr_tour_num(instructions[_i][1]) == 0) {
                        _fresh = id;
                    }
                }
            }
        }
    }
    if (_fresh != noone) {
        return _fresh;
    }
    return _any;
}

/// @desc Any connected NORMAL node with opcode _op whose operand is _val.
///       _val < 0 means "any non-zero operand".
function scr_tour_has_op_value(_op, _val) {
    var _found = false;
    with (obj_c64_node) {
        if (is_connected && node_type == "NORMAL") {
            for (var _i = 0; _i < array_length(instructions); _i++) {
                if (string_lower(string(instructions[_i][0])) == _op) {
                    var _n = scr_tour_num(instructions[_i][1]);
                    if (_val < 0) {
                        if (_n != 0) {
                            _found = true;
                        }
                    } else {
                        if (_n == _val) {
                            _found = true;
                        }
                    }
                }
            }
        }
    }
    return _found;
}

/// @desc How many connected NORMAL nodes use opcode _op.
///       _nonzero: only count ones whose operand has been set.
function scr_tour_count_op(_op, _nonzero) {
    var _c = 0;
    with (obj_c64_node) {
        if (is_connected && node_type == "NORMAL") {
            for (var _i = 0; _i < array_length(instructions); _i++) {
                if (string_lower(string(instructions[_i][0])) == _op) {
                    if (!_nonzero || scr_tour_num(instructions[_i][1]) != 0) {
                        _c++;
                    }
                }
            }
        }
    }
    return _c;
}

/// @desc First connected node of _type, or noone.
function scr_tour_node_by_type(_type) {
    var _hit = noone;
    with (obj_c64_node) {
        if (_hit == noone && is_connected && node_type == _type) {
            _hit = id;
        }
    }
    return _hit;
}

/// @desc Number of BITMAP assets in the asset list.
function scr_tour_bitmap_count() {
    var _c = 0;
    if (!instance_exists(obj_asset_manager)) {
        return 0;
    }
    var _list = obj_asset_manager.asset_list;
    for (var _i = 0; _i < ds_list_size(_list); _i++) {
        var _a = ds_list_find_value(_list, _i);
        if (_a.type == "BITMAP") {
            _c++;
        }
    }
    return _c;
}

/// @desc The BITMAP asset open in the viewer, or undefined.
function scr_tour_viewer_bitmap() {
    if (!instance_exists(obj_asset_manager)) {
        return undefined;
    }
    var _am = obj_asset_manager;
    if (!_am.viewer_open) {
        return undefined;
    }
    if (_am.viewer_asset < 0 || _am.viewer_asset >= ds_list_size(_am.asset_list)) {
        return undefined;
    }
    var _a = ds_list_find_value(_am.asset_list, _am.viewer_asset);
    if (_a.type != "BITMAP") {
        return undefined;
    }
    return _a;
}

/// @desc True once a new undo entry lands on the open bitmap.
///       _need_fill: only count it while the FILL tool is selected.
function scr_tour_bitmap_changed(_need_fill) {
    var _a = scr_tour_viewer_bitmap();
    if (is_undefined(_a)) {
        base_undo_name = "";
        return false;
    }
    var _stack = _a.meta[$ "undo_stack"];
    if (!is_array(_stack)) {
        return false;
    }
    var _top = undefined;
    if (array_length(_stack) > 0) {
        _top = _stack[array_length(_stack) - 1];
    }
    var _tool_ok = true;
    if (_need_fill) {
        _tool_ok = (_a.meta[$ "active_tool"] == "FILL");
    }
    // Re-base while the editor settles (it pushes its own first entry on
    // open), when the open asset changes, or while the wrong tool is held.
    if (step_timer < 20 || base_undo_name != _a.name || !_tool_ok) {
        base_undo_name = _a.name;
        base_undo_top  = _top;
        return false;
    }
    if (is_undefined(_top)) {
        return false;
    }
    return (_top != base_undo_top);
}

/// @desc Evaluate a step's check code. Runs on the tour object.
function scr_tour_check(_code) {
    var _n = noone;
    switch (_code) {
        case "NONE":
            return false;
        case "OP_LDA_IMM":
            return (scr_tour_node_by_op("lda_imm") != noone);
        case "LDA_NONZERO":
            return scr_tour_has_op_value("lda_imm", -1);
        case "OP_STA_ABS":
            return (scr_tour_node_by_op("sta_abs") != noone);
        case "STA_D020":
            return scr_tour_has_op_value("sta_abs", 0xD020);
        case "STA_D021":
            return scr_tour_has_op_value("sta_abs", 0xD021);
        case "OP_LDA_IMM_2":
            return (scr_tour_count_op("lda_imm", false) >= 2);
        case "LDA_NONZERO_2":
            return (scr_tour_count_op("lda_imm", true) >= 2);
        case "OP_STA_ABS_2":
            return (scr_tour_count_op("sta_abs", false) >= 2);
        case "BUILT":
            return (global.tour_build_count > base_build);
        case "MENU_MACROS":
            if (obj_workspace_manager.gui_menu_open == 0) {
                return true;
            }
            return (scr_tour_node_by_type("MACRO_PRINT") != noone);
        case "HAS_PRINT":
            return (scr_tour_node_by_type("MACRO_PRINT") != noone);
        case "PRINT_TEXT":
            _n = scr_tour_node_by_type("MACRO_PRINT");
            if (_n == noone) {
                return false;
            }
            return (string(_n.instructions[0][5]) != "");
        case "PRINT_Y":
            _n = scr_tour_node_by_type("MACRO_PRINT");
            if (_n == noone) {
                return false;
            }
            return (scr_tour_num(_n.instructions[0][2]) != 0);
        case "PRINT_COL":
            _n = scr_tour_node_by_type("MACRO_PRINT");
            if (_n == noone) {
                return false;
            }
            return (scr_tour_num(_n.instructions[0][3]) != 1);
        case "ADD_OPEN":
            if (obj_asset_manager.add_dropdown_open) {
                return true;
            }
            return (scr_tour_bitmap_count() > base_bmp_count);
        case "BMP_ADDED":
            return (scr_tour_bitmap_count() > base_bmp_count);
        case "BMP_OPEN":
            return !is_undefined(scr_tour_viewer_bitmap());
        case "BMP_EDITING":
            var _eb = scr_tour_viewer_bitmap();
            if (is_undefined(_eb)) {
                return false;
            }
            return (_eb.meta[$ "is_editing"] == true);
        case "BMP_PAINTED":
            return scr_tour_bitmap_changed(false);
        case "BMP_FILLED":
            return scr_tour_bitmap_changed(true);
        case "BMP_CLOSED":
            return !obj_asset_manager.viewer_open;
        case "HAS_BMP_NODE":
            return (scr_tour_node_by_type("MACRO_BMP") != noone);
        case "BMP_LINKED":
            _n = scr_tour_node_by_type("MACRO_BMP");
            if (_n == noone) {
                return false;
            }
            return (string(_n.instructions[0][1]) != "");
    }
    return scr_tour_check_ext(_code);
}

/// @desc GUI rect of a node (world -> GUI via the workspace camera).
function scr_tour_node_rect(_n) {
    var _wm = obj_workspace_manager;
    var _nx = _n.x + _n.x_indent;
    var _x1 = (_nx - _wm.cam_x) / _wm.cam_zoom;
    var _y1 = (_n.y - _wm.cam_y) / _wm.cam_zoom;
    var _x2 = (_nx + _n.width - _wm.cam_x) / _wm.cam_zoom;
    var _y2 = (_n.y + _n.height - _wm.cam_y) / _wm.cam_zoom;
    return [_x1, _y1, _x2, _y2];
}

/// @desc Resolve the current step's highlight. Returns [x1,y1,x2,y2] or
///       undefined when nothing is on screen.
function scr_tour_resolve_rect() {
    var _keys = global.tour_keys;
    for (var _i = 0; _i < array_length(_keys); _i++) {
        var _k = _keys[_i];

        if (global.tour_stamps[_i] == global.tour_frame) {
            return global.tour_rects[_i];
        }

        if (string_copy(_k, 1, 7) == "NODEOP:") {
            var _no = scr_tour_node_by_op(string_delete(_k, 1, 7));
            if (_no != noone) {
                return scr_tour_node_rect(_no);
            }
        }
        if (string_copy(_k, 1, 9) == "NODETYPE:") {
            var _nt = scr_tour_node_by_type(string_delete(_k, 1, 9));
            if (_nt != noone) {
                return scr_tour_node_rect(_nt);
            }
        }

        var _ext = scr_tour_resolve_ext(_k);
        if (!is_undefined(_ext)) {
            return _ext;
        }

        if (instance_exists(obj_asset_manager)) {
            var _am    = obj_asset_manager;
            var _right = global.gui_w - 2;
            if (_k == "ASSET:ADD" && !_am.viewer_open) {
                return [_am.panel_x + 4, _am.panel_y + 4, _right - 4, _am.panel_y + 26];
            }
            if (_k == "ASSET:PANEL" && !_am.viewer_open) {
                return [_am.panel_x, _am.panel_y + 66, _right, display_get_gui_height() - 100];
            }
            if (string_copy(_k, 1, 11) == "ASSET:TYPE:" && _am.add_dropdown_open) {
                var _want = string_delete(_k, 1, 11);
                for (var _t = 0; _t < array_length(_am.asset_types); _t++) {
                    if (_am.asset_types[_t] == _want) {
                        var _dy = _am.panel_y + 28 + (_t * 20);
                        return [_am.panel_x, _dy, _right, _dy + 20];
                    }
                }
            }
        }
    }
    return undefined;
}

/// @desc End the tour and put anything it changed back.
function scr_tour_end() {
    if (instance_exists(obj_tour_guide)) {
        instance_destroy(obj_tour_guide);
    }
}

// ---------------------------------------------------------------------------
// Starter workspaces. Tours from 5 on build on earlier ones, so they start
// with what those tours made already in place, built with the same nodes and
// assets a user would make by hand.
// ---------------------------------------------------------------------------

/// @desc Put the starting nodes / assets in place for tour _id.
function scr_tour_setup(_id) {
    var _made = false;
    if (_id == 5) {
        scr_tour_make_ship();
        scr_tour_build_starter("SPRITE");
        _made = true;
    }
    if (_id == 6 || _id == 7) {
        scr_tour_build_starter("LOOP");
        _made = true;
    }
    if (_id == 8) {
        scr_tour_make_ship();
        scr_tour_build_starter("COLLIDE");
        _made = true;
    }
    if (_id == 9) {
        scr_tour_make_music();
        _made = true;
    }
    if (_made) {
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        global.autosave_dirty  = true;
        obj_workspace_manager.flow_overlay_dirty = true;
    }
}

/// @desc A one-sprite SPRITE_SET called SHIP, made the way [ADD ASSET +]
///       makes one, with a small ship already drawn in it.
function scr_tour_make_ship() {
    if (!instance_exists(obj_asset_manager)) {
        return;
    }
    var _hex = "000000000000000000000000003800003800003800007C00007C00007C0000EE0000EE0000EE0001EF0017FFE81FFFF81FFFF81FFFF8007C0000540000100000";
    var _buf = buffer_create(64, buffer_fixed, 1);
    for (var _i = 0; _i < 64; _i++) {
        buffer_write(_buf, buffer_u8, scr_tour_num("$" + string_copy(_hex, (_i * 2) + 1, 2)));
    }
    var _meta = {
        format      : "binary",
        has_colour  : true,
        bg_col      : 0,
        mc1_col     : 1,
        mc2_col     : 2,
        sprite_mcs  : array_create(1, 0),
        sprite_ucs  : array_create(1, 7),
        spr_sprites : array_create(1, -1),
        found_count : 1,
        used_count  : 1,
        total_size  : 64
    };
    var _a = {
        type          : "SPRITE_SET",
        name          : "SHIP",
        file          : "",
        address       : scr_asset_default_address("SPRITE_SET"),
        buffer        : _buf,
        meta          : _meta,
        load_later    : false,
        d64_filename  : "",
        reu_filename  : "",
        reu_size      : 0,
        reu_used      : 0,
        linked_assets : [],
        group         : ""
    };
    ds_list_add(obj_asset_manager.asset_list, _a);
    scr_asset_spr_cache_sprites(_a, true);
}

/// @desc A MUSIC_MAKER asset called TOUR_TUNE, filled from the bundled
///       TOURS/tour_music.json through the same path the project loader uses.
function scr_tour_make_music() {
    if (!instance_exists(obj_asset_manager)) {
        return;
    }
    var _path = working_directory + "C64DMResources/TOURS/tour_music.json";
    if (!file_exists(_path)) {
        scr_show_message("The tour music file is missing.");
        return;
    }
    var _b = buffer_load(_path);
    if (_b == -1) {
        scr_show_message("The tour music file could not be read.");
        return;
    }
    var _text = buffer_read(_b, buffer_text);
    buffer_delete(_b);
    var _src = undefined;
    try {
        _src = json_parse(_text);
    } catch (_err) {
        _src = undefined;
    }
    if (!is_struct(_src)) {
        scr_show_message("The tour music file is not valid.");
        return;
    }
    var _a = {
        type          : "MUSIC_MAKER",
        name          : "TOUR_TUNE",
        file          : "",
        address       : scr_asset_default_address("MUSIC_MAKER"),
        buffer        : buffer_create(1, buffer_fixed, 1),
        meta          : {},
        load_later    : false,
        d64_filename  : "",
        reu_filename  : "",
        reu_size      : 0,
        reu_used      : 0,
        linked_assets : [],
        group         : ""
    };
    scr_sound_editor_create(_a);
    scr_music_sid_copy_meta(_src, _a.meta);
    ds_list_add(obj_asset_manager.asset_list, _a);
}

/// @desc Attach _n to the main spine at the cursor in _st and move the
///       cursor down past it.
function scr_tour_spine_place(_n, _st) {
    _n.x            = _st.x;
    _n.y            = _st.y;
    _n.is_connected = true;
    _n.org_parent   = noone;
    _n.x_indent     = 0;
    _n.height_dirty = true;
    scr_macro_sync_height(_n);
    _n.prev_height  = _n.height;
    _st.y += ceil(_n.height / 20) * 20;
    return _n;
}

function scr_tour_spine_macro(_type, _st) {
    var _n = scr_node_spawn(_type, _st.x, _st.y);
    return scr_tour_spine_place(_n, _st);
}

function scr_tour_spine_op(_op, _operand, _st) {
    var _n = scr_music_sid_op(_op, _operand, _st.x, _st.y, noone);
    return scr_tour_spine_place(_n, _st);
}

function scr_tour_spine_label(_name, _st) {
    var _n = scr_music_sid_label(_name, _st.x, _st.y, noone);
    return scr_tour_spine_place(_n, _st);
}

/// @desc Build a starter spine under SYSTEM INIT.
///       LOOP    : MAIN, VWAIT, JMP MAIN
///       SPRITE  : SPRITE (SHIP), then LOOP
///       COLLIDE : two SPRITEs, LOOP with JOYSTICK, and LF / RT move routines
function scr_tour_build_starter(_kind) {
    var _init = scr_tour_node_by_type("INIT");
    if (_init == noone) {
        return;
    }
    var _st = { x: _init.x, y: _init.y + (ceil(_init.height / 20) * 20) };
    var _n  = noone;

    if (_kind == "SPRITE") {
        _n = scr_tour_spine_macro("MACRO_SPR", _st);
        _n.instructions[0][1] = "SHIP";
        _n.instructions[0][2] = 0;
        _n.instructions[0][3] = 172;
        _n.instructions[0][4] = 150;
    }
    if (_kind == "COLLIDE") {
        _n = scr_tour_spine_macro("MACRO_SPR", _st);
        _n.instructions[0][1] = "SHIP";
        _n.instructions[0][2] = 0;
        _n.instructions[0][3] = 100;
        _n.instructions[0][4] = 150;
        _n = scr_tour_spine_macro("MACRO_SPR", _st);
        _n.instructions[0][1] = "SHIP";
        _n.instructions[0][2] = 1;
        _n.instructions[0][3] = 220;
        _n.instructions[0][4] = 150;
    }

    scr_tour_spine_label("MAIN", _st);
    scr_tour_spine_macro("MACRO_VWAIT", _st);
    if (_kind == "COLLIDE") {
        _n = scr_tour_spine_macro("MACRO_JOY", _st);
        _n.instructions[16][2] = 1;
        _n.instructions[17][2] = 1;
    }
    scr_tour_spine_op("jmp_abs", "MAIN", _st);

    if (_kind == "COLLIDE") {
        scr_tour_spine_label("LF", _st);
        _n = scr_tour_spine_macro("MACRO_MOVE", _st);
        _n.instructions[0][2] = -2;
        scr_tour_spine_op("rts", 0, _st);
        scr_tour_spine_label("RT", _st);
        _n = scr_tour_spine_macro("MACRO_MOVE", _st);
        _n.instructions[0][2] = 2;
        scr_tour_spine_op("rts", 0, _st);
    }
}

// ---------------------------------------------------------------------------
// Check helpers for tours 3-9
// ---------------------------------------------------------------------------

/// @desc Number of assets of _type in the asset list.
function scr_tour_asset_count(_type) {
    var _c = 0;
    if (!instance_exists(obj_asset_manager)) {
        return 0;
    }
    var _list = obj_asset_manager.asset_list;
    for (var _i = 0; _i < ds_list_size(_list); _i++) {
        var _a = ds_list_find_value(_list, _i);
        if (_a.type == _type) {
            _c++;
        }
    }
    return _c;
}

/// @desc First asset of _type, or undefined.
function scr_tour_asset_by_type(_type) {
    if (!instance_exists(obj_asset_manager)) {
        return undefined;
    }
    var _list = obj_asset_manager.asset_list;
    for (var _i = 0; _i < ds_list_size(_list); _i++) {
        var _a = ds_list_find_value(_list, _i);
        if (_a.type == _type) {
            return _a;
        }
    }
    return undefined;
}

/// @desc Type of the asset open in the viewer, or "".
function scr_tour_viewer_type() {
    if (!instance_exists(obj_asset_manager)) {
        return "";
    }
    var _am = obj_asset_manager;
    if (!_am.viewer_open) {
        return "";
    }
    if (_am.viewer_asset < 0 || _am.viewer_asset >= ds_list_size(_am.asset_list)) {
        return "";
    }
    return ds_list_find_value(_am.asset_list, _am.viewer_asset).type;
}

/// @desc True once the sprite being edited (or any SPRITE_SET) has a pixel set.
function scr_tour_sprite_drawn() {
    if (!instance_exists(obj_asset_manager)) {
        return false;
    }
    var _v = obj_asset_manager.spred64_v2;
    if (_v.active) {
        var _base = _v.selected_slot * 504;
        for (var _i = 0; _i < 504; _i++) {
            if (_v.bits[_base + _i] != 0) {
                return true;
            }
        }
        return false;
    }
    var _list = obj_asset_manager.asset_list;
    for (var _ai = 0; _ai < ds_list_size(_list); _ai++) {
        var _a = ds_list_find_value(_list, _ai);
        if (_a.type == "SPRITE_SET" && buffer_exists(_a.buffer)) {
            var _sz = buffer_get_size(_a.buffer);
            for (var _bi = 0; _bi < _sz; _bi++) {
                if (buffer_peek(_a.buffer, _bi, buffer_u8) != 0) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// @desc How many nodes of _type exist. _connected_only: spine/ORG nodes only.
function scr_tour_count_type(_type, _connected_only) {
    var _c = 0;
    with (obj_c64_node) {
        if (node_type == _type) {
            if (!_connected_only || is_connected) {
                _c++;
            }
        }
    }
    return _c;
}

/// @desc Lowest connected node of _type on the canvas, or noone.
function scr_tour_last_by_type(_type) {
    var _hit = noone;
    var _y   = -1000000;
    with (obj_c64_node) {
        if (is_connected && node_type == _type && y > _y) {
            _y   = y;
            _hit = id;
        }
    }
    return _hit;
}

/// @desc LABEL node called _name (any case), connected or not, or noone.
function scr_tour_label(_name) {
    var _want = string_upper(_name);
    var _hit  = noone;
    with (obj_c64_node) {
        if (_hit == noone && node_type == "LABEL") {
            if (string_upper(string(instructions[0][1])) == _want) {
                _hit = id;
            }
        }
    }
    return _hit;
}

/// @desc First LABEL node not yet attached to anything, or noone.
function scr_tour_free_label() {
    var _hit = noone;
    with (obj_c64_node) {
        if (_hit == noone && node_type == "LABEL" && !is_connected && org_parent == noone) {
            _hit = id;
        }
    }
    return _hit;
}

/// @desc The main-spine JMP_ABS that jumps back to MAIN, or noone.
function scr_tour_loop_jmp() {
    var _hit = noone;
    with (obj_c64_node) {
        if (_hit == noone && is_connected && org_parent == noone && node_type == "NORMAL") {
            if (array_length(instructions) > 0) {
                if (string_lower(string(instructions[0][0])) == "jmp_abs") {
                    if (string_upper(string(instructions[0][1])) == "MAIN") {
                        _hit = id;
                    }
                }
            }
        }
    }
    return _hit;
}

/// @desc True when _n is attached between the MAIN label and its JMP.
function scr_tour_in_loop(_n) {
    if (_n == noone) {
        return false;
    }
    if (!_n.is_connected) {
        return false;
    }
    var _lbl = scr_tour_label("MAIN");
    var _jmp = scr_tour_loop_jmp();
    if (_lbl == noone || _jmp == noone) {
        return false;
    }
    return (_n.y > _lbl.y && _n.y < _jmp.y);
}

/// @desc True when _n is attached below the loop's JMP MAIN.
function scr_tour_below_loop(_n) {
    if (_n == noone) {
        return false;
    }
    if (!_n.is_connected) {
        return false;
    }
    var _jmp = scr_tour_loop_jmp();
    if (_jmp == noone) {
        return false;
    }
    return (_n.y > _jmp.y);
}

/// @desc Any connected MOVE node whose DX matches: _sign -1 negative, +1 positive.
function scr_tour_move_dx(_sign) {
    var _found = false;
    with (obj_c64_node) {
        if (is_connected && node_type == "MACRO_MOVE") {
            var _dx = instructions[0][2];
            if (is_real(_dx) || is_int64(_dx)) {
                if (_sign < 0 && _dx < 0) {
                    _found = true;
                }
                if (_sign > 0 && _dx > 0) {
                    _found = true;
                }
            }
        }
    }
    return _found;
}

/// @desc Any connected MOVE node attached below the label _name.
function scr_tour_move_after(_name) {
    var _lbl = scr_tour_label(_name);
    if (_lbl == noone) {
        return false;
    }
    if (!_lbl.is_connected) {
        return false;
    }
    var _ly    = _lbl.y;
    var _found = false;
    with (obj_c64_node) {
        if (is_connected && node_type == "MACRO_MOVE" && y > _ly) {
            _found = true;
        }
    }
    return _found;
}

/// @desc True when the keyboard node of _type has key _key switched on.
function scr_tour_key_on(_type, _key) {
    var _n = scr_tour_node_by_type(_type);
    if (_n == noone) {
        return false;
    }
    for (var _i = 1; _i < array_length(_n.instructions); _i++) {
        var _row = _n.instructions[_i];
        if (array_length(_row) >= 3) {
            if (string(_row[0]) == _key && real(_row[2]) == 1) {
                return true;
            }
        }
    }
    return false;
}

/// @desc Checks for tours 3-9. Called from scr_tour_check for codes it
///       does not handle itself; returns false for unknown codes.
function scr_tour_check_ext(_code) {
    var _n = noone;
    var _a = undefined;
    switch (_code) {
        case "ADD_OPEN_SPR":
            if (obj_asset_manager.add_dropdown_open) {
                return true;
            }
            return (scr_tour_asset_count("SPRITE_SET") > base_spr_count);
        case "SPR_ADDED":
            return (scr_tour_asset_count("SPRITE_SET") > base_spr_count);
        case "SPR_VIEW":
            return (scr_tour_viewer_type() == "SPRITE_SET");
        case "SPR_V2_OPEN":
            return obj_asset_manager.spred64_v2.active;
        case "SPR_DRAWN":
            return scr_tour_sprite_drawn();
        case "SPR_CLOSED":
            if (obj_asset_manager.spred64_v2.active) {
                return false;
            }
            return !obj_asset_manager.viewer_open;
        case "HAS_SPR":
            return (scr_tour_node_by_type("MACRO_SPR") != noone);
        case "SPR_LINKED":
            _n = scr_tour_node_by_type("MACRO_SPR");
            if (_n == noone) {
                return false;
            }
            return (string(_n.instructions[0][1]) != "");

        case "LABEL_EXISTS":
            return (scr_tour_count_type("LABEL", false) > base_label_count);
        case "LABEL_CONNECTED":
            return (scr_tour_count_type("LABEL", true) >= 1);
        case "LABEL_MAIN":
            _n = scr_tour_label("MAIN");
            if (_n == noone) {
                return false;
            }
            return _n.is_connected;
        case "HAS_VWAIT":
            return (scr_tour_node_by_type("MACRO_VWAIT") != noone);
        case "HAS_RANDOM":
            return (scr_tour_node_by_type("MACRO_RANDOM") != noone);
        case "OP_JMP":
            return (scr_tour_node_by_op("jmp_abs") != noone);
        case "JMP_MAIN":
            _n = scr_tour_label("MAIN");
            var _j = scr_tour_loop_jmp();
            if (_n == noone || _j == noone) {
                return false;
            }
            return (_n.is_connected && _n.y < _j.y);

        case "JOY_IN_LOOP":
            return scr_tour_in_loop(scr_tour_node_by_type("MACRO_JOY"));
        case "JOY_LF":
            _n = scr_tour_node_by_type("MACRO_JOY");
            if (_n == noone) {
                return false;
            }
            return (real(_n.instructions[16][2]) == 1);
        case "JOY_RT":
            _n = scr_tour_node_by_type("MACRO_JOY");
            if (_n == noone) {
                return false;
            }
            return (real(_n.instructions[17][2]) == 1);
        case "LF_BELOW":
            return scr_tour_below_loop(scr_tour_label("LF"));
        case "RT_BELOW":
            return scr_tour_below_loop(scr_tour_label("RT"));
        case "MOVE_AFTER_LF":
            return scr_tour_move_after("LF");
        case "MOVE_NEG":
            return scr_tour_move_dx(-1);
        case "MOVE_2":
            return (scr_tour_count_type("MACRO_MOVE", true) >= 2);
        case "MOVE_POS":
            return scr_tour_move_dx(1);
        case "RTS_1":
            return (scr_tour_count_op("rts", false) >= 1);
        case "RTS_2":
            return (scr_tour_count_op("rts", false) >= 2);
        case "RTS_3":
            return (scr_tour_count_op("rts", false) >= 3);

        case "KEYS_IN_LOOP":
            return scr_tour_in_loop(scr_tour_node_by_type("MACRO_LETTERS"));
        case "KEY_B_ON":
            return scr_tour_key_on("MACRO_LETTERS", "B");
        case "KEYB_BELOW":
            return scr_tour_below_loop(scr_tour_label("KEY_B"));
        case "OP_INC_ABS":
            return (scr_tour_node_by_op("inc_abs") != noone);
        case "INC_D020":
            return scr_tour_has_op_value("inc_abs", 0xD020);

        case "CLR_BEFORE_LOOP":
            _n = scr_tour_node_by_type("MACRO_CLR_SCREEN");
            var _ml = scr_tour_label("MAIN");
            if (_n == noone || _ml == noone) {
                return false;
            }
            return (_n.y < _ml.y);
        case "TXT_IN_LOOP":
            return scr_tour_in_loop(scr_tour_node_by_type("MACRO_TEXT_SCROLL"));
        case "TXT_CHANGED":
            _n = scr_tour_node_by_type("MACRO_TEXT_SCROLL");
            if (_n == noone) {
                return false;
            }
            return (string(_n.instructions[0][6]) != "HELLO WORLD ");
        case "TXT_COL":
            _n = scr_tour_node_by_type("MACRO_TEXT_SCROLL");
            if (_n == noone) {
                return false;
            }
            return (scr_tour_num(_n.instructions[0][2]) != 1);

        case "LBL_HIT":
            return (scr_tour_label("HIT") != noone);
        case "HIT_BELOW":
            return scr_tour_below_loop(scr_tour_label("HIT"));
        case "COLL_IN_LOOP":
            return scr_tour_in_loop(scr_tour_node_by_type("MACRO_COLLISION"));
        case "COLL_HIT":
            _n = scr_tour_node_by_type("MACRO_COLLISION");
            if (_n == noone) {
                return false;
            }
            return (string_upper(string(_n.instructions[0][3])) == "HIT");

        case "MUS_OPEN":
            return (scr_tour_viewer_type() == "MUSIC_MAKER");
        case "MUS_GENERATED":
            _a = scr_tour_asset_by_type("MUSIC_MAKER");
            if (is_undefined(_a)) {
                return false;
            }
            return is_struct(_a.meta[$ "music_nodes"]);
        case "MUS_CLOSED":
            return !obj_asset_manager.viewer_open;
    }
    return false;
}

/// @desc Highlight keys added for tours 3-9. Returns a GUI rect or undefined.
function scr_tour_resolve_ext(_k) {
    var _n = noone;
    if (string_copy(_k, 1, 10) == "LABELNAME:") {
        _n = scr_tour_label(string_delete(_k, 1, 10));
        if (_n != noone) {
            return scr_tour_node_rect(_n);
        }
        return undefined;
    }
    if (string_copy(_k, 1, 9) == "LASTTYPE:") {
        _n = scr_tour_last_by_type(string_delete(_k, 1, 9));
        if (_n != noone) {
            return scr_tour_node_rect(_n);
        }
        return undefined;
    }
    if (_k == "FREELABEL") {
        _n = scr_tour_free_label();
        if (_n != noone) {
            return scr_tour_node_rect(_n);
        }
        return undefined;
    }
    return undefined;
}
