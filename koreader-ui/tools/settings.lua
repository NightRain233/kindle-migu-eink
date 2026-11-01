--[[
修改或恢复 KOReader 的 settings.reader.lua（在 Mac 上用 luajit 运行）。

  luajit settings.lua apply   <settings.reader.lua> <orig-values.lua>
  luajit settings.lua restore <settings.reader.lua> <orig-values.lua>

apply：第一次运行时把将要改动的键的原值写进 orig-values.lua（已存在则不覆盖），
       然后写入新值。restore：按 orig-values.lua 把这些键改回去。
KOReader 运行时会回写设置，所以调用前必须先停掉 KOReader。
--]]

-- 顶层键
local top = {
    home_dir = "/storage/emulated/legacy/Books",
    show_parent_folder = false,
    shorten_home_dir = true,
    reader_footer_mode = 1,
}

-- footer 子表里的键
local footer = {
    all_at_once = true,
    hide_empty_generators = true,
    page_progress = false,
    pages_left_book = false,
    percentage = false,
    book_time_to_read = false,
    chapter_time_to_read = false,
    pages_left = true,
    dynamic_filler = true,
    time = true,
    battery = true,
    battery_hide_threshold = 20,
    order = { "pages_left", "dynamic_filler", "battery", "time" },
    progress_bar_position = "above",
    progress_style_thin = false,
    progress_style_thick_height = 5,
    progress_margin = false,
    toc_markers = true,
    toc_markers_width = 1,
    item_prefix = "letters",
    items_separator = "dot",
    align = "center",
    text_font_face = "NotoSansCJKsc-Medium.otf",
    text_font_size = 14,
    text_font_bold = false,
    container_height = 16,
    container_bottom_padding = 2,
}

local function serialize(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t ~= "table" then error("cannot serialize " .. t) end
    local keys = {}
    for k in pairs(v) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    local inner = indent .. "    "
    local out = { "{\n" }
    for _, k in ipairs(keys) do
        local ks = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
        table.insert(out, inner .. ks .. " = " .. serialize(v[k], inner) .. ",\n")
    end
    table.insert(out, indent .. "}")
    return table.concat(out)
end

local function load(path)
    local f = assert(loadfile(path))
    return f()
end

local function save(path, tbl, header)
    local f = assert(io.open(path, "w"))
    f:write(header or "", "return ", serialize(tbl), "\n")
    f:close()
end

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local mode, settings_path, orig_path = arg[1], arg[2], arg[3]
assert(mode and settings_path and orig_path, "usage: settings.lua apply|restore <settings> <orig>")
local s = load(settings_path)
s.footer = s.footer or {}

if mode == "apply" then
    if not exists(orig_path) then
        local orig = { top = {}, footer = {} }
        for k in pairs(top) do
            local v = s[k]
            if v == nil then orig.top[k] = "__nil__" else orig.top[k] = v end
        end
        for k in pairs(footer) do
            local v = s.footer[k]
            if v == nil then orig.footer[k] = "__nil__" else orig.footer[k] = v end
        end
        save(orig_path, orig, "-- eanab UI 补丁改动前的原值，由 koreader-ui/tools/settings.lua 生成\n")
    end
    for k, v in pairs(top) do s[k] = v end
    for k, v in pairs(footer) do s.footer[k] = v end
elseif mode == "restore" then
    local orig = load(orig_path)
    for k, v in pairs(orig.top) do
        if v == "__nil__" then s[k] = nil else s[k] = v end
    end
    for k, v in pairs(orig.footer) do
        if v == "__nil__" then s.footer[k] = nil else s.footer[k] = v end
    end
else
    error("unknown mode " .. tostring(mode))
end
save(settings_path, s, "-- " .. settings_path:match("[^/]+$") .. "\n")
print(mode .. " done")
