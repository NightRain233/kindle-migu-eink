--[[
先快后清（late 补丁，只在 eanab 适配包下生效）。

翻页仍走 DU4（272 ms，配合 2-eink-du4-quantize.lua 的 4 级预量化，快且字实）；
若在这一页停留超过 SETTLE_DELAY 秒、期间没有任何新的刷新，就把当前页重绘一遍
（走 "ui" 刷新，不经过预量化，保留 16 级灰），并用 GL16(5) 局部刷新下发。
此时屏幕上只有字形边缘的像素从 4 级变成 16 级，EPDC 只驱动这些变化的像素；
GL16 是灰到灰、不闪黑的波形，结果接近原厂 450 ms 的画质，但不增加翻页等待。

  - 依赖候选控制器把非标准波形号原样透传给 parcel（mode=5 → waveform 5, updateMode 0），
    以及 2-eink-ande-order.lua 提供的 Screen:eanabRefreshWithWaveform；
  - 期间任何刷新（翻页、菜单、弹窗、底栏）都会取消待执行的补刷，快翻时不补刷；
  - 到点时最上层必须仍是阅读界面；
  - 紧急开关：创建 koreader/eanab-settle.off 后重启 KOReader 即停用。
删除本文件即可恢复原样。
--]]

local SETTLE_DELAY = 1.0      -- 秒：停留多久后补刷
local SETTLE_WAVEFORM = 5     -- GL16
local MIN_AREA_RATIO = 0.6    -- 只对大面积的正文翻页安排补刷

local DataStorage = require("datastorage")
local Device = require("device")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local UIManager = require("ui/uimanager")

local Screen = Device.screen
if not Screen.eanabRefreshWithWaveform then
    logger.info("eink-settle: needs 2-eink-ande-order.lua (candidate launcher only), skipped")
    return
end
if lfs.attributes(DataStorage:getDataDir() .. "/eanab-settle.off", "mode") then
    logger.info("eink-settle: disabled by eanab-settle.off")
    return
end

local pending = false
local settling = false
local want_settle_refresh = false

local function readerOnTop()
    local ReaderUI = package.loaded["apps/reader/readerui"]
    local ui = ReaderUI and ReaderUI.instance
    return ui ~= nil and UIManager:getTopmostVisibleWidget() == ui, ui
end

local settle -- forward

local function cancel()
    if pending then
        UIManager:unschedule(settle)
        pending = false
    end
end

settle = function()
    pending = false
    local on_top, ui = readerOnTop()
    if not on_top then return end
    settling = true
    want_settle_refresh = true
    -- 重绘阅读界面；随后 UIManager 会调用 refreshUIImp，由下面的包装改用 GL16 下发
    UIManager:setDirty(ui, "ui")
    UIManager:forceRePaint()
    want_settle_refresh = false
    settling = false
end

local function schedule()
    cancel()
    UIManager:scheduleIn(SETTLE_DELAY, settle)
    pending = true
end

local screen_area = Screen:getWidth() * Screen:getHeight()

for _, name in ipairs({ "refreshFullImp", "refreshPartialImp", "refreshFlashPartialImp",
                        "refreshUIImp", "refreshFlashUIImp", "refreshFastImp" }) do
    local orig = Screen[name]
    if orig then
        Screen[name] = function(fb, x, y, w, h, ...)
            if want_settle_refresh and name == "refreshUIImp" then
                want_settle_refresh = false
                local bb = fb.full_bb or fb.bb
                local rx, ry, rw, rh = bb:getBoundedRect(x or 0, y or 0, w or fb:getWidth(), h or fb:getHeight())
                return fb:eanabRefreshWithWaveform(SETTLE_WAVEFORM, rx, ry, rw, rh)
            end
            if not settling then
                cancel()
            end
            local ret = orig(fb, x, y, w, h, ...)
            if name == "refreshPartialImp" and not settling then
                local area = (w or fb:getWidth()) * (h or fb:getHeight())
                if area >= screen_area * MIN_AREA_RATIO and readerOnTop() then
                    schedule()
                end
            end
            return ret
        end
    end
end
