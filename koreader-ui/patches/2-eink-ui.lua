--[[
eanab 界面细节（late 补丁）：
  1. 给思源黑体 Medium 登记真粗体 Bold，粗体文字不再靠合成加粗；
  2. 开关按钮选中态改为纯黑底白字（DU 快速刷新只有黑白两级，灰底会被压坏）；
  3. 所有列表只有一页时隐藏底部翻页栏；
  4. 阅读底栏文字改为中文短句：“本章还剩 N 页”、低电量才显示电量。
删除本文件即可恢复原样。
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")

-- 1. 真粗体
do
    local regular, bold = "NotoSansCJKsc-Medium.otf", "NotoSansCJKsc-Bold.otf"
    Font.bold_font_variant[regular] = bold
    Font.regular_font_variant[bold] = regular
end

-- 2. 开关按钮
do
    local ToggleSwitch = require("ui/widget/toggleswitch")
    ToggleSwitch.fgcolor = Blitbuffer.COLOR_BLACK
end

-- 3. 单页列表不显示翻页栏
do
    local Menu = require("ui/widget/menu")
    local orig_updatePageInfo = Menu.updatePageInfo
    Menu.updatePageInfo = function(self, select_number)
        orig_updatePageInfo(self, select_number)
        -- 所有列表（书库、目录、书签、历史……）只有一页时都不显示翻页栏
        if #self.item_table > 0 and (self.page_num or 1) <= 1 then
            self.page_info_text:setText("")
            self.page_info_left_chev:hide()
            self.page_info_right_chev:hide()
            self.page_info_first_chev:hide()
            self.page_info_last_chev:hide()
        end
    end
end

-- 4. 阅读底栏
do
    local ReaderFooter = require("apps/reader/modules/readerfooter")
    local gen = ReaderFooter.textGeneratorMap
    if gen then
        gen.pages_left = function(footer)
            local left = footer.ui.toc:getChapterPagesLeft(footer.pageno)
            local in_chapter = left ~= nil
            if not in_chapter then
                left = footer.ui.document:getTotalPagesLeft(footer.pageno)
            end
            if footer.settings.pages_left_includes_current_page then
                left = left + 1
            end
            if left <= 0 then
                return in_chapter and "本章最后一页" or "最后一页"
            end
            return (in_chapter and "本章还剩 %d 页" or "全书还剩 %d 页"):format(left)
        end
        gen.battery = function(footer)
            if not Device:hasBattery() then return "" end
            local powerd = Device:getPowerDevice()
            local level = powerd:getCapacity()
            local threshold = footer.settings.battery_hide_threshold or 20
            if powerd:isCharging() then
                return ("充电中 %d%%"):format(level)
            end
            if level > threshold then return "" end
            return ("电量 %d%%"):format(level)
        end
    end
end
