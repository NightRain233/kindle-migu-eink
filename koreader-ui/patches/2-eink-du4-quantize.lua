--[[
DU4 预量化（late 补丁，实验）。

本机翻页走全局 DU4，面板只能准确显示 GL0/GL5/GL10/GL15 四级灰。字形边缘的抗锯齿
像素落在这几级之间，DU4 对它们没有定义，结果时浅时断，看起来“虚”。

这里在 KOReader 把画面交给安卓窗口之前，先把本次刷新区域的像素换算成
0x00/0x55/0xAA/0xFF 四个值。分界点故意偏深，让边缘灰往黑靠，笔画更实、更稳定。
已经是四个值之一的像素保持不变，所以重复处理不会累积。

  - 只在运行时包装 Screen 的 refresh*Imp，不改 ffi/framebuffer_android.lua；
  - 按 launcher 能力决定处理哪些刷新：
      官方包（不能指定波形，全部走全局 DU4）→ 所有刷新都量化；
      eanab 适配包（android.isEinkFull()，按刷新类别下发 parcel）→ 只量化正文翻页
      refreshPartialImp（DU4）；快速刷新走 DU（本来只有黑白），菜单/书库走 AUTO、
      全刷走 GC16（16 级灰），这些都不碰，否则反而丢失灰阶；
  - 夜间模式（反色）下跳过；
  - 紧急开关：创建 koreader/eanab-quant.off 后重启 KOReader 即停用；
  - 前 200 次刷新的耗时写入 koreader/eanab-quant.log。
删除本文件即可恢复原样。
--]]

local ffi = require("ffi")
local bit = require("bit")
local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ffiUtil = require("ffi/util")

local data_dir = DataStorage:getDataDir()
if lfs.attributes(data_dir .. "/eanab-quant.off", "mode") then
    logger.info("eink-du4-quantize: disabled by eanab-quant.off")
    return
end

-- 分界点（0=黑，255=白）。最近值取整的分界是 0x2A/0x80/0xD5，这里整体往亮的一侧移，
-- 等于把中间灰“判黑”的范围放大。调深浅只改这三个数。
local T_BLACK = 0x50   -- 低于此值 → 0x00
local T_DARK  = 0x9A   -- 低于此值 → 0x55
local T_LIGHT = 0xE0   -- 低于此值 → 0xAA，否则 → 0xFF

local LUT = ffi.new("uint8_t[256]")
for v = 0, 255 do
    if v < T_BLACK then LUT[v] = 0x00
    elseif v < T_DARK then LUT[v] = 0x55
    elseif v < T_LIGHT then LUT[v] = 0xAA
    else LUT[v] = 0xFF end
end

local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local WHITE = 0xFFFFFF
local u32p = ffi.typeof("uint32_t*")

-- BBRGB32 内存布局为 r,g,b,a：按小端 uint32 读是 a<<24 | b<<16 | g<<8 | r
local function quantizeRect(bb, x, y, w, h)
    local stride = tonumber(bb.stride) / 4
    local base = ffi.cast(u32p, bb.data)
    for row = y, y + h - 1 do
        local p = base + row * stride + x
        for i = 0, w - 1 do
            local px = p[i]
            local rgb = band(px, WHITE)
            if rgb ~= WHITE and rgb ~= 0 then
                local r = band(px, 0xFF)
                local g = band(rshift(px, 8), 0xFF)
                local b = band(rshift(px, 16), 0xFF)
                local lum
                if r == g and g == b then
                    lum = r
                else
                    lum = rshift(r * 77 + g * 151 + b * 28, 8)
                end
                local q = LUT[lum]
                if q ~= r or r ~= g or g ~= b then
                    p[i] = bor(band(px, 0xFF000000), lshift(q, 16), lshift(q, 8), q)
                end
            end
        end
    end
end

local Screen = Device.screen
local stats = { n = 0, total = 0, max = 0, pixels = 0 }
local log_path = data_dir .. "/eanab-quant.log"

local function now()
    local s, us = ffiUtil.gettime()
    return s + us / 1e6
end

local function process(fb, x, y, w, h)
    local bb = fb.full_bb or fb.bb
    if not bb or bb:getType() ~= Blitbuffer.TYPE_BBRGB32 or bb:getInverse() == 1 then
        return
    end
    local t0 = stats.n < 200 and now()
    x, y, w, h = bb:getBoundedRect(x or 0, y or 0, w or bb:getWidth(), h or bb:getHeight())
    x, y, w, h = bb:getPhysicalRect(x, y, w, h)
    if w <= 0 or h <= 0 then return end
    quantizeRect(bb, x, y, w, h)
    if t0 then
        local dt = (now() - t0) * 1000
        stats.n = stats.n + 1
        stats.total = stats.total + dt
        stats.pixels = stats.pixels + w * h
        if dt > stats.max then stats.max = dt end
        if stats.n % 20 == 0 then
            local f = io.open(log_path, "a")
            if f then
                f:write(("%s n=%d avg=%.1fms max=%.1fms avg_px=%d\n"):format(
                    os.date("%H:%M:%S"), stats.n, stats.total / stats.n, stats.max,
                    math.floor(stats.pixels / stats.n)))
                f:close()
            end
        end
    end
end

local broken = false
local ok_android, android = pcall(require, "android")
local eink_full = ok_android and android.isEinkFull and android.isEinkFull() or false
local targets = eink_full and { "refreshPartialImp" }
    or { "refreshFullImp", "refreshPartialImp", "refreshFlashPartialImp",
         "refreshUIImp", "refreshFlashUIImp", "refreshFastImp" }
do
    local f = io.open(log_path, "a")
    if f then
        f:write(("%s start eink_full=%s targets=%s\n"):format(
            os.date("%H:%M:%S"), tostring(eink_full), table.concat(targets, ",")))
        f:close()
    end
end

for _, name in ipairs(targets) do
    local orig = Screen[name]
    if orig then
        Screen[name] = function(fb, x, y, w, h, ...)
            if not broken then
                local ok, err = pcall(process, fb, x, y, w, h)
                if not ok then
                    broken = true
                    logger.warn("eink-du4-quantize: disabled after error:", err)
                    local f = io.open(log_path, "a")
                    if f then f:write("ERROR ", tostring(err), "\n") f:close() end
                end
            end
            return orig(fb, x, y, w, h, ...)
        end
    end
end
