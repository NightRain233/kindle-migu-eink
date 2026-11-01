--[[
eanab 界面字体（early 补丁）。

原版界面主字体是 NotoSans（只有西文），中文全部靠 NotoSansCJKsc 回退显示，
中英文粗细、基线都对不齐。这里把界面字体统一换成思源黑体（Noto Sans CJK SC）：
  - 常规文字用 Medium：DU4 只有 4 级灰，Regular 的 1 px 笔画容易被量化成浅灰；
  - 标题与粗体用 Bold（真粗体，不靠合成加粗）。
等宽字体（输入框、快捷键）保持原样。

字体文件放在 koreader/fonts/ 下，由 FontList 搜索到。
reader.lua 会在启动时把全局 `fontmap` 合并进 Font.fontmap。
删除本文件即可恢复原样。
--]]

local MEDIUM = "NotoSansCJKsc-Medium.otf"
local BOLD = "NotoSansCJKsc-Bold.otf"

-- luacheck: globals fontmap
fontmap = {
    cfont = MEDIUM,
    tfont = BOLD,
    smalltfont = BOLD,
    x_smalltfont = BOLD,
    ffont = MEDIUM,
    smallffont = MEDIUM,
    largeffont = MEDIUM,
    rifont = MEDIUM,
    pgfont = MEDIUM,
    hfont = MEDIUM,
    infofont = MEDIUM,
    smallinfofont = MEDIUM,
    smallinfofontbold = BOLD,
    x_smallinfofont = MEDIUM,
    xx_smallinfofont = MEDIUM,
}
