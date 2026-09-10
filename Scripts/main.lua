local TAG = "[PalboxQuickBrowse]"
local VERSION = "2.1.4"


local PB_HOVER_FN = "/Game/Pal/Blueprint/UI/PalStorage/WBP_PalStorageMenu.WBP_PalStorageMenu_C:BndEvt__WBP_PalStorageMenu_WBP_IngameMenu_PalBox_K2Node_ComponentBoundEvent_1_OnHoveredBoxSlot__DelegateSignature"
local PB_SETUP_PARTY_FN = "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox.WBP_IngameMenu_PalBox_C:Setup Party Pal"


local PARTY_SET_HANDLES_FN = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Pal/WBP_MainMenu_Pal_00.WBP_MainMenu_Pal_00_C:Set Pal Handles"
local PARTY_LIST_TO_STATUS_FN = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Pal/WBP_MainMenu_Pal_00.WBP_MainMenu_Pal_00_C:ListToStatus"
local PARTY_TO_STATUS_FN = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Pal/WBP_MainMenu_Pal_00.WBP_MainMenu_Pal_00_C:AnmEvent_ToStatus_WithSetup"
local PARTY_FOCUS_PANEL_FN = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Pal/WBP_MainMenu_Pal_00.WBP_MainMenu_Pal_00_C:FocusToPalPanel"
local PARTY_SKILL_OPEN_FN = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Pal/WBP_MainMenu_Pal_00.WBP_MainMenu_Pal_00_C:OpenChangeActiveSkillList"


local STATUS_SETUP_ONE_FN = "/Game/Pal/Blueprint/UI/PalStatus/WBP_PalStatus.WBP_PalStatus_C:Setup One Pal"
local NAME_EDIT_OPEN_FN = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Pal/WBP_MainMenu_Pal_00.WBP_MainMenu_Pal_00_C:OpenNameEditWindow"
local NAME_EDIT_CLOSE_FN = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Pal/WBP_MainMenu_Pal_00.WBP_MainMenu_Pal_00_C:OnCloseNameEditWindow"
local TO_SKILL_DETAIL_FN = "/Game/Pal/Blueprint/UI/PalStatus/WBP_PalStatus.WBP_PalStatus_C:ToSkillDetail"
local TO_PARAMETER_DETAIL_FN = "/Game/Pal/Blueprint/UI/PalStatus/WBP_PalStatus.WBP_PalStatus_C:ToParameterDetail"
local CANCEL_FN = "/Game/Pal/Blueprint/UI/PalStatus/StatusPopup/WBP_PalStatusPopup.WBP_PalStatusPopup_C:OnCancelAction"
local MODEL_GET_CAMERA_FN = "/Game/Pal/Blueprint/UI/SceneCaptureWidget/WBP_PalMonsterInframeRender.WBP_PalMonsterInframeRender_C:GetCaptureCameraActor"

local VIS_VISIBLE = 0
local VIS_COLLAPSED = 1
local VIS_HIT_TEST_INVISIBLE = 3
local VIS_SELF_HIT_TEST_INVISIBLE = 4


local UI_BG = { R = 0.0, G = 0.0, B = 0.0, A = 0.68 }
local UI_BLUE = { R = 0.075, G = 0.67, B = 0.90, A = 1.0 }
local UI_WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }

local PARTY_NAV_MIN_INTERVAL_SEC = 0.12
local PB_NAV_MIN_INTERVAL_SEC = 0.08

local class_cache = {}
local vec2 = { X = 0.0, Y = 0.0 }

local hooks_ready = {
    pb_hover = false,
    pb_setup_party = false,
    status_setup_one = false,
    party_set_handles = false,
    party_list = false,
    party_to_status = false,
    party_focus_panel = false,
    party_skill_open = false,
    cancel = false,
    name_open = false,
    name_close = false,
    controller_prev = false,
    controller_next = false,
    model_get_camera = false,
}
local retry_pending = false
local hook_install_attempts = 0
local HOOK_INSTALL_MAX_ATTEMPTS = 30

local function new_ui_state()
    return {
        overlay = nil,
        root = nil,
        left_widgets = {},
        right_widgets = {},
        left_rect = { x = 0, y = 0, w = 0, h = 0 },
        right_rect = { x = 0, y = 0, w = 0, h = 0 },
    }
end


local PB = {
    palbox_container = nil,
    active_container = nil,
    context_kind = nil,
    context_container_name = nil,
    current_handle = nil,
    suppress_setup = false,
    details_open = false,
    details_popup = nil,
    popup_seen_open = false,
    nickname_editing = false,
    status_widget = nil,
    pal_panel = nil,
    capture_set = nil,
    nav_serial = 0,
    last_nav_clock = -1000.0,
    input_mode = "keyboard",
    initial_party_focus_done = {},
    ui = new_ui_state(),
}


local PT = {
    party_widget = nil,
    handles = {},
    native_slots = {},
    current_index = nil,
    current_handle = nil,
    details_open = false,
    nickname_editing = false,
    status_widget = nil,
    details_popup = nil,
    capture_set = nil,
    nav_serial = 0,
    last_nav_clock = -1000.0,
    input_mode = "keyboard",
    ui = new_ui_state(),
}

local function log(msg)
    print(string.format("%s %s\n", TAG, tostring(msg)))
end

local function valid(obj)
    if obj == nil then return false end
    local ok, value = pcall(function() return obj:IsValid() end)
    return ok and value == true
end

local function unwrap(value)
    if value == nil or valid(value) then return value end
    local t = type(value)
    if t == "boolean" or t == "number" or t == "string" then return value end
    local ok, result = pcall(function() return value:Get() end)
    return ok and result or value
end

local function full_name(obj)
    if not valid(obj) then return "" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and tostring(value or "") or ""
end

local function object_path(obj)
    local full = full_name(obj)
    local path = full:match("^%S+%s+(.+)$")
    return path or full
end

local function same_object(a, b)
    return valid(a) and valid(b) and full_name(a) == full_name(b)
end

local function belongs_to(child, parent)
    if not valid(child) or not valid(parent) then return false end
    local child_name = full_name(child)
    local parent_path = object_path(parent)
    return parent_path ~= "" and string.find(child_name, parent_path, 1, true) ~= nil
end

local function get_class(path)
    if valid(class_cache[path]) then return class_cache[path] end
    local ok, obj = pcall(StaticFindObject, path)
    if ok and valid(obj) then
        class_cache[path] = obj
        return obj
    end
    return nil
end

local function construct(path, outer)
    local class = get_class(path)
    if not valid(class) or outer == nil then return nil end
    local ok, obj = pcall(StaticConstructObject, class, outer)
    return ok and valid(obj) and obj or nil
end

local function field(obj, name)
    if not valid(obj) then return nil end
    local ok, value = pcall(function() return unwrap(obj[name]) end)
    return ok and value or nil
end

local function get_player_controller()
    if UEHelpers and type(UEHelpers.GetPlayerController) == "function" then
        local ok, pc = pcall(function() return UEHelpers:GetPlayerController() end)
        if ok and valid(pc) then return pc end
    end

    local ok, pc = pcall(FindFirstOf, "PalPlayerController")
    return ok and valid(pc) and pc or nil
end

local function get_outer(obj)
    if not valid(obj) then return nil end

    local ok, outer = pcall(function() return unwrap(obj:GetOuter()) end)
    if ok and valid(outer) then return outer end

    outer = field(obj, "OuterPrivate")
    return valid(outer) and outer or nil
end

local function find_ancestor_containing(obj, token, max_depth)
    local current = unwrap(obj)
    for _ = 1, max_depth or 12 do
        if not valid(current) then return nil end
        if string.find(full_name(current), token, 1, true) then return current end
        current = get_outer(current)
    end
    return nil
end

local function find_popup_ancestor(obj)
    return find_ancestor_containing(obj, "WBP_PalStatusPopup_C", 12)
end

local function find_status_ancestor(obj)
    return find_ancestor_containing(obj, "WBP_PalStatus_C", 12)
end

local function popup_visible(widget)
    if not valid(widget) then return false end

    local ok, visibility = pcall(function() return widget:GetVisibility() end)
    if ok then
        visibility = tonumber(unwrap(visibility))
        if visibility ~= nil then
            return visibility == VIS_VISIBLE
                or visibility == VIS_HIT_TEST_INVISIBLE
                or visibility == VIS_SELF_HIT_TEST_INVISIBLE
        end
    end

    ok, visibility = pcall(function() return widget["IsVisible"](widget) end)
    return ok and visibility == true
end

local function find_details_widget()
    local ok, popups = pcall(function() return FindAllOf("WBP_PalStatusPopup_C") end)
    if not ok or popups == nil then return nil end

    local popup = nil
    for _, obj in ipairs(popups) do
        if valid(obj) and string.find(full_name(obj), "/Engine/Transient.", 1, true) and popup_visible(obj) then
            popup = obj
            break
        end
    end
    if not valid(popup) then return nil end

    ok, popups = pcall(function() return FindAllOf("WBP_PalStatus_C") end)
    if not ok or popups == nil then return nil end

    local popup_path = object_path(popup)
    for _, obj in ipairs(popups) do
        if valid(obj) then
            local name = full_name(obj)
            if string.find(name, "/Engine/Transient.", 1, true)
                and popup_path ~= ""
                and string.find(name, popup_path, 1, true)
            then
                return obj
            end
        end
    end

    for _, obj in ipairs(popups) do
        if valid(obj) and string.find(full_name(obj), "/Engine/Transient.", 1, true) then
            return obj
        end
    end

    return nil
end

local function find_pal_panel_for_status(status)
    if not valid(status) then return nil end

    local direct = field(status, "WBP_MainMenu_Pal_00")
    if valid(direct) then return direct end

    direct = field(status, "WBP_MainMenu_Pal")
    if valid(direct) then return direct end

    local ok, panels = pcall(function() return FindAllOf("WBP_MainMenu_Pal_00_C") end)
    if not ok or panels == nil then return nil end

    for _, panel in ipairs(panels) do
        if valid(panel) and belongs_to(panel, status) then return panel end
    end

    return nil
end


local function adopt_status_authority(state, status, source)
    if type(state) ~= "table" or not valid(status) then return nil end

    local incoming_popup = find_popup_ancestor(status)
    local previous_status = state.status_widget
    local previous_popup = state.details_popup

    if valid(previous_status) and not same_object(previous_status, status) then
        local previous_visible = valid(previous_popup) and popup_visible(previous_popup)
        local incoming_visible = valid(incoming_popup) and popup_visible(incoming_popup)
        if previous_visible and not incoming_visible then
            return find_pal_panel_for_status(previous_status)
        end
    end

    local changed = not same_object(previous_status, status)
    if changed then
        state.capture_set = nil
    end

    state.status_widget = status
    state.details_popup = valid(incoming_popup) and incoming_popup or nil
    local panel = find_pal_panel_for_status(status)
    if state == PB then
        PB.pal_panel = panel
    elseif state == PT and valid(panel) then
        PT.party_widget = panel
    end

    return panel
end

local function try_capture_from_status(status)
    if not valid(status) then return nil end

    local renderer = field(status, "WBP_PalInframeRender")
    if not valid(renderer) then
        renderer = field(status, "WBP_PalMonsterInframeRender")
    end
    if not valid(renderer) then return nil end

    local ok, capture = pcall(function()
        return unwrap(renderer["GetCaptureCameraActor"](renderer))
    end)
    return ok and valid(capture) and capture or nil
end

local function pal_id_from_handle(handle)
    if not valid(handle) then return nil, nil end

    local pal_id = nil
    local pal_id_string = nil
    local ok, err = pcall(function()
        local ind = handle:TryGetIndividualParameter()
        if ind ~= nil and ind:IsValid() then
            pal_id = ind:GetCharacterID()
            if pal_id ~= nil then
                local ok_string, value = pcall(function() return pal_id:ToString() end)
                pal_id_string = ok_string and tostring(value) or tostring(pal_id)
            end
        end
    end)

    if not ok then
        log("PalID resolve error: " .. tostring(err))
        return nil, nil
    end
    return pal_id, pal_id_string
end


local function native_rebind_panel(panel, target_handle, source)
    if not valid(panel) or not valid(target_handle) then
        return false, false, false
    end

    local unbind_attempted = false
    local unbind_ok = false
    local unbind_err = nil
    local ok_get_unbind, unbind_fn = pcall(function() return panel["Unbind"] end)
    if ok_get_unbind and unbind_fn ~= nil then
        unbind_attempted = true
        local ok_unbind, err_unbind = pcall(function()
            unbind_fn(panel)
        end)
        unbind_ok = ok_unbind
        unbind_err = err_unbind
    end

    local bind_ok, bind_err = pcall(function()
        panel["BindFromHandle"](panel, target_handle)
    end)


    if unbind_attempted and not unbind_ok then
        log(source .. " Unbind error (continuing with BindFromHandle): " .. tostring(unbind_err))
    end
    if not bind_ok then
        log(source .. " BindFromHandle error: " .. tostring(bind_err))
    end

    return bind_ok, unbind_attempted, unbind_ok
end


local INTERNAL_STATUS_REFRESH = false

local function native_refresh_status(status_widget, target_handle, source)
    if not valid(status_widget) or not valid(target_handle) then
        return false
    end

    local ok, err = pcall(function()
        INTERNAL_STATUS_REFRESH = true
        status_widget["Setup One Pal"](status_widget, target_handle, true)
    end)
    INTERNAL_STATUS_REFRESH = false

    if not ok then
        log(source .. " status refresh via Setup One Pal failed: " .. tostring(err))
        return false
    end

    return true
end

local function normalized_display_text(value)
    if value == nil or type(value) == "boolean" then return nil end

    local function clean(candidate)
        if type(candidate) ~= "string" then return nil end
        candidate = candidate:gsub("^%s+", ""):gsub("%s+$", "")
        if candidate == "" or candidate == "None" or candidate == "nil" then return nil end
        if candidate:match("^FText[%s:]") or candidate:match("^RemoteUnrealParam[%s:]") then
            return nil
        end
        return candidate
    end

    local text = clean(value)
    if text ~= nil then return text end

    local ok, converted = pcall(function() return value:GetDisplayString() end)
    text = ok and clean(converted) or nil
    if text ~= nil then return text end

    ok, converted = pcall(function() return value:ToString() end)
    text = ok and clean(converted) or nil
    if text ~= nil then return text end

    local unwrapped = unwrap(value)
    text = clean(unwrapped)
    if text ~= nil then return text end

    if unwrapped ~= value and unwrapped ~= nil then
        ok, converted = pcall(function() return unwrapped:GetDisplayString() end)
        text = ok and clean(converted) or nil
        if text ~= nil then return text end

        ok, converted = pcall(function() return unwrapped:ToString() end)
        text = ok and clean(converted) or nil
        if text ~= nil then return text end
    end

    return nil
end

local function partner_skill_name_for_pal(pal_id, world_context)
    if pal_id == nil or not valid(world_context) then
        return nil, "missing PalID/world context"
    end

    local ui = get_class("/Script/Pal.Default__PalUIUtility")
    if not valid(ui) then return nil, "PalUIUtility unavailable" end

    local out = {}
    local ok, first, second, third = pcall(function()
        return ui:GetPartnerSkillName(world_context, pal_id, out)
    end)
    if not ok then return nil, "GetPartnerSkillName error: " .. tostring(first) end

    local function first_text(...)
        for index = 1, select("#", ...) do
            local text = normalized_display_text(select(index, ...))
            if text ~= nil then return text end
        end
        return nil
    end

    local text = first_text(first, second, third)
    if text ~= nil then return text, nil end
    for _, value in pairs(out) do
        text = normalized_display_text(value)
        if text ~= nil then return text, nil end
    end

    return nil, "localized Partner Skill name unavailable"
end

local function find_widget_descendant(root, wanted_name)
    root = unwrap(root)
    if not valid(root) or type(wanted_name) ~= "string" then return nil end

    local stack = { root }
    local visited = {}
    local inspected = 0
    while #stack > 0 and inspected < 256 do
        local widget = unwrap(table.remove(stack))
        if valid(widget) then
            local identity = full_name(widget)
            if identity == "" or not visited[identity] then
                if identity ~= "" then visited[identity] = true end
                inspected = inspected + 1

                local ok_name, object_name = pcall(function()
                    return widget:GetFName():ToString()
                end)
                object_name = ok_name and tostring(object_name or "") or ""
                if object_name == wanted_name
                    or object_name:match("^" .. wanted_name .. "_") then
                    return widget
                end

                local ok_count, count = pcall(function()
                    return widget:GetChildrenCount()
                end)
                if ok_count and type(count) == "number" and count > 0 then
                    for index = count - 1, 0, -1 do
                        local ok_child, child = pcall(function()
                            return unwrap(widget:GetChildAt(index))
                        end)
                        if ok_child and valid(child) then stack[#stack + 1] = child end
                    end
                end
            end
        end
    end

    return nil
end

local function widget_tree_root(owner)
    if not valid(owner) then return nil, nil end
    local tree = field(owner, "WidgetTree")
    if not valid(tree) then return nil, nil end

    local root = field(tree, "RootWidget")
    if valid(root) then return root, tree end

    return nil, tree
end

local function find_widget_tree_descendant(owner, wanted_name)
    local root = widget_tree_root(owner)
    if not valid(root) then return nil end
    return find_widget_descendant(root, wanted_name)
end


local function find_named_widget(owner, name)
    if not valid(owner) or type(name) ~= "string" then return nil, "none" end

    local tree_descendant = find_widget_tree_descendant(owner, name)
    if valid(tree_descendant) then return tree_descendant, "WidgetTree" end

    local direct = field(owner, name)
    if valid(direct) then return direct, "field" end

    local key = nil
    if FName ~= nil then
        local ok_name, value = pcall(FName, name)
        if ok_name then key = value end
    end

    if key ~= nil then
        local tree = field(owner, "WidgetTree")
        if valid(tree) then
            local ok, found = pcall(function() return unwrap(tree:FindWidget(key)) end)
            if ok and valid(found) then return found, "WidgetTree.FindWidget" end
        end

        local ok, found = pcall(function() return unwrap(owner:GetWidgetFromName(key)) end)
        if ok and valid(found) then return found, "GetWidgetFromName" end
    end

    local descendant = find_widget_descendant(owner, name)
    if valid(descendant) then return descendant, "owner-descendant" end
    return nil, "none"
end

local function refresh_partner_skill_name(panel, status_widget, pal_id)
    if not valid(panel) or pal_id == nil then return false end

    local context = valid(status_widget) and status_widget or panel
    local name = partner_skill_name_for_pal(pal_id, context)
    if name == nil then return false end

    local rich_widget = find_named_widget(panel, "RichText_PartnerSkillName")
    local plain_widget = find_named_widget(panel, "Text_PartnerSkillName_1")
    if not valid(rich_widget) and not valid(plain_widget) then return false end

    local ok_text, text_value = pcall(FText, name)
    if not ok_text or text_value == nil then return false end

    local rich_verified = false
    local plain_verified = false

    if valid(rich_widget) then
        local ok_set = pcall(function() rich_widget:SetText(text_value) end)
        if ok_set then
            local ok_get, value = pcall(function() return rich_widget:GetText() end)
            rich_verified = ok_get and normalized_display_text(value) == name
        end
    end

    if valid(plain_widget) then
        local ok_set = pcall(function() plain_widget:SetText(text_value) end)
        if ok_set then
            local ok_get, value = pcall(function() return plain_widget:GetText() end)
            plain_verified = ok_get and normalized_display_text(value) == name
        end
    end

    return rich_verified or plain_verified
end

local function refresh_target(state, target_handle, source)
    local pal_id = pal_id_from_handle(target_handle)
    if pal_id == nil then return false, false, false end

    local panel = state.pal_panel
    if not valid(panel) and state == PT then
        panel = PT.party_widget
    end
    if not valid(panel) and valid(state.status_widget) then
        panel = find_pal_panel_for_status(state.status_widget)
        if state == PB then PB.pal_panel = panel end
    end

    local lock_ok = false
    local icon_ok = false
    local name_ok = false
    if valid(panel) then
        lock_ok = pcall(function()
            panel["SetPartnerSkillLock"](panel, pal_id)
        end)
        icon_ok = pcall(function()
            panel["SetPartnerSkillIcon"](panel, pal_id)
        end)
        name_ok = refresh_partner_skill_name(panel, state.status_widget, pal_id)
    end

    local capture = state.capture_set
    if not valid(capture) and valid(state.status_widget) then
        capture = try_capture_from_status(state.status_widget)
        if valid(capture) then state.capture_set = capture end
    end


    if not valid(capture) and state.details_open then
        local ok_find, found = pcall(function()
            return FindFirstOf("BP_PalMonsterCaptureSet_C")
        end)
        if ok_find and valid(found) then
            capture = found
            state.capture_set = found
        end
    end

    local capture_ok = false
    if valid(capture) then
        capture_ok = pcall(function()
            capture["RequestCaptureFromPalID"](capture, pal_id)
        end)
    end

    return lock_ok, icon_ok, name_ok, capture_ok
end


local function set_position(slot, x, y)
    if slot == nil then return end
    vec2.X, vec2.Y = x, y
    pcall(function() slot:SetPosition(vec2) end)
end

local function set_size(slot, w, h)
    if slot == nil then return end
    vec2.X, vec2.Y = w, h
    pcall(function() slot:SetSize(vec2) end)
end

local function add_to_canvas(canvas, child)
    if not valid(canvas) or not valid(child) then return nil end
    local ok, slot = pcall(function() return canvas:AddChildToCanvas(child) end)
    if not ok or slot == nil then return nil end
    pcall(function() slot:SetAutoSize(false) end)
    return slot
end

local function set_text(widget, value)
    local ok, text = pcall(FText, value)
    if ok and text ~= nil then
        pcall(function() widget:SetText(text) end)
    end
end

local function set_text_color(widget, color)
    if not valid(widget) or color == nil then return end

    local ok = pcall(function()
        widget:SetColorAndOpacity({
            SpecifiedColor = {
                R = color.R,
                G = color.G,
                B = color.B,
                A = color.A,
            }
        })
    end)
    if ok then return end

    pcall(function()
        local slate = widget.ColorAndOpacity
        slate.SpecifiedColor.R = color.R
        slate.SpecifiedColor.G = color.G
        slate.SpecifiedColor.B = color.B
        slate.SpecifiedColor.A = color.A
        widget.ColorAndOpacity = slate
    end)
end

local function controller_labels()
    local left, right = "LT", "RT"
    local ok, input = pcall(function() return FindFirstOf("CommonInputSubsystem") end)
    if not ok or not valid(input) then return left, right end

    local names = {}
    local ok_name, name = pcall(function() return unwrap(input:GetCurrentGamepadName()) end)
    if ok_name and name ~= nil then names[#names + 1] = tostring(name) end

    ok_name, name = pcall(function() return unwrap(input:GetCurrentInputTypeName()) end)
    if ok_name and name ~= nil then names[#names + 1] = tostring(name) end

    local joined = string.lower(table.concat(names, " "))
    if string.find(joined, "playstation", 1, true)
        or string.find(joined, "dualsense", 1, true)
        or string.find(joined, "dualshock", 1, true)
        or string.find(joined, "ps4", 1, true)
        or string.find(joined, "ps5", 1, true)
    then
        return "L2", "R2"
    end

    return left, right
end

local function detect_input_mode(fallback)
    local ok, input = pcall(function() return FindFirstOf("CommonInputSubsystem") end)
    if not ok or not valid(input) then return fallback or "keyboard" end

    ok, input = pcall(function() return unwrap(input:GetCurrentInputType()) end)
    if not ok then return fallback or "keyboard" end
    return tonumber(input) == 0 and "keyboard" or "controller"
end

local function ui_update_labels(state, mode)
    state.input_mode = mode
    local left, right = "A", "D"
    if mode == "controller" then
        left, right = controller_labels()
    end

    local left_label = state.ui.left_widgets.control_label
    local right_label = state.ui.right_widgets.control_label

    if valid(left_label) then set_text(left_label, left) end
    if valid(right_label) then set_text(right_label, right) end
end

local function ui_set_control_visible(widgets, visible)
    local visibility = visible and VIS_HIT_TEST_INVISIBLE or VIS_COLLAPSED
    for _, widget in ipairs(widgets) do
        if valid(widget) then
            pcall(function() widget:SetVisibility(visibility) end)
        end
    end
end

local function ui_set_visible(state, visible)
    local ui = state.ui
    local visibility = visible and VIS_SELF_HIT_TEST_INVISIBLE or VIS_COLLAPSED
    if valid(ui.overlay) then pcall(function() ui.overlay:SetVisibility(visibility) end) end
    if valid(ui.root) then pcall(function() ui.root:SetVisibility(visibility) end) end

    if not visible then
        ui_set_control_visible(ui.left_widgets, false)
        ui_set_control_visible(ui.right_widgets, false)
    end
end

local function viewport_size(pc)
    local library = get_class("/Script/UMG.Default__WidgetLayoutLibrary")
    if not valid(library) then return 1920, 1080 end

    local ok, size = pcall(function() return library:GetViewportSize(pc) end)
    if not ok or size == nil then return 1920, 1080 end

    local x, y
    ok, x, y = pcall(function() return tonumber(size.X), tonumber(size.Y) end)
    if ok and x and y and x > 0 and y > 0 then return x, y end
    return 1920, 1080
end

local function ui_update_rects(state, pc)
    local w, h = viewport_size(pc)
    local bw = math.max(66, math.floor(w * 0.038))
    local bh = math.max(126, math.floor(h * 0.145))
    local margin = math.max(6, math.floor(w * 0.006))
    local y = math.floor((h - bh) / 2)

    local l = state.ui.left_rect
    local r = state.ui.right_rect
    l.x, l.y, l.w, l.h = margin, y, bw, bh
    r.x, r.y, r.w, r.h = w - margin - bw, y, bw, bh
end

local function add_control(tree, root, rect, letter, arrow)
    local widgets = {}


    local outer_rim = math.max(2, math.floor(math.min(rect.w, rect.h) * 0.025))
    local line = math.max(2, math.floor(math.min(rect.w, rect.h) * 0.020))

    local bg = construct("/Script/UMG.Border", tree)
    if not valid(bg) then return nil end

    local slot = add_to_canvas(root, bg)
    if slot == nil then return nil end
    set_position(slot, rect.x, rect.y)
    set_size(slot, rect.w, rect.h)
    pcall(function()
        bg:SetBrushColor(UI_BG)
        bg:SetVisibility(VIS_HIT_TEST_INVISIBLE)
    end)
    widgets[#widgets + 1] = bg

    local function add_blue_strip(x, y, w, h)
        local strip = construct("/Script/UMG.Border", tree)
        if not valid(strip) then return end
        local s = add_to_canvas(root, strip)
        if s == nil then return end
        set_position(s, x, y)
        set_size(s, w, h)
        pcall(function()
            strip:SetBrushColor(UI_BLUE)
            strip:SetVisibility(VIS_HIT_TEST_INVISIBLE)
        end)
        widgets[#widgets + 1] = strip
    end


    local bx = rect.x + outer_rim
    local by = rect.y + outer_rim
    local bw = rect.w - (outer_rim * 2)
    local bh = rect.h - (outer_rim * 2)

    add_blue_strip(bx, by, bw, line)
    add_blue_strip(bx, by + bh - line, bw, line)
    add_blue_strip(bx, by + line, line, bh - (line * 2))
    add_blue_strip(bx + bw - line, by + line, line, bh - (line * 2))


    local control_label = construct("/Script/UMG.TextBlock", tree)
    if valid(control_label) then
        slot = add_to_canvas(root, control_label)
        if slot ~= nil then
            set_position(slot, rect.x + 2, rect.y + math.floor(rect.h * 0.08))
            set_size(slot, rect.w - 4, math.floor(rect.h * 0.27))
            set_text(control_label, letter)
            set_text_color(control_label, UI_WHITE)
            pcall(function()
                local font = control_label.Font
                font.Size = math.max(16, math.floor(rect.h * 0.14))
                control_label:SetFont(font)
                control_label:SetJustification(1)
                control_label:SetVisibility(VIS_HIT_TEST_INVISIBLE)
            end)
            widgets[#widgets + 1] = control_label
            widgets.control_label = control_label
        end
    end


    local arrow_label = construct("/Script/UMG.TextBlock", tree)
    if valid(arrow_label) then
        slot = add_to_canvas(root, arrow_label)
        if slot ~= nil then
            set_position(slot, rect.x, rect.y + math.floor(rect.h * 0.30))
            set_size(slot, rect.w, math.floor(rect.h * 0.55))
            set_text(arrow_label, arrow)
            set_text_color(arrow_label, UI_BLUE)
            pcall(function()
                local font = arrow_label.Font
                font.Size = math.max(34, math.floor(rect.h * 0.35))
                arrow_label:SetFont(font)
                arrow_label:SetJustification(1)
                arrow_label:SetVisibility(VIS_HIT_TEST_INVISIBLE)
            end)
            widgets[#widgets + 1] = arrow_label
            widgets.arrow_label = arrow_label
        end
    end

    return widgets
end

local function ui_build(state)
    if valid(state.ui.overlay) then return true end

    local pc = get_player_controller()
    if not valid(pc) then return false end

    local widget_library = get_class("/Script/UMG.Default__WidgetBlueprintLibrary")
    local user_widget_class = get_class("/Script/UMG.UserWidget")
    if not valid(widget_library) or not valid(user_widget_class) then return false end

    local world
    pcall(function() world = pc:GetWorld() end)
    if world == nil then return false end

    local ok, widget = pcall(function()
        return widget_library:Create(world, user_widget_class, pc)
    end)
    if not ok or not valid(widget) then return false end

    local tree
    pcall(function() tree = widget.WidgetTree end)
    if tree == nil then return false end

    local root = construct("/Script/UMG.CanvasPanel", tree)
    if not valid(root) then return false end
    if not pcall(function() tree.RootWidget = root end) then return false end

    state.ui.overlay, state.ui.root = widget, root
    pcall(function() root:SetVisibility(VIS_SELF_HIT_TEST_INVISIBLE) end)

    ui_update_rects(state, pc)
    local left_label, right_label = "A", "D"
    if state.input_mode == "controller" then
        left_label, right_label = controller_labels()
    end

    state.ui.left_widgets = add_control(tree, root, state.ui.left_rect, left_label, "←") or {}
    state.ui.right_widgets = add_control(tree, root, state.ui.right_rect, right_label, "→") or {}

    if not pcall(function() widget:AddToViewport(80) end) then
        state.ui.overlay, state.ui.root = nil, nil
        return false
    end

    pcall(function() widget:SetVisibility(VIS_SELF_HIT_TEST_INVISIBLE) end)
    ui_set_visible(state, false)
    return true
end

local function mouse_position()
    local pc = get_player_controller()
    local library = get_class("/Script/UMG.Default__WidgetLayoutLibrary")
    if not valid(pc) or not valid(library) then return nil, nil end

    local ok, pos = pcall(function() return library:GetMousePositionOnViewport(pc) end)
    if not ok or pos == nil then return nil, nil end

    local x, y
    ok, x, y = pcall(function() return tonumber(pos.X), tonumber(pos.Y) end)
    return ok and x or nil, ok and y or nil
end

local function inside(x, y, rect)
    return x ~= nil and y ~= nil
        and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end


local function pb_expanded_party_capacity()
    local pc = get_player_controller()
    if not valid(pc) then return nil end

    local holder = field(pc, "BP_OtomoPalHolderComponent")
    if not valid(holder) then return nil end

    local ok, total = pcall(function()
        return tonumber(unwrap(holder:GetMaxOtomoNum()))
    end)
    return ok and total or nil
end

local function pb_focus_key(widget)
    if not valid(widget) then return nil end
    local name = full_name(widget)
    return name ~= "" and name or nil
end

local function pb_native_focus_to_party_top(palbox_widget)
    if not valid(palbox_widget) then return false end
    if detect_input_mode("keyboard") ~= "controller" then return false end

    local total = pb_expanded_party_capacity()
    if not total or total <= 5 then return false end

    local key = pb_focus_key(palbox_widget)
    if key == nil or PB.initial_party_focus_done[key] then return false end

    local ok, err = pcall(function()
        palbox_widget["FocusToPartyTopSlot"](palbox_widget)
    end)

    if not ok then
        log("Expanded Palbox FocusToPartyTopSlot failed: " .. tostring(err))
        return false
    end

    PB.initial_party_focus_done[key] = true
    return true
end

local function pb_schedule_native_party_focus(palbox_widget)
    local target = unwrap(palbox_widget)
    if not valid(target) then return end

    local total = pb_expanded_party_capacity()
    if not total or total <= 5 then return end
    if detect_input_mode("keyboard") ~= "controller" then return end

    local key = pb_focus_key(target)
    if key == nil or PB.initial_party_focus_done[key] then return end


    local callback = function()
        if valid(target) then
            pb_native_focus_to_party_top(target)
        end
    end

    if type(ExecuteInGameThreadWithDelay) == "function" then
        ExecuteInGameThreadWithDelay(350, callback)
    else
        ExecuteWithDelay(350, function()
            local method = nil
            pcall(function()
                if EGameThreadMethod ~= nil then
                    method = EGameThreadMethod.ProcessEvent
                end
            end)

            if method ~= nil then
                local ok = pcall(function()
                    ExecuteInGameThread(callback, method)
                end)
                if ok then return end
            end

            pcall(function() ExecuteInGameThread(callback) end)
        end)
    end
end


local function slot_index(slot)
    if not valid(slot) then return nil end
    local ok, value = pcall(function() return slot.SlotIndex end)
    return ok and type(value) == "number" and value or nil
end

local function slot_handle(slot)
    if not valid(slot) then return nil end
    local ok, value = pcall(function() return slot.Handle end)
    return ok and valid(value) and value or nil
end

local function container_num(container)
    if not valid(container) then return nil end
    local ok, value = pcall(function() return container["Num"](container) end)
    if not ok then return nil end
    value = unwrap(value)
    return type(value) == "number" and value or nil
end

local function container_get(container, index)
    if not valid(container) then return nil end
    local ok, value = pcall(function() return container["Get"](container, index) end)
    return ok and unwrap(value) or nil
end

local function container_find(container, handle)
    if not valid(container) or not valid(handle) then return nil end
    local ok, value = pcall(function() return container["FindByHandle"](container, handle) end)
    return ok and unwrap(value) or nil
end

local function pb_find_container(handle)
    if not valid(handle) then return nil end

    if valid(PB.active_container) and valid(container_find(PB.active_container, handle)) then
        return PB.active_container
    end

    if valid(PB.palbox_container) and valid(container_find(PB.palbox_container, handle)) then
        return PB.palbox_container
    end

    local ok, containers = pcall(function() return FindAllOf("PalIndividualCharacterContainer") end)
    if not ok or containers == nil then return nil end

    for _, container in ipairs(containers) do
        if valid(container) and valid(container_find(container, handle)) then
            return container
        end
    end

    return nil
end

local function pb_container_has_base_signature(container)
    local current = container
    for _ = 1, 10 do
        if not valid(current) then break end
        local name = string.lower(full_name(current))
        if string.find(name, "basecamp", 1, true)
            or string.find(name, "base_camp", 1, true)
            or string.find(name, "base camp", 1, true) then
            return true
        end
        current = get_outer(current)
    end
    return false
end

local function pb_context_kind(container)
    if not valid(container) then return "unknown" end
    if valid(PB.palbox_container) and same_object(container, PB.palbox_container) then
        return "palbox"
    end
    if pb_container_has_base_signature(container) then
        return "base"
    end
    if valid(PB.palbox_container) then
        return "base"
    end
    return "other"
end

local function pb_log_context(container, reason, handle)
    if not valid(container) then return "unknown" end
    local kind = pb_context_kind(container)
    local name = full_name(container)
    local changed = kind ~= PB.context_kind or name ~= PB.context_container_name
    PB.context_kind = kind
    PB.context_container_name = name

    return kind
end

local function pb_resolve_current_slot()
    PB.active_container = pb_find_container(PB.current_handle)
    if not valid(PB.active_container) then return nil end
    pb_log_context(PB.active_container, "resolve", PB.current_handle)

    local slot = container_find(PB.active_container, PB.current_handle)
    if valid(slot) then return slot end

    local count = container_num(PB.active_container)
    if count == nil then return nil end

    for i = 0, count - 1 do
        slot = container_get(PB.active_container, i)
        if same_object(slot_handle(slot), PB.current_handle) then return slot end
    end

    return nil
end

local function pb_find_neighbor(index, direction)
    local count = container_num(PB.active_container)
    if count == nil then return nil end

    for i = index + direction, direction > 0 and count - 1 or 0, direction do
        local slot = container_get(PB.active_container, i)
        if valid(slot) and valid(slot_handle(slot)) then return slot end
    end

    return nil
end

-- Generic Pal-search API. Providers publish only the current filtered Pal
-- and its two native-storage neighbors. Shared values are primitives, never UObjects.
local API_PREFIX = "PalboxQuickBrowse.API."
local function api_read(key)
    local ok, value = pcall(function() return ModRef:GetSharedVariable(API_PREFIX .. key) end)
    return ok and value or nil
end
local function api_write(key, value)
    return pcall(function() ModRef:SetSharedVariable(API_PREFIX .. key, value) end)
end
api_write("Version", 1)

local function api_integer(value)
    return type(value) == "number" and value >= 0 and value < 2147483647
        and value == math.floor(value)
end

local function api_storage()
    local utility = get_class("/Script/Pal.Default__PalUtility")
    local pc = get_player_controller()
    if not valid(utility) or not valid(pc) then return nil end
    local ok, storage = pcall(function()
        local data = unwrap(utility:GetPlayerDataStorage(pc))
        return unwrap(data:GetPalStorage())
    end)
    return ok and valid(storage) and storage or nil
end

local function api_resolve(storage, page, index, identity)
    if not api_integer(page) or not api_integer(index)
        or type(identity) ~= "string" or identity == "" then return nil end
    local ok, first, second = pcall(function() return storage:GetSlotsInPage(page) end)
    local slots = ok and unwrap(first or second) or nil
    if slots == nil then
        local out = {}
        ok = pcall(function() storage:GetSlotsInPage(page, out) end)
        if ok then slots = out end
    end
    if slots == nil then return nil end
    for _, candidate in ipairs({ index, index - 1 }) do
        local read_ok, slot = pcall(function() return unwrap(slots[candidate]) end)
        local handle = read_ok and slot_handle(slot) or nil
        if valid(handle) and full_name(handle) == identity then return handle end
    end
    return nil
end

local function api_context()
    local provider = api_read("ActiveProvider")
    if type(provider) ~= "string" or not provider:match("^[%w_-]+$") then return nil end
    local prefix = provider .. "."
    local current = api_read(prefix .. "Current")
    if type(current) ~= "string" or current == ""
        or current ~= full_name(PB.current_handle) then return nil end

    local values = {}
    for _, side in ipairs({ "Previous", "Next" }) do
        values[side .. "Page"] = api_read(prefix .. side .. "Page")
        values[side .. "Slot"] = api_read(prefix .. side .. "Slot")
        values[side .. "Handle"] = api_read(prefix .. side .. "Handle")
    end
    if current ~= api_read(prefix .. "Current")
        or provider ~= api_read("ActiveProvider") then return nil end

    local storage = api_storage()
    if not valid(storage) then return nil end
    local context = { provider = provider }
    for _, side in ipairs({ "Previous", "Next" }) do
        local page = values[side .. "Page"]
        local index = values[side .. "Slot"]
        local identity = values[side .. "Handle"]
        if page == -1 and index == -1 and identity == "" then
            context[side] = false 
        else
            local handle = api_resolve(storage, page, index, identity)
            if not valid(handle) or same_object(handle, PB.current_handle) then return nil end
            context[side] = handle
        end
    end
    return context
end

local function api_clear_active()
    if type(api_read("ActiveProvider")) == "string" then
        api_write("ActiveProvider", "")
    end
end

local function pb_target_handle(index, direction)
    local context = api_context()
    if context ~= nil then return context[direction < 0 and "Previous" or "Next"] end
    return slot_handle(pb_find_neighbor(index, direction))
end

local pb_update_control_visibility

local function pb_close_details()
    api_clear_active()
    PB.details_open = false
    PB.details_popup = nil
    PB.popup_seen_open = false
    PB.nickname_editing = false
    PB.active_container = nil
    PB.context_kind = nil
    PB.context_container_name = nil
    PB.current_handle = nil
    PB.suppress_setup = false
    PB.status_widget = nil
    PB.pal_panel = nil
    PB.capture_set = nil
    PB.nav_serial = PB.nav_serial + 1
    ui_set_visible(PB, false)
end

pb_update_control_visibility = function()
    if not PB.details_open or not valid(PB.current_handle) then
        ui_set_control_visible(PB.ui.left_widgets, false)
        ui_set_control_visible(PB.ui.right_widgets, false)
        return
    end

    local current_slot = pb_resolve_current_slot()
    if not valid(current_slot) then
        ui_set_control_visible(PB.ui.left_widgets, false)
        ui_set_control_visible(PB.ui.right_widgets, false)
        return
    end

    local index = slot_index(current_slot)
    if index == nil then
        ui_set_control_visible(PB.ui.left_widgets, false)
        ui_set_control_visible(PB.ui.right_widgets, false)
        return
    end

    ui_set_control_visible(PB.ui.left_widgets, valid(pb_target_handle(index, -1)))
    ui_set_control_visible(PB.ui.right_widgets, valid(pb_target_handle(index, 1)))
end

local function pb_navigate(direction)
    if not PB.details_open or not valid(PB.current_handle) or PB.nickname_editing then return false end

    local now = os.clock()
    if now - PB.last_nav_clock < PB_NAV_MIN_INTERVAL_SEC then return true end
    PB.last_nav_clock = now

    local current_slot = pb_resolve_current_slot()
    if not valid(current_slot) then
        log("PB navigation failed: source container not found")
        return false
    end

    local index = slot_index(current_slot)
    if index == nil then return false end

    local target_handle = pb_target_handle(index, direction)
    if not valid(target_handle) then return false end



    local widget = PB.status_widget
    if not valid(widget) then
        log("PB navigation failed: Details widget unavailable")
        return false
    end

    PB.nav_serial = PB.nav_serial + 1
    local serial = PB.nav_serial


    local panel = valid(PB.pal_panel) and PB.pal_panel or find_pal_panel_for_status(widget)
    PB.pal_panel = panel


    local bind_ok = false
    if valid(panel) then
        bind_ok = native_rebind_panel(
            panel, target_handle,
            pb_context_kind(PB.active_container) == "base" and "BP" or "PB")
        if not bind_ok then
            log("PB native rebind failed; falling back to Setup One Pal")
        end
    end

    if not bind_ok then
        local ok_setup, setup_err = pcall(function()
            PB.suppress_setup = true
            widget["Setup One Pal"](widget, target_handle, true)
        end)

        PB.suppress_setup = false

        if not ok_setup then
            log("PB navigation failed on both bind paths: " .. tostring(setup_err))
            return false
        end
    else
        native_refresh_status(widget, target_handle, "PB")
    end

    if serial ~= PB.nav_serial then return true end

    PB.current_handle = target_handle
    PB.status_widget = widget
    PB.pal_panel = valid(PB.pal_panel) and PB.pal_panel or find_pal_panel_for_status(widget)

    local context_kind = pb_context_kind(PB.active_container)
    refresh_target(PB, target_handle, context_kind == "base" and "BP" or "PB")
    pb_update_control_visibility()
    return true
end


local function party_handle_key(handle)
    return valid(handle) and full_name(handle) or ""
end

local function party_parameter_identity(handle)
    if not valid(handle) then return nil end
    local ok, first, second = pcall(function()
        return handle:TryGetIndividualParameter()
    end)
    if not ok then return nil end

    local parameter = unwrap(first)
    if not valid(parameter) then parameter = unwrap(second) end
    if not valid(parameter) then return nil end

    local ok_address, address = pcall(function() return parameter:GetAddress() end)
    if ok_address and type(address) == "number" and address ~= 0 then
        return "addr:" .. tostring(address)
    end

    local name = full_name(parameter)
    if name ~= "" then return "name:" .. name end
    return nil
end

local function party_same_individual(a, b)
    if not valid(a) or not valid(b) then return false end
    local a_id = party_parameter_identity(a)
    local b_id = party_parameter_identity(b)
    if a_id ~= nil and b_id ~= nil then return a_id == b_id end
    return party_handle_key(a) == party_handle_key(b)
end

local function party_owner_controller(widget)
    if valid(widget) then
        local ok, pc = pcall(function() return unwrap(widget:GetOwningPlayer()) end)
        if ok and valid(pc) then return pc end

        local player_context = field(widget, "PlayerContext")
        if valid(player_context) then
            local pc2 = field(player_context, "PlayerController")
            if valid(pc2) then return pc2 end
        end
    end
    return get_player_controller()
end

local function party_holder(widget)
    local pc = party_owner_controller(widget)
    if not valid(pc) then return nil end
    local holder = field(pc, "BP_OtomoPalHolderComponent")
    return valid(holder) and holder or nil
end

local function party_find_index(handle)
    if not valid(handle) then return nil end
    for i, h in ipairs(PT.handles) do
        if party_same_individual(h, handle) then return i end
    end
    return nil
end

local function party_refresh_native_roster(reason)
    local holder = party_holder(PT.party_widget)
    if not valid(holder) then
        log("PT roster unavailable: no holder (" .. tostring(reason) .. ")")
        return false
    end

    local ok_total, total = pcall(function()
        return tonumber(unwrap(holder:GetMaxOtomoNum()))
    end)
    if not ok_total or not total or total < 1 then
        log("PT roster unavailable: bad capacity (" .. tostring(reason) .. ")")
        return false
    end

    local current_handle = PT.current_handle

    local handles = {}
    local native_slots = {}
    for native_slot = 0, total - 1 do
        local ok_handle, handle = pcall(function()
            return unwrap(holder:GetOtomoIndividualHandle(native_slot))
        end)
        if ok_handle and valid(handle) then
            handles[#handles + 1] = handle
            native_slots[#native_slots + 1] = native_slot
        end
    end

    if #handles < 1 then
        log("PT roster empty capacity=" .. tostring(total))
        return false
    end

    PT.handles = handles
    PT.native_slots = native_slots
    PT.current_index = nil

    if valid(current_handle) then
        for i, handle in ipairs(PT.handles) do
            if party_same_individual(handle, current_handle) then
                PT.current_index = i
                PT.current_handle = handle
                break
            end
        end
    end

    return true
end

local party_update_control_visibility

local function party_leave_details()
    PT.details_open = false
    PT.current_index = nil
    PT.current_handle = nil
    PT.nickname_editing = false
    PT.status_widget = nil
    PT.details_popup = nil
    PT.capture_set = nil
    PT.nav_serial = PT.nav_serial + 1
    ui_set_visible(PT, false)
end

local function party_begin_session(context)
    local ctx = unwrap(context)
    if valid(ctx) then PT.party_widget = ctx end

    PT.handles = {}
    PT.native_slots = {}
    PT.current_index = nil
    PT.current_handle = nil
    PT.details_open = false
    PT.nickname_editing = false
    PT.status_widget = nil
    PT.details_popup = nil
    PT.capture_set = nil
    PT.nav_serial = PT.nav_serial + 1
    ui_set_visible(PT, false)

    party_refresh_native_roster("session_begin")
end

local function party_enter_details(context, handle, source)
    local ctx = unwrap(context)
    local target = unwrap(handle)

    if valid(ctx) then PT.party_widget = ctx end
    if not valid(target) then return end

    party_refresh_native_roster("enter_details")
    local idx = party_find_index(target)
    if idx == nil then
        log("PT " .. tostring(source) .. " target not found in native Party roster")
        return
    end


    if PB.details_open then pb_close_details() end

    PT.current_index = idx
    PT.current_handle = target
    PT.details_open = true
    PT.nickname_editing = false
    local entered_status = find_status_ancestor(PT.party_widget)
    if not valid(entered_status) then entered_status = find_details_widget() end
    if valid(entered_status) then
        adopt_status_authority(PT, entered_status, "PT " .. tostring(source or "enter_details"))
    end

    PT.input_mode = detect_input_mode(PT.input_mode)
    if not valid(PT.ui.overlay) then ui_build(PT) end
    ui_update_labels(PT, PT.input_mode)
    ui_set_visible(PT, true)
    party_update_control_visibility()

end

party_update_control_visibility = function()
    if not PT.details_open or PT.current_index == nil then
        ui_set_control_visible(PT.ui.left_widgets, false)
        ui_set_control_visible(PT.ui.right_widgets, false)
        return
    end

    ui_set_control_visible(PT.ui.left_widgets, PT.current_index > 1)
    ui_set_control_visible(PT.ui.right_widgets, PT.current_index < #PT.handles)
end


local function party_sync_cached_handle(panel, handle, source)
    if not valid(panel) or not valid(handle) then return false end

    local label = tostring(source or "PT")
    local ok, err = pcall(function()
        panel.CachedIndividualHandle = handle
    end)
    if not ok then
        log(label .. " CachedIndividualHandle write failed: " .. tostring(err))
        return false
    end

    local current = nil
    pcall(function() current = unwrap(panel.CachedIndividualHandle) end)
    if not valid(current) or not same_object(current, handle) then
        log(label .. " CachedIndividualHandle sync failed")
        return false
    end
    return true
end

local function party_navigate(direction)
    if not PT.details_open or PT.nickname_editing then return false end

    local now = os.clock()
    if now - PT.last_nav_clock < PARTY_NAV_MIN_INTERVAL_SEC then return true end
    PT.last_nav_clock = now

    party_refresh_native_roster("navigate")

    if PT.current_index == nil and valid(PT.current_handle) then
        PT.current_index = party_find_index(PT.current_handle)
    end
    if PT.current_index == nil then
        log("PT navigation failed: current Party index unavailable")
        return false
    end

    local target_index = PT.current_index + direction
    if target_index < 1 or target_index > #PT.handles then
        party_update_control_visibility()
        return false
    end

    local target_handle = PT.handles[target_index]
    if not valid(target_handle) then
        log("PT navigation failed: target unavailable")
        return false
    end


    local bind_widget = PT.party_widget
    if not valid(bind_widget) and valid(PT.status_widget) then
        bind_widget = find_pal_panel_for_status(PT.status_widget)
        if valid(bind_widget) then PT.party_widget = bind_widget end
    end
    if not valid(bind_widget) then
        log("PT navigation failed: Party bind widget unavailable")
        return false
    end

    PT.nav_serial = PT.nav_serial + 1
    local serial = PT.nav_serial


    local ok = native_rebind_panel(bind_widget, target_handle, "PT")
    if not ok then
        return false
    end

    party_sync_cached_handle(bind_widget, target_handle, "PT navigate")

    if serial ~= PT.nav_serial then return true end

    PT.current_index = target_index
    PT.current_handle = target_handle
    if not valid(PT.status_widget) then
        PT.status_widget = find_status_ancestor(PT.party_widget)
    end

    refresh_target(PT, target_handle, "PT")
    party_update_control_visibility()
    return true
end


local function active_state()
    if PT.details_open then return PT, "party" end
    if PB.details_open then return PB, "palbox" end
    return nil, nil
end

local function navigate_active(direction, input_mode)
    if PT.details_open then
        ui_update_labels(PT, input_mode or PT.input_mode)
        return party_navigate(direction)
    end
    if PB.details_open then
        ui_update_labels(PB, input_mode or PB.input_mode)
        return pb_navigate(direction)
    end
    return false
end

local function handle_click()
    local state = active_state()
    if state == nil then return end

    local x, y = mouse_position()
    if inside(x, y, state.ui.left_rect) then
        navigate_active(-1, "keyboard")
    elseif inside(x, y, state.ui.right_rect) then
        navigate_active(1, "keyboard")
    end
end

local function dispatch_game_thread(fn)
    local wrapped = function()
        local ok, err = pcall(fn)
        if not ok then log("GameThread dispatch error: " .. tostring(err)) end
    end

    local method = nil
    local ok_method = pcall(function()
        if EGameThreadMethod ~= nil then method = EGameThreadMethod.ProcessEvent end
    end)

    if ok_method and method ~= nil then
        local ok, err = pcall(function() ExecuteInGameThread(wrapped, method) end)
        if ok then return true end
        log("ProcessEvent dispatch failed; using legacy dispatch: " .. tostring(err))
    end

    local ok, err = pcall(function() ExecuteInGameThread(wrapped) end)
    if not ok then
        log("GameThread queue error: " .. tostring(err))
        return false
    end
    return true
end

local function request_navigate(direction, input_mode)
    dispatch_game_thread(function()
        navigate_active(direction, input_mode)
    end)
end


local install_hooks

local function schedule_retry()
    if retry_pending or hook_install_attempts >= HOOK_INSTALL_MAX_ATTEMPTS then return end
    retry_pending = true

    ExecuteWithDelay(1000, function()
        retry_pending = false
        install_hooks()
    end)
end


local SETUP_SYNC_STACK = {}

local function sync_partner_skill_after_setup(pending)
    if type(pending) ~= "table" then return end
    local status = pending.status
    local handle = pending.handle
    if not valid(status) or not valid(handle) then return end

    local panel = find_pal_panel_for_status(status)
    local pal_id = pal_id_from_handle(handle)
    if not valid(panel) or pal_id == nil then return end

    refresh_partner_skill_name(panel, status, pal_id)
end

install_hooks = function()
    if hook_install_attempts >= HOOK_INSTALL_MAX_ATTEMPTS then return end
    hook_install_attempts = hook_install_attempts + 1
    if not hooks_ready.pb_setup_party then
        hooks_ready.pb_setup_party = pcall(function()
            RegisterHook(PB_SETUP_PARTY_FN, function(context)
                pb_schedule_native_party_focus(context)
            end, function() end)
        end)
    end

    if not hooks_ready.pb_hover then
        hooks_ready.pb_hover = pcall(function()
            RegisterHook(PB_HOVER_FN, function(_, Slot)
                local slot = unwrap(Slot)
                if valid(slot) then
                    local outer = get_outer(slot)
                    if valid(outer) then PB.palbox_container = outer end
                end
            end, function() end)
        end)
    end

    if not hooks_ready.party_set_handles then
        hooks_ready.party_set_handles = pcall(function()
            RegisterHook(PARTY_SET_HANDLES_FN, function(context)
                party_begin_session(context)
            end, function() end)
        end)
    end

    if not hooks_ready.party_list then
        hooks_ready.party_list = pcall(function()
            RegisterHook(PARTY_LIST_TO_STATUS_FN, function(context, CharacterHandle)
                party_enter_details(context, CharacterHandle, "ListToStatus")
            end, function() end)
        end)
    end

    if not hooks_ready.party_to_status then
        hooks_ready.party_to_status = pcall(function()
            RegisterHook(PARTY_TO_STATUS_FN, function(context, CharacterHandle)
                party_enter_details(context, CharacterHandle, "ToStatus")
            end, function() end)
        end)
    end

    if not hooks_ready.party_focus_panel then
        hooks_ready.party_focus_panel = pcall(function()
            RegisterHook(PARTY_FOCUS_PANEL_FN, function()
                if PT.details_open then
                    party_leave_details()
                    end
            end, function() end)
        end)
    end

    if not hooks_ready.party_skill_open then
        hooks_ready.party_skill_open = pcall(function()
            RegisterHook(PARTY_SKILL_OPEN_FN, function(context)
                if not PT.details_open or not valid(PT.current_handle) then return end
                local panel = unwrap(context)
                if not valid(panel) then panel = PT.party_widget end
                if valid(panel) then
                    PT.party_widget = panel
                    party_sync_cached_handle(panel, PT.current_handle, "PT skill popup")
                end
            end, function() end)
        end)
    end

    if not hooks_ready.status_setup_one then
        hooks_ready.status_setup_one = pcall(function()
            RegisterHook(STATUS_SETUP_ONE_FN, function(context, CharacterHandle)
                local handle = unwrap(CharacterHandle)
                local status = unwrap(context)

                local pending = { status = status, handle = handle, source = "SetupOne" }
                table.insert(SETUP_SYNC_STACK, pending)
                if not valid(handle) then return end

                if INTERNAL_STATUS_REFRESH then
                    pending.source = "Internal status refresh"
                    return
                end

                local party_index = nil
                if party_refresh_native_roster("setup_one_classify") then
                    party_index = party_find_index(handle)
                end

                if party_index ~= nil then
                    pending.source = "PT SetupOne"
                    if PB.details_open then pb_close_details() end

                    PT.current_index = party_index
                    PT.current_handle = PT.handles[party_index] or handle
                    PT.details_open = true
                    PT.nickname_editing = false
                    if valid(status) then
                        adopt_status_authority(PT, status, "PT SetupOne")
                    elseif not valid(PT.status_widget) then
                        local fallback = find_details_widget()
                        if valid(fallback) then
                            adopt_status_authority(PT, fallback, "PT SetupOne fallback")
                        end
                    end

                    local recovered_panel = valid(PT.status_widget)
                        and find_pal_panel_for_status(PT.status_widget) or nil
                    if valid(recovered_panel) then PT.party_widget = recovered_panel end

                    PT.input_mode = detect_input_mode(PT.input_mode)
                    if not valid(PT.ui.overlay) then ui_build(PT) end
                    ui_update_labels(PT, PT.input_mode)
                    ui_set_visible(PB, false)
                    ui_set_visible(PT, true)
                    party_update_control_visibility()

                    return
                end

                if PT.details_open then party_leave_details() end

                if PB.suppress_setup then
                    pending.source = "PB SetupOne fallback"
                    PB.suppress_setup = false
                    PB.current_handle = handle
                    if valid(status) then
                        adopt_status_authority(PB, status, "PB SetupOne fallback")
                    end
                    pb_update_control_visibility()
                    return
                end

                pending.source = "PB SetupOne"
                PB.current_handle = handle
                PB.active_container = pb_find_container(handle)
                if valid(PB.active_container) then
                    pb_log_context(PB.active_container, "SetupOne", handle)
                end

                if valid(status) then
                    adopt_status_authority(PB, status, "PB SetupOne")
                elseif not valid(PB.status_widget) then
                    local fallback = find_details_widget()
                    if valid(fallback) then
                        adopt_status_authority(PB, fallback, "PB SetupOne fallback")
                    end
                end

                PB.capture_set = nil
                PB.popup_seen_open = false
                PB.details_open = true
                PB.nickname_editing = false
                PB.nav_serial = PB.nav_serial + 1

                PB.input_mode = detect_input_mode(PB.input_mode)
                if not valid(PB.ui.overlay) then ui_build(PB) end
                ui_update_labels(PB, PB.input_mode)
                ui_set_visible(PT, false)
                ui_set_visible(PB, true)
                pb_update_control_visibility()
            end, function()
                local pending = table.remove(SETUP_SYNC_STACK)
                sync_partner_skill_after_setup(pending)
            end)
        end)
    end

    if not hooks_ready.model_get_camera then
        hooks_ready.model_get_camera = pcall(function()
            RegisterHook(MODEL_GET_CAMERA_FN, function(context, CaptureActor)
                local renderer = unwrap(context)
                local capture = unwrap(CaptureActor)
                if not valid(capture) then return end

                if PT.details_open then
                    PT.capture_set = capture
                elseif PB.details_open then
                    PB.capture_set = capture
                end
            end, function() end)
        end)
    end

    if not hooks_ready.cancel then
        hooks_ready.cancel = pcall(function()
            RegisterHook(CANCEL_FN, function()
                if PT.details_open then party_leave_details() end
                if PB.details_open then pb_close_details() end
            end, function() end)
        end)
    end

    if not hooks_ready.name_open then
        hooks_ready.name_open = pcall(function()
            RegisterHook(NAME_EDIT_OPEN_FN, function()
                if PT.details_open then PT.nickname_editing = true end
                if PB.details_open then PB.nickname_editing = true end
            end, function() end)
        end)
    end

    if not hooks_ready.name_close then
        hooks_ready.name_close = pcall(function()
            RegisterHook(NAME_EDIT_CLOSE_FN, function()
                PT.nickname_editing = false
                PB.nickname_editing = false
            end, function() end)
        end)
    end

    if not hooks_ready.controller_prev then
        hooks_ready.controller_prev = pcall(function()
            RegisterHook(TO_SKILL_DETAIL_FN, function()
                navigate_active(-1, "controller")
            end, function() end)
        end)
    end

    if not hooks_ready.controller_next then
        hooks_ready.controller_next = pcall(function()
            RegisterHook(TO_PARAMETER_DETAIL_FN, function()
                navigate_active(1, "controller")
            end, function() end)
        end)
    end

    local all_ready =
        hooks_ready.pb_setup_party
        and hooks_ready.pb_hover
        and hooks_ready.status_setup_one
        and hooks_ready.party_set_handles
        and hooks_ready.party_list
        and hooks_ready.party_to_status
        and hooks_ready.party_focus_panel
        and hooks_ready.party_skill_open
        and hooks_ready.cancel
        and hooks_ready.name_open
        and hooks_ready.name_close
        and hooks_ready.controller_prev
        and hooks_ready.controller_next
        and hooks_ready.model_get_camera

    if not all_ready then
        if hook_install_attempts < HOOK_INSTALL_MAX_ATTEMPTS then
            schedule_retry()
        else
            log("UI hooks still incomplete after " .. tostring(HOOK_INSTALL_MAX_ATTEMPTS) .. " attempts; stopping hook retries")
        end
    end
end

local function client_viewport_ready()
    local pc = get_player_controller()
    if not valid(pc) then return false end

    local library = get_class("/Script/UMG.Default__WidgetLayoutLibrary")
    if not valid(library) then return false end

    local ok, size = pcall(function() return library:GetViewportSize(pc) end)
    if not ok or size == nil then return false end

    local x, y
    ok, x, y = pcall(function() return tonumber(size.X), tonumber(size.Y) end)
    return ok and x ~= nil and y ~= nil and x > 0 and y > 0
end

local client_started = false
local client_viewport_waits = 0
local CLIENT_VIEWPORT_MAX_WAITS = 10

local function start_client()
    if client_started then return end
    client_started = true

    RegisterKeyBind(Key.A, function() request_navigate(-1, "keyboard") end)
    RegisterKeyBind(Key.D, function() request_navigate(1, "keyboard") end)

    local left_arrow_ok, left_arrow_err = pcall(function()
        RegisterKeyBind(Key.LEFT_ARROW, function() request_navigate(-1, "keyboard") end)
    end)

    local right_arrow_ok, right_arrow_err = pcall(function()
        RegisterKeyBind(Key.RIGHT_ARROW, function() request_navigate(1, "keyboard") end)
    end)

    local mouse_ok, mouse_err = pcall(function()
        RegisterKeyBind(Key.LEFT_MOUSE_BUTTON, function()
            dispatch_game_thread(handle_click)
        end)
    end)

    install_hooks()

    local api_had_provider = false
    if type(LoopInGameThreadWithDelay) == "function" then
        LoopInGameThreadWithDelay(250, function()
            local provider = api_read("ActiveProvider")
            local has_provider = type(provider) == "string" and provider ~= ""
            if PB.details_open and (has_provider or api_had_provider) then
                pb_update_control_visibility()
            end
            api_had_provider = has_provider
        end)
    end

    log("Palbox Quick Browse v" .. VERSION .. " loaded")
    if not left_arrow_ok then log("Left Arrow binding unavailable: " .. tostring(left_arrow_err)) end
    if not right_arrow_ok then log("Right Arrow binding unavailable: " .. tostring(right_arrow_err)) end
    if not mouse_ok then log("Mouse binding unavailable: " .. tostring(mouse_err)) end
end

local function wait_for_client_viewport()
    if client_viewport_ready() then
        start_client()
        return
    end

    if client_viewport_waits >= CLIENT_VIEWPORT_MAX_WAITS then
        log("No client viewport detected after 10 seconds; dedicated/headless process detected, PBQB disabled")
        return
    end

    if client_viewport_waits == 0 then
        log("Waiting for client viewport before initializing input and UI hooks")
    end

    client_viewport_waits = client_viewport_waits + 1
    ExecuteWithDelay(1000, wait_for_client_viewport)
end

wait_for_client_viewport()
