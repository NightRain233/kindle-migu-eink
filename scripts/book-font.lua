--[[
把 DU4 下调好的正文字体参数写进书籍 metadata 或全局设置（在 Mac 上用 luajit 运行）。

  luajit book-font.lua book     <metadata.epub.lua>     # 改单本书，打印 cache_file_path
  luajit book-font.lua defaults <settings.reader.lua>   # 改全局默认（新书生效）

参数来自 docs/font-clarity-2026-10-31.md：LXGW WenKai + 字重 +1 + gamma 30 + hinting 1。
font_face 必须用 FontList 家族名 "LXGW WenKai"，不能用文件名 "LXGWWenKai-Regular"。
调用前必须停掉 KOReader（运行中会回写），改完要删掉该书的 .cr3 排版缓存。
--]]

local FONT = "LXGW WenKai"
local OPTS = { font_base_weight = 1, font_gamma = 30, font_hinting = 1 }

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

local mode, path = arg[1], arg[2]
assert(mode and path, "usage: book-font.lua book|defaults <file>")
local t = assert(loadfile(path))()

if mode == "book" then
    t.font_face = FONT
    for k, v in pairs(OPTS) do t["copt_" .. k] = v end
elseif mode == "defaults" then
    t.cre_font = FONT
    for k, v in pairs(OPTS) do t["copt_" .. k] = v end
else
    error("unknown mode " .. mode)
end

local f = assert(io.open(path, "w"))
f:write("-- ", path:match("[^/]+$"), "\nreturn ", serialize(t), "\n")
f:close()
if mode == "book" and t.cache_file_path then
    print(t.cache_file_path)
end
