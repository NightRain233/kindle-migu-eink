--[[
eanab 界面调色板（early 补丁，必须在任何界面模块加载前运行）。

KOReader 的界面灰色是按 16 级灰屏设计的（0x11 的倍数，共 15 种）。本机的翻页波形
是 DU4，局部刷新只有 GL0/GL5/GL10/GL15 四级，其余灰值会被随机量化，表现为发虚、
同一种灰深浅不一。这里把界面常量统一收敛到 0x00/0x55/0xAA/0xFF：
这四个值在 DU4 下是精确灰阶，在 GC16/GL16 下也正好落在色阶上，
所以将来按图层分流后（界面走 16 级灰）同样正确。

只改 Blitbuffer 的颜色常量，不碰书页渲染（crengine 不用这些常量）。
删除本文件即可恢复原样。
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Color8 = Blitbuffer.Color8

local remap = {
    COLOR_GRAY_E     = 0xFF,
    COLOR_GRAY_D     = 0xFF,
    COLOR_LIGHT_GRAY = 0xAA,
    COLOR_GRAY_B     = 0xAA,
    COLOR_GRAY       = 0xAA,
    COLOR_GRAY_9     = 0xAA,
    COLOR_DARK_GRAY  = 0x55,
    COLOR_GRAY_7     = 0x55,
    COLOR_GRAY_6     = 0x55,
    COLOR_GRAY_5     = 0x55,
    COLOR_GRAY_4     = 0x55,
    COLOR_GRAY_3     = 0x55,
    COLOR_GRAY_2     = 0x00,
    COLOR_GRAY_1     = 0x00,
}

for name, value in pairs(remap) do
    if Blitbuffer[name] ~= nil then
        Blitbuffer[name] = Color8(value)
    end
end
