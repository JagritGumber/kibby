-- Kibby's changes to CachyOS's binds and inputs, applied on top of them.
-- Number keys go to workspaces rather than monitors, and Super+Shift+S
-- toggles the focused window in and out of the scratchpad.

local mainMod = "SUPER"

local function rebind(keys, dispatcher, options)
    hl.unbind(keys)
    hl.bind(keys, dispatcher, options or {})
end

-- CachyOS binds Super+1..3 and Super+Shift+1..3 to monitors, and keeps
-- absolute and relative workspace keys on Alt and Control.
for i = 1, NUM_WPM do
    local key = i % 10
    hl.unbind(mainMod .. " + ALT + " .. key)
    hl.unbind(mainMod .. " + CONTROL + " .. key)
    hl.unbind(mainMod .. " + SHIFT + CONTROL + " .. key)
    rebind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    rebind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
hl.unbind(mainMod .. " + SHIFT + mouse_up")
hl.unbind(mainMod .. " + SHIFT + mouse_down")

KIBBY = KIBBY or {}

function KIBBY.toggleScratchpadWindow()
    if not hl.get_active_window() then
        return
    end

    if hl.get_active_special_workspace() then
        local normal_workspace = hl.get_active_workspace()
        if normal_workspace then
            hl.dispatch(hl.dsp.window.move({ workspace = normal_workspace.name }))
        end
    else
        hl.dispatch(hl.dsp.window.move({ workspace = "special" }))
    end
end

rebind(mainMod .. " + SHIFT + S", KIBBY.toggleScratchpadWindow)

-- Laptops with a dedicated numpad (KIBBY_NUMLOCK_BY_DEFAULT): without this,
-- NumLk often never sticks on the keyd virtual keyboard and the pad sends arrows.
if KIBBY.settings.numlockByDefault then
    hl.config({ input = { numlock_by_default = true } })
end
