--[[
AndE parcel 先于画面提交（late 补丁，只在 eanab 适配包下生效）。

原版 ffi/framebuffer_android.lua 的每个 refresh*Imp 都是先 _updateWindow()（把画面交给窗口），
再 _updatePartial()/android.einkUpdate()（候选控制器在这里发 AndE parcel）。
SurfaceFlinger 收到新 buffer 就立即提交给 EPDC，比 parcel 早约 2 ms，于是**每一帧都用了
上一次的波形配置**：菜单之后的第一页翻页走了 AUTO(257)，翻页之后打开的菜单走了 DU4(7)。
（实测与原理见 docs/pitfalls.md「刷新顺序」。）

这里把顺序换成：先下发刷新意图（parcel 同步完成），再提交画面。
- 只在 android.isEinkFull() 为真时替换（候选包）；官方包没有 parcel，保持原样；
- 文件名排在 2-eink-du4-quantize.lua 之前：量化补丁会包在这里替换后的函数外面。
删除本文件即可恢复原样。
--]]

local ok, android = pcall(require, "android")
if not ok or not android.isEinkFull or not android.isEinkFull() then
    return
end

local Device = require("device")
local Screen = Device.screen

local full, partial, full_ui, partial_ui, fast, delay_page, delay_ui, delay_fast = android.getEinkConstants()
local _, eink_platform = android.isEink()

function Screen:refreshFullImp(x, y, w, h) -- luacheck: ignore
    self:_updateFull()
    self:_updateWindow()
end

function Screen:refreshPartialImp(x, y, w, h)
    self:_updatePartial(partial, delay_page, x, y, w, h)
    self:_updateWindow()
end

function Screen:refreshFlashPartialImp(x, y, w, h)
    self:_updatePartial(full, delay_page, x, y, w, h)
    self:_updateWindow()
end

function Screen:refreshUIImp(x, y, w, h)
    self:_updatePartial(partial_ui, delay_ui, x, y, w, h)
    self:_updateWindow()
end

function Screen:refreshFlashUIImp(x, y, w, h)
    self:_updatePartial(full_ui, delay_ui, x, y, w, h)
    self:_updateWindow()
end

function Screen:refreshFastImp(x, y, w, h)
    self:_updatePartial(fast, delay_fast, x, y, w, h)
    self:_updateWindow()
end

-- 供其他补丁（先快后清）使用：先下发指定波形，再提交画面
function Screen:eanabRefreshWithWaveform(waveform, x, y, w, h)
    self:_updatePartial(waveform, 0, x, y, w, h)
    self:_updateWindow()
end

Screen.eanab_parcel_first = true
Screen.eanab_platform = eink_platform
