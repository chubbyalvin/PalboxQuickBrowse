local TAG = "[PalboxQuickBrowse]"

local HOVER_FN = "/Game/Pal/Blueprint/UI/PalStorage/WBP_PalStorageMenu.WBP_PalStorageMenu_C:BndEvt__WBP_PalStorageMenu_WBP_IngameMenu_PalBox_K2Node_ComponentBoundEvent_1_OnHoveredBoxSlot__DelegateSignature"
local SETUP_FN = "/Game/Pal/Blueprint/UI/PalStatus/WBP_PalStatus.WBP_PalStatus_C:Setup One Pal"
local NAME_EDIT_OPEN_FN = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Pal/WBP_MainMenu_Pal_00.WBP_MainMenu_Pal_00_C:OpenNameEditWindow"
local NAME_EDIT_CLOSE_FN = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Pal/WBP_MainMenu_Pal_00.WBP_MainMenu_Pal_00_C:OnCloseNameEditWindow"
local TO_SKILL_DETAIL_FN = "/Game/Pal/Blueprint/UI/PalStatus/WBP_PalStatus.WBP_PalStatus_C:ToSkillDetail"
local TO_PARAMETER_DETAIL_FN = "/Game/Pal/Blueprint/UI/PalStatus/WBP_PalStatus.WBP_PalStatus_C:ToParameterDetail"
local CANCEL_FN = "/Game/Pal/Blueprint/UI/PalStatus/StatusPopup/WBP_PalStatusPopup.WBP_PalStatusPopup_C:OnCancelAction"

local VIS_VISIBLE = 0
local VIS_COLLAPSED = 1
local VIS_HIT_TEST_INVISIBLE = 3
local VIS_SELF_HIT_TEST_INVISIBLE = 4

local hooks_ready = { hover = false, setup = false, cancel = false, name_open = false, name_close = false, controller_prev = false, controller_next = false }
local retry_pending = false

local palbox_container = nil
local active_container = nil
local current_handle = nil
local suppress_setup = false
local details_open = false
local details_popup = nil
local popup_seen_open = false
local nickname_editing = false
local input_display_mode = "keyboard"

local overlay = nil
local overlay_root = nil
local left_widgets = {}
local right_widgets = {}

local left_rect = { x = 0, y = 0, w = 0, h = 0 }
local right_rect = { x = 0, y = 0, w = 0, h = 0 }

local class_cache = {}
local vec2 = { X = 0.0, Y = 0.0 }

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

local function same_object(a, b)
    return valid(a) and valid(b) and full_name(a) == full_name(b)
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

    local ok, outer = pcall(function() return obj:GetOuter() end)
    if ok and valid(outer) then return outer end

    ok, outer = pcall(function() return obj.OuterPrivate end)
    return ok and valid(outer) and outer or nil
end

local function find_popup_ancestor(obj)
    local current = unwrap(obj)

    for _ = 1, 10 do
        if not valid(current) then return nil end

        if string.find(full_name(current), "WBP_PalStatusPopup_C", 1, true) then
            return current
        end

        current = get_outer(current)
    end

    return nil
end

local function popup_is_open(popup)
    if not valid(popup) then return false end

    local ok, active = pcall(function() return popup:IsActivated() end)
    if ok and active == false then return false end

    ok, active = pcall(function() return popup:GetVisibility() end)
    if ok then
        active = tonumber(unwrap(active))
        if active ~= nil then
            return active == VIS_VISIBLE
                or active == VIS_HIT_TEST_INVISIBLE
                or active == VIS_SELF_HIT_TEST_INVISIBLE
        end
    end

    return true
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

local function popup_visible(widget)
    if not valid(widget) then return false end

    local ok, visibility = pcall(function() return widget:GetVisibility() end)
    if ok then
        visibility = unwrap(visibility)
        visibility = tonumber(visibility)
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

    local popup_name = full_name(popup)
    for _, obj in ipairs(popups) do
        local name = full_name(obj)
        if valid(obj)
            and string.find(name, "/Engine/Transient.", 1, true)
            and string.find(name, popup_name, 1, true)
        then
            return obj
        end
    end

    for _, obj in ipairs(popups) do
        if valid(obj) and string.find(full_name(obj), "/Engine/Transient.", 1, true) then
            return obj
        end
    end

    return nil
end

local function find_container(handle)
    if not valid(handle) then return nil end

    if valid(active_container) and valid(container_find(active_container, handle)) then
        return active_container
    end

    if valid(palbox_container) and valid(container_find(palbox_container, handle)) then
        return palbox_container
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

local function resolve_current_slot()
    active_container = find_container(current_handle)
    if not valid(active_container) then return nil end

    local slot = container_find(active_container, current_handle)
    if valid(slot) then return slot end

    local count = container_num(active_container)
    if count == nil then return nil end

    for i = 0, count - 1 do
        slot = container_get(active_container, i)
        if same_object(slot_handle(slot), current_handle) then return slot end
    end

    return nil
end

local function find_neighbor(index, direction)
    local count = container_num(active_container)
    if count == nil then return nil end

    for i = index + direction, direction > 0 and count - 1 or 0, direction do
        local slot = container_get(active_container, i)
        if valid(slot) and valid(slot_handle(slot)) then return slot end
    end

    return nil
end

local update_control_visibility

local function navigate(direction)
    if not details_open or not valid(current_handle) or nickname_editing then return false end

    local current_slot = resolve_current_slot()
    if not valid(current_slot) then
        log("Navigation failed: source container not found.")
        return false
    end

    local index = slot_index(current_slot)
    if index == nil then return false end

    local target_slot = find_neighbor(index, direction)
    if not valid(target_slot) then return false end

    local target_handle = slot_handle(target_slot)
    local widget = find_details_widget()
    if not valid(target_handle) or not valid(widget) then
        log("Navigation failed: Details widget unavailable.")
        return false
    end

    local ok, err = pcall(function()
        suppress_setup = true
        widget["Setup One Pal"](widget, target_handle, true)
    end)

    if ok then
        current_handle = target_handle
        update_control_visibility()
        return true
    end

    suppress_setup = false
    log("Navigation error: " .. tostring(err))
    return false
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

local function update_input_labels(mode)
    input_display_mode = mode
    if valid(left_widgets[2]) then set_text(left_widgets[2], mode == "controller" and "LT" or "A") end
    if valid(right_widgets[2]) then set_text(right_widgets[2], mode == "controller" and "RT" or "D") end
end

local function detect_input_mode()
    local ok, input = pcall(function() return FindFirstOf("CommonInputSubsystem") end)
    if not ok or not valid(input) then return input_display_mode end

    ok, input = pcall(function() return unwrap(input:GetCurrentInputType()) end)
    if not ok then return input_display_mode end
    return tonumber(input) == 0 and "keyboard" or "controller"
end

local function set_overlay_visible(visible)
    local visibility = visible and VIS_SELF_HIT_TEST_INVISIBLE or VIS_COLLAPSED
    if valid(overlay) then pcall(function() overlay:SetVisibility(visibility) end) end
    if valid(overlay_root) then pcall(function() overlay_root:SetVisibility(visibility) end) end

    if not visible then
        for _, widgets in ipairs({ left_widgets, right_widgets }) do
            for _, widget in ipairs(widgets) do
                if valid(widget) then
                    pcall(function() widget:SetVisibility(VIS_COLLAPSED) end)
                end
            end
        end
    end
end

local function close_details()
    details_open = false
    details_popup = nil
    popup_seen_open = false
    nickname_editing = false
    active_container = nil
    current_handle = nil
    suppress_setup = false
    set_overlay_visible(false)
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

local function update_rects(pc)
    local w, h = viewport_size(pc)
    local bw = math.max(66, math.floor(w * 0.038))
    local bh = math.max(126, math.floor(h * 0.145))
    local margin = math.max(6, math.floor(w * 0.006))
    local y = math.floor((h - bh) / 2)

    left_rect.x, left_rect.y, left_rect.w, left_rect.h = margin, y, bw, bh
    right_rect.x, right_rect.y, right_rect.w, right_rect.h = w - margin - bw, y, bw, bh
end

local function add_control(tree, root, rect, letter, arrow)
    local widgets = {}

    local border = construct("/Script/UMG.Border", tree)
    if not valid(border) then return nil end

    local slot = add_to_canvas(root, border)
    if slot == nil then return nil end

    set_position(slot, rect.x, rect.y)
    set_size(slot, rect.w, rect.h)

    pcall(function()
        border:SetBrushColor({ R = 0.025, G = 0.028, B = 0.035, A = 0.68 })
        border:SetVisibility(VIS_HIT_TEST_INVISIBLE)
    end)
    widgets[#widgets + 1] = border

    local label = construct("/Script/UMG.TextBlock", tree)
    if valid(label) then
        slot = add_to_canvas(root, label)
        if slot ~= nil then
            set_position(slot, rect.x + 2, rect.y + math.floor(rect.h * 0.08))
            set_size(slot, rect.w - 4, math.floor(rect.h * 0.27))
            set_text(label, letter)
            pcall(function()
                local font = label.Font
                font.Size = math.max(16, math.floor(rect.h * 0.14))
                label:SetFont(font)
                label:SetJustification(1)
                label:SetVisibility(VIS_HIT_TEST_INVISIBLE)
            end)
            widgets[#widgets + 1] = label
        end
    end

    label = construct("/Script/UMG.TextBlock", tree)
    if valid(label) then
        slot = add_to_canvas(root, label)
        if slot ~= nil then
            set_position(slot, rect.x, rect.y + math.floor(rect.h * 0.30))
            set_size(slot, rect.w, math.floor(rect.h * 0.55))
            set_text(label, arrow)
            pcall(function()
                local font = label.Font
                font.Size = math.max(34, math.floor(rect.h * 0.35))
                label:SetFont(font)
                label:SetJustification(1)
                label:SetVisibility(VIS_HIT_TEST_INVISIBLE)
            end)
            widgets[#widgets + 1] = label
        end
    end

    return widgets
end

local function set_control_visible(widgets, visible)
    local visibility = visible and VIS_HIT_TEST_INVISIBLE or VIS_COLLAPSED
    for _, widget in ipairs(widgets) do
        if valid(widget) then
            pcall(function() widget:SetVisibility(visibility) end)
        end
    end
end

update_control_visibility = function()
    if not details_open or not valid(current_handle) then
        set_control_visible(left_widgets, false)
        set_control_visible(right_widgets, false)
        return
    end

    local current_slot = resolve_current_slot()
    if not valid(current_slot) then
        set_control_visible(left_widgets, false)
        set_control_visible(right_widgets, false)
        return
    end

    local index = slot_index(current_slot)
    if index == nil then
        set_control_visible(left_widgets, false)
        set_control_visible(right_widgets, false)
        return
    end

    set_control_visible(left_widgets, valid(find_neighbor(index, -1)))
    set_control_visible(right_widgets, valid(find_neighbor(index, 1)))
end

local function build_overlay()
    if valid(overlay) then return true end

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

    overlay, overlay_root = widget, root
    pcall(function() root:SetVisibility(VIS_SELF_HIT_TEST_INVISIBLE) end)

    update_rects(pc)
    left_widgets = add_control(tree, root, left_rect, input_display_mode == "controller" and "LT" or "A", "←") or {}
    right_widgets = add_control(tree, root, right_rect, input_display_mode == "controller" and "RT" or "D", "→") or {}

    if not pcall(function() widget:AddToViewport(80) end) then
        overlay, overlay_root = nil, nil
        return false
    end

    pcall(function() widget:SetVisibility(VIS_SELF_HIT_TEST_INVISIBLE) end)
    set_overlay_visible(false)
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

local function handle_click()
    if not details_open then return end

    local x, y = mouse_position()
    if inside(x, y, left_rect) then
        navigate(-1)
    elseif inside(x, y, right_rect) then
        navigate(1)
    end
end

local install_hooks

local function schedule_retry()
    if retry_pending or (hooks_ready.hover and hooks_ready.setup and hooks_ready.cancel) then return end
    retry_pending = true

    ExecuteWithDelay(1000, function()
        retry_pending = false
        install_hooks()
    end)
end

install_hooks = function()
    if not hooks_ready.hover then
        local ok = pcall(function()
            RegisterHook(HOVER_FN, function(_, Slot)
                local slot = unwrap(Slot)
                if valid(slot) then
                    local outer = get_outer(slot)
                    if valid(outer) then palbox_container = outer end
                end
            end, function() end)
        end)
        hooks_ready.hover = ok
    end

    if not hooks_ready.setup then
        local ok = pcall(function()
            RegisterHook(SETUP_FN, function(context, CharacterHandle)
                local handle = unwrap(CharacterHandle)

                if suppress_setup then
                    suppress_setup = false
                    if valid(handle) then current_handle = handle end
                    update_control_visibility()
                    return
                end

                if valid(handle) then
                    current_handle = handle
                    active_container = nil
                end

                details_popup = find_popup_ancestor(context)
                popup_seen_open = false
                details_open = true
                update_input_labels(detect_input_mode())
                set_overlay_visible(true)
                update_control_visibility()
            end, function() end)
        end)
        hooks_ready.setup = ok
    end

    if not hooks_ready.cancel then
        local ok = pcall(function()
            RegisterHook(CANCEL_FN, function()
                close_details()
            end, function() end)
        end)
        hooks_ready.cancel = ok
    end

    if not hooks_ready.name_open then
        local ok = pcall(function()
            RegisterHook(NAME_EDIT_OPEN_FN, function()
                nickname_editing = true
            end, function() end)
        end)
        hooks_ready.name_open = ok
    end

    if not hooks_ready.name_close then
        local ok = pcall(function()
            RegisterHook(NAME_EDIT_CLOSE_FN, function()
                nickname_editing = false
            end, function() end)
        end)
        hooks_ready.name_close = ok
    end

    if not hooks_ready.controller_prev then
        hooks_ready.controller_prev = pcall(function()
            RegisterHook(TO_SKILL_DETAIL_FN, function()
                if details_open and not nickname_editing then
                    update_input_labels("controller")
                    navigate(-1)
                end
            end, function() end)
        end)
    end

    if not hooks_ready.controller_next then
        hooks_ready.controller_next = pcall(function()
            RegisterHook(TO_PARAMETER_DETAIL_FN, function()
                if details_open and not nickname_editing then
                    update_input_labels("controller")
                    navigate(1)
                end
            end, function() end)
        end)
    end

    if not (hooks_ready.hover and hooks_ready.setup and hooks_ready.cancel and hooks_ready.name_open and hooks_ready.name_close and hooks_ready.controller_prev and hooks_ready.controller_next) then
        schedule_retry()
    end
end

RegisterKeyBind(Key.A, function() update_input_labels("keyboard"); navigate(-1) end)
RegisterKeyBind(Key.LEFT_ARROW, function() update_input_labels("keyboard"); navigate(-1) end)
RegisterKeyBind(Key.D, function() update_input_labels("keyboard"); navigate(1) end)
RegisterKeyBind(Key.RIGHT_ARROW, function() update_input_labels("keyboard"); navigate(1) end)

local mouse_ok, mouse_err = pcall(function()
    RegisterKeyBind(Key.LEFT_MOUSE_BUTTON, handle_click)
end)

LoopAsync(250, function()
    ExecuteInGameThread(function()
        if not valid(overlay) and build_overlay() then
            set_overlay_visible(details_open)
            if details_open then update_control_visibility() end
        end

        if details_open and valid(details_popup) then
            if popup_is_open(details_popup) then
                popup_seen_open = true
            elseif popup_seen_open then
                close_details()
            end
        end
    end)
    return false
end)

install_hooks()

log("Palbox Quick Browse loaded.")
if not mouse_ok then log("Mouse binding unavailable: " .. tostring(mouse_err)) end
