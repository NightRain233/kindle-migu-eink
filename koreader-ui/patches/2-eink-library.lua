--[[
eanab 书库（late 补丁）。

替换 coverbrowser 插件“详细列表”模式的排版：
  - 标题栏：左对齐大标题“书库”，副标题显示藏书数量；
  - 主目录第一页顶部是“继续阅读”卡片（上次打开的书：大封面、进度条、上次阅读时间）；
  - 下面的书架按最近阅读排序，每行：封面 / 书名（粗体）/ 作者 · 上次阅读时间 / 右侧进度；
  - 封面统一转灰度并用 4×4 有序抖动压到 DU4 的 4 级灰（DITHER_COVERS 可关）。

只挂钩 ListMenu 的两个排版函数和 FileManager 的标题栏；数据仍来自 coverbrowser
的缓存（BookInfoManager）、KOReader 的阅读记录（ReadHistory）和书籍侧边文件（BookList）。
删除本文件即可恢复原样。
--]]

local DITHER_COVERS = true

local userpatch = require("userpatch")
local logger = require("logger")
local DataStorage = require("datastorage")

-- 出错时写日志（本机 logcat 里看不到 KOReader 的 Lua 日志）
local function logError(where, err)
    logger.warn("eink-library:", where, err)
    local f = io.open(DataStorage:getDataDir() .. "/eanab-ui-error.log", "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S"), " ", where, "\n", tostring(err), "\n\n")
        f:close()
    end
end

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local RenderImage = require("ui/renderimage")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local FileManager = require("apps/filemanager/filemanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Screen = Device.screen

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local DIM = Blitbuffer.Color8(0x55)   -- 次要文字
local LINE = Blitbuffer.Color8(0xAA)  -- 分隔线

local S = function(v) return Screen:scaleBySize(v) end

local PAD = S(18)              -- 页面左右留白
local GAP = S(14)              -- 封面与文字的间距
local ROW_MIN_H = S(70)        -- 书架每行最小高度
local HERO_COVER_W = S(104)
local HERO_COVER_H = S(150)
local HERO_LABEL_H = S(40)
local HERO_H = HERO_LABEL_H + HERO_COVER_H + S(14)
local SECTION_H = S(42)

-- 所有封面按同一规格缓存，避免卡片和列表来回触发重新提取
local COVER_SPECS = { max_cover_w = HERO_COVER_W, max_cover_h = HERO_COVER_H }

---------------------------------------------------------------------------
-- 小工具
---------------------------------------------------------------------------

local function isHome(path)
    if not path then return false end
    local home = filemanagerutil.getHomeFolder()
    if not home then return false end
    home = home:gsub("/+$", "")
    return path:gsub("/+$", "") == home
end

local function historyTimes()
    local times = {}
    local ok, ReadHistory = pcall(require, "readhistory")
    if ok and ReadHistory.hist then
        for _, h in ipairs(ReadHistory.hist) do
            if h.file and not times[h.file] then
                times[h.file] = h.time
            end
        end
    end
    return times
end

local function whenText(ts)
    if not ts or ts <= 0 then return nil end
    local now = os.time()
    local t = os.date("*t", now)
    local midnight = os.time{ year = t.year, month = t.month, day = t.day, hour = 0 }
    if ts >= midnight then
        return "今天 " .. os.date("%H:%M", ts)
    elseif ts >= midnight - 86400 then
        return "昨天"
    end
    local days = math.floor((midnight - ts) / 86400) + 1
    if days < 7 then
        return days .. " 天前"
    end
    local d = os.date("*t", ts)
    if d.year == t.year then
        return d.month .. " 月 " .. d.day .. " 日"
    end
    return d.year .. " 年 " .. d.month .. " 月"
end

local function firstAuthor(authors)
    if not authors or authors == "" then return nil end
    if authors:find("\n") then
        local list = util.splitToArray(authors, "\n")
        if #list > 1 then
            return list[1] .. " 等"
        end
        return list[1]
    end
    return authors
end

local function joinDot(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v and v ~= "" then table.insert(parts, v) end
    end
    return table.concat(parts, " · ")
end

local function face(size, name)
    return Font:getFace(name or "cfont", size)
end

---------------------------------------------------------------------------
-- 封面：缩放 → 灰度 → 4 级有序抖动；结果按 文件+尺寸 缓存
---------------------------------------------------------------------------

local BAYER4 = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }

local function ditherTo4Levels(bb)
    local w, h = bb:getWidth(), bb:getHeight()
    for y = 0, h - 1 do
        local row = (y % 4) * 4 + 1
        for x = 0, w - 1 do
            local p = bb:getPixelP(x, y)
            local q = p[0].a / 85
            local base = math.floor(q)
            if base < 3 and (q - base) > (BAYER4[row + x % 4] + 0.5) / 16 then
                base = base + 1
            end
            p[0].a = base * 85
        end
    end
end

local cover_cache = {}
local cover_cache_n = 0

local function clearCoverCache()
    for _, bb in pairs(cover_cache) do
        bb:free()
    end
    cover_cache = {}
    cover_cache_n = 0
end

-- 返回 ImageWidget（或 nil）。bookinfo.cover_bb 在这里被释放。
local function coverImage(filepath, bookinfo, max_w, max_h)
    local src = bookinfo.cover_bb
    if not (bookinfo.has_cover and not bookinfo.ignore_cover and src) then
        if src then src:free() end
        return nil
    end
    local sw, sh = src:getWidth(), src:getHeight()
    local scale = math.min(max_w / sw, max_h / sh)
    local w = math.max(1, math.floor(sw * scale + 0.5))
    local h = math.max(1, math.floor(sh * scale + 0.5))
    local key = table.concat({ filepath, w, h, DITHER_COVERS and "d" or "g" }, "|")
    local bb = cover_cache[key]
    if not bb then
        local scaled = RenderImage:scaleBlitBuffer(src, w, h, false)
        bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
        bb:blitFrom(scaled, 0, 0, 0, 0, w, h)
        if scaled ~= src then scaled:free() end
        if DITHER_COVERS then
            ditherTo4Levels(bb)
        end
        if cover_cache_n >= 48 then clearCoverCache() end
        cover_cache[key] = bb
        cover_cache_n = cover_cache_n + 1
    end
    src:free()
    return ImageWidget:new{ image = bb, image_disposable = false }
end

-- 封面盒子：固定宽高，图片居中并带 1px 黑框；没有封面时画书名首字
local function coverBox(img, box_w, box_h, title, glyph_size)
    local inner
    if img then
        local size = img:getSize()
        inner = FrameContainer:new{
            bordersize = Size.border.thin,
            color = BLACK,
            margin = 0,
            padding = 0,
            width = size.w + 2 * Size.border.thin,
            height = size.h + 2 * Size.border.thin,
            img,
        }
    else
        local glyph = title and util.splitToChars(title)[1] or "书"
        local fw, fh = math.floor(box_h * 0.7), box_h
        if fw > box_w then fw = box_w end
        inner = FrameContainer:new{
            bordersize = Size.border.thin,
            color = BLACK,
            margin = 0,
            padding = 0,
            width = fw,
            height = fh,
            CenterContainer:new{
                dimen = Geom:new{ w = fw - 2 * Size.border.thin, h = fh - 2 * Size.border.thin },
                TextWidget:new{ text = glyph, face = face(glyph_size), bold = true },
            },
        }
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = box_w, h = box_h },
        inner,
    }
end

-- 统一的书籍数据读取（与原 ListMenuItem 相同的缓存有效性判断）
local BookInfoManager -- 由插件补丁时注入
local BookList = require("ui/widget/booklist")

local function loadBookInfo(filepath, deleted)
    local bookinfo = BookInfoManager:getBookInfo(filepath, true)
    if bookinfo and not bookinfo.ignore_cover and not deleted then
        if bookinfo.cover_fetched then
            if bookinfo.has_cover and BookInfoManager.isCachedCoverInvalid(bookinfo, COVER_SPECS) then
                if bookinfo.cover_bb then bookinfo.cover_bb:free() end
                bookinfo = nil
            end
        else
            if bookinfo.cover_bb then bookinfo.cover_bb:free() end
            bookinfo = nil
        end
    end
    return bookinfo
end

local function displayTitle(bookinfo, filepath)
    local _, filename = util.splitFilePathName(filepath)
    local name = filemanagerutil.splitFileNameType(filename)
    if bookinfo and bookinfo.title and not bookinfo.ignore_meta then
        return bookinfo.title
    end
    return name
end

local function progressText(book_info)
    if book_info.status == "complete" then
        return "读完"
    elseif book_info.status == "abandoned" then
        return "搁置"
    elseif book_info.percent_finished then
        return ("%d%%"):format(math.floor(100 * book_info.percent_finished))
    elseif not book_info.been_opened then
        return "新"
    end
    return ""
end

---------------------------------------------------------------------------
-- 安装：等 coverbrowser 插件实例化后替换 ListMenu 的排版函数
---------------------------------------------------------------------------

local installed = false

local function install(plugin_bim)
    BookInfoManager = plugin_bim
    local ListMenu = require("listmenu")
    local orig_build = ListMenu._updateItemsBuildUI
    local orig_recalc = ListMenu._recalculateDimen
    local ListMenuItem = userpatch.getUpValue(orig_build, "ListMenuItem")
    if not ListMenuItem then
        logger.warn("eink-library: ListMenuItem not found, skipped")
        return
    end

    -----------------------------------------------------------------------
    -- 书架行
    -----------------------------------------------------------------------
    local Row = ListMenuItem:extend{}

    function Row:paintTo(bb, x, y)
        InputContainer.paintTo(self, bb, x, y)
    end

    function Row:update()
        local dimen = Geom:new{ w = self.width, h = self.height - 2 * self.underline_h }
        local box_h = dimen.h - 2 * S(7)
        local box_w = math.floor(box_h * 0.72)
        self.menu.cover_specs = COVER_SPECS
        self.is_directory = not (self.entry.is_file or self.entry.file)

        local title, meta, right, cover
        if self.is_directory then
            title = self.text:gsub("/$", "")
            meta = self.mandatory or "文件夹"
            right = "›"
            cover = coverBox(nil, box_w, box_h, "▤", 20)
        else
            self.file_deleted = self.entry.dim
            local bookinfo = loadBookInfo(self.filepath, self.file_deleted)
            local book_info = self.menu.getBookInfo and self.menu.getBookInfo(self.filepath) or BookList.getBookInfo(self.filepath)
            self.been_opened = book_info.been_opened
            if not bookinfo then
                if self.init_done then return end
                self.cover_specs = COVER_SPECS
                title = displayTitle(nil, self.filepath)
                local missing = lfs.attributes(self.filepath, "mode") ~= "file"
                meta = missing and "（文件已删除）" or "正在读取…"
                right = ""
                cover = coverBox(nil, box_w, box_h, title, 18)
            else
                self.bookinfo_found = true
                title = displayTitle(bookinfo, self.filepath)
                local times = self.menu._eink_times or {}
                meta = joinDot(firstAuthor(not bookinfo.ignore_meta and bookinfo.authors or nil),
                               whenText(times[self.filepath]))
                if meta == "" then meta = " " end
                right = progressText(book_info)
                -- dim 既表示历史里已删除的书，也表示多选模式下被选中的书：封面照常显示，只把文字变灰
                local img = coverImage(self.filepath, bookinfo, box_w, box_h)
                if img then
                    self.menu._has_cover_images = true
                    self._has_cover_image = true
                end
                cover = coverBox(img, box_w, box_h, title, 18)
            end
        end

        local fg = self.file_deleted and DIM or BLACK
        local wright
        if right == "新" then
            wright = FrameContainer:new{
                bordersize = Size.border.thin,
                color = BLACK,
                radius = S(3),
                margin = 0,
                padding = 0,
                padding_left = S(5),
                padding_right = S(5),
                TextWidget:new{ text = right, face = face(13), bold = true },
            }
        else
            wright = TextWidget:new{
                text = right,
                face = face(16),
                bold = right ~= "读完" and right ~= "搁置",
                fgcolor = (right == "读完" or right == "搁置") and DIM or fg,
            }
        end
        local right_w = wright:getSize().w
        local text_x = PAD + box_w + GAP
        local col_w = dimen.w - text_x - PAD - (right_w > 0 and (right_w + GAP) or 0)
        self.menu._eink_text_x = text_x

        local wtitle = TextWidget:new{
            text = title, face = face(19), bold = true, fgcolor = fg, max_width = col_w,
        }
        local wmeta = TextWidget:new{
            text = meta, face = face(14), fgcolor = DIM, max_width = col_w,
        }
        local widget = OverlapGroup:new{
            dimen = dimen:copy(),
            LeftContainer:new{
                dimen = dimen:copy(),
                HorizontalGroup:new{
                    align = "center",
                    HorizontalSpan:new{ width = PAD },
                    cover,
                    HorizontalSpan:new{ width = GAP },
                    VerticalGroup:new{
                        align = "left",
                        wtitle,
                        VerticalSpan:new{ width = S(5) },
                        wmeta,
                    },
                },
            },
            RightContainer:new{
                dimen = dimen:copy(),
                HorizontalGroup:new{
                    wright,
                    HorizontalSpan:new{ width = PAD },
                },
            },
        }

        if self._underline_container[1] then
            self._underline_container[1]:free()
        end
        self._underline_container[1] = VerticalGroup:new{
            VerticalSpan:new{ width = self.underline_h },
            widget,
        }
    end

    -----------------------------------------------------------------------
    -- 继续阅读卡片
    -----------------------------------------------------------------------
    local Hero = InputContainer:extend{
        entry = nil,
        menu = nil,
        width = nil,
        height = nil,
        init_done = false,
        bookinfo_found = false,
    }

    function Hero:init()
        self.filepath = self.entry.path or self.entry.file
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
        self.ges_events = {
            TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
            HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
        }
        self[1] = FrameContainer:new{
            bordersize = 0, padding = 0, margin = 0,
            width = self.width, height = self.height,
            VerticalSpan:new{ width = self.height },
        }
        self:update()
        self.init_done = true
    end

    function Hero:update()
        local bookinfo = loadBookInfo(self.filepath, false)
        if not bookinfo and self.init_done then return end
        local book_info = self.menu.getBookInfo and self.menu.getBookInfo(self.filepath) or BookList.getBookInfo(self.filepath)
        local title = displayTitle(bookinfo, self.filepath)
        local col_w = self.width - 2 * PAD - HERO_COVER_W - GAP

        local img
        if bookinfo then
            self.bookinfo_found = true
            img = coverImage(self.filepath, bookinfo, HERO_COVER_W, HERO_COVER_H)
            if img then
                self.menu._has_cover_images = true
                self._has_cover_image = true
            end
        else
            self.cover_specs = COVER_SPECS
        end

        local wtitle = TextBoxWidget:new{
            text = title, face = face(23), bold = true, width = col_w, alignment = "left",
        }
        local two_lines = wtitle:getSize().h > wtitle:getLineHeight() * 1.5
        if wtitle:getSize().h > 2 * wtitle:getLineHeight() + 1 then
            local lh = wtitle:getLineHeight()
            wtitle:free(true)
            wtitle = TextBoxWidget:new{
                text = title, face = face(23), bold = true, width = col_w, alignment = "left",
                height = 2 * lh, height_adjust = true, height_overflow_show_ellipsis = true,
            }
        end

        local column = VerticalGroup:new{ align = "left" }
        table.insert(column, wtitle)
        local author = bookinfo and not bookinfo.ignore_meta and firstAuthor(bookinfo.authors)
        if author then
            table.insert(column, VerticalSpan:new{ width = two_lines and S(3) or S(6) })
            table.insert(column, TextWidget:new{ text = author, face = face(15), fgcolor = DIM, max_width = col_w })
        end
        local pct = book_info.percent_finished or 0
        if book_info.status == "complete" then pct = 1 end
        -- 书名两行时收紧间距，让右栏不超出封面高度
        table.insert(column, VerticalSpan:new{ width = two_lines and S(10) or S(18) })
        table.insert(column, ProgressWidget:new{
            width = col_w,
            height = S(8),
            percentage = pct,
            margin_h = 0,
            margin_v = 0,
            radius = 0,
            bordersize = Size.border.thin,
            bordercolor = BLACK,
            bgcolor = WHITE,
            fillcolor = BLACK,
        })
        table.insert(column, VerticalSpan:new{ width = S(8) })
        local pages = book_info.pages or (bookinfo and bookinfo.pages)
        local status_line
        if book_info.status == "complete" then
            status_line = "已读完"
        elseif book_info.percent_finished then
            status_line = ("已读 %d%%"):format(math.floor(100 * pct))
        else
            status_line = "尚未开始"
        end
        table.insert(column, TextWidget:new{
            text = joinDot(status_line, pages and ("共 " .. pages .. " 页") or nil),
            face = face(15), max_width = col_w,
        })
        local when = whenText((self.menu._eink_times or {})[self.filepath])
        if when then
            table.insert(column, VerticalSpan:new{ width = S(4) })
            table.insert(column, TextWidget:new{
                text = "上次阅读 " .. when, face = face(14), fgcolor = DIM, max_width = col_w,
            })
        end

        local content = VerticalGroup:new{
            align = "left",
            LeftContainer:new{
                dimen = Geom:new{ w = self.width, h = HERO_LABEL_H },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = PAD },
                    TextWidget:new{ text = "继续阅读", face = face(15), bold = true },
                },
            },
            HorizontalGroup:new{
                align = "top",
                HorizontalSpan:new{ width = PAD },
                coverBox(img, HERO_COVER_W, HERO_COVER_H, title, 40),
                HorizontalSpan:new{ width = GAP },
                column,
            },
        }
        if self[1][1] and self[1][1].free then self[1][1]:free() end
        self[1][1] = content
    end

    function Hero:onTapSelect()
        self.menu:onMenuSelect(self.entry)
        return true
    end

    function Hero:onHoldSelect()
        self.menu:onMenuHold(self.entry)
        return true
    end

    -----------------------------------------------------------------------
    -- 排版
    -----------------------------------------------------------------------
    local function sectionLabel(width, text)
        return LeftContainer:new{
            dimen = Geom:new{ w = width, h = SECTION_H },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = PAD },
                TextWidget:new{ text = text, face = face(15), bold = true },
            },
        }
    end

    local function separator(width, text_x)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = text_x },
            LineWidget:new{
                dimen = Geom:new{ w = width - text_x - PAD, h = Size.line.thin },
                background = LINE,
            },
        }
    end

    local function new_recalc(self)
        self.eink_hide_single_page = true
        self.portrait_mode = Screen:getWidth() <= Screen:getHeight()
        self.others_height = 0
        if self.title_bar then
            if not self.is_borderless then
                self.others_height = self.others_height + 2
            end
            if not self.no_title then
                self.others_height = self.others_height + self.title_bar.dimen.h
            end
            if self.page_info then
                self.others_height = self.others_height + self.page_info:getSize().h
            end
        else
            self.page_recalc_needed_next_time = true
            self.itemnum_orig = self.path_items and self.path_items[self.path]
            self.focused_path_orig = self.focused_path
        end
        local available_height = self.inner_dimen.h - self.others_height - Size.line.thin

        -- 文件管理器里：最近读过的排前面；主目录第一页放“继续阅读”
        self._eink_times = historyTimes()
        self._eink_hero = nil
        local display = self.item_table
        if self.name == "filemanager" then
            local times = self._eink_times
            local dirs, files = {}, {}
            for i, e in ipairs(self.item_table) do
                e._eink_order = i
                if e.is_file then table.insert(files, e) else table.insert(dirs, e) end
            end
            table.sort(files, function(a, b)
                local ta, tb = times[a.path] or 0, times[b.path] or 0
                if ta ~= tb then return ta > tb end
                return a._eink_order < b._eink_order
            end)
            local sorted = {}
            for _, e in ipairs(dirs) do table.insert(sorted, e) end
            for _, e in ipairs(files) do table.insert(sorted, e) end
            for i, e in ipairs(sorted) do self.item_table[i] = e end

            local selecting = self.ui and self.ui.selected_files
            if isHome(self.path) and not selecting and #files > 0 then
                -- 与书架排序一致：阅读记录里最近的一本；没有阅读记录时才用 lastfile
                -- （设备上有多个 KOReader 包共用目录，lastfile 可能不是最近读的那本）
                if times[files[1].path] then
                    self._eink_hero = files[1]
                else
                    local last = G_reader_settings:readSetting("lastfile")
                    for _, e in ipairs(files) do
                        if e.path == last then self._eink_hero = e break end
                    end
                end
            end
            if self._eink_hero then
                display = {}
                for _, e in ipairs(self.item_table) do
                    if e ~= self._eink_hero then table.insert(display, e) end
                end
            end
            if self.ui and self.ui.title_bar and isHome(self.path) then
                self.ui.title_bar:setSubTitle(("共 %d 本"):format(#files), true)
            end
        end
        self._eink_display = display

        local rows_height = available_height
        if self._eink_hero then
            rows_height = rows_height - HERO_H - SECTION_H
        end
        self.perpage = math.max(1, math.floor(rows_height / ROW_MIN_H))
        self.files_per_page = self.perpage
        self.page_num = math.max(1, math.ceil(#display / self.perpage))
        if #self.item_table == 0 then self.page_num = 0 end
        if self.page_num > 0 and self.page > self.page_num then self.page = self.page_num end

        self.item_height = math.floor(rows_height / self.perpage) - Size.line.thin
        self.item_width = self.inner_dimen.w
        self.item_dimen = Geom:new{ x = 0, y = 0, w = self.item_width, h = self.item_height }

        if self.page_recalc_needed then
            if #display > 0 then
                self.page = math.ceil((self.itemnum_orig or 1) / self.perpage)
            end
            if self.focused_path_orig then
                for num, item in ipairs(display) do
                    if item.path == self.focused_path_orig then
                        self.page = math.floor((num - 1) / self.perpage) + 1
                        break
                    end
                end
            end
            if self.page_num > 0 and self.page > self.page_num then self.page = self.page_num end
            if self.page < 1 then self.page = 1 end
            self.page_recalc_needed = nil
            self.itemnum_orig = nil
            self.focused_path_orig = nil
        end
        if self.page_recalc_needed_next_time then
            self.page_recalc_needed = true
            self.page_recalc_needed_next_time = nil
        end
    end

    local function new_build(self)
        local display = self._eink_display or self.item_table
        local width = self.item_width

        if self.page == 1 and self._eink_hero then
            local hero = Hero:new{
                entry = self._eink_hero,
                menu = self,
                width = width,
                height = HERO_H,
                show_parent = self.show_parent,
            }
            table.insert(self.item_group, hero)
            table.insert(self.layout, { hero })
            if not hero.bookinfo_found then
                table.insert(self.items_to_update, hero)
            end
            table.insert(self.item_group, sectionLabel(width, "书架"))
        end

        local index_of = {}
        for i, e in ipairs(self.item_table) do index_of[e] = i end
        local offset = (self.page - 1) * self.perpage
        local text_x
        for idx = 1, self.perpage do
            local entry = display[offset + idx]
            if entry == nil then break end
            entry.idx = index_of[entry] or (offset + idx)
            if idx > 1 then
                table.insert(self.item_group, separator(width, text_x or PAD))
            end
            local item = Row:new{
                height = self.item_height,
                width = width,
                entry = entry,
                text = entry.text,
                show_parent = self.show_parent,
                mandatory = entry.mandatory,
                dimen = self.item_dimen:copy(),
                menu = self,
                do_cover_image = true,
            }
            text_x = text_x or self._eink_text_x
            table.insert(self.item_group, item)
            table.insert(self.layout, { item })
            if not item.bookinfo_found and not item.is_directory and not item.file_deleted then
                table.insert(self.items_to_update, item)
            end
        end
        return nil
    end

    -- 安全网：新排版任何一步出错，记日志并永久退回原版列表，绝不让 KOReader 崩溃
    local broken = false
    local raw_recalc, raw_build = new_recalc, new_build
    local function guarded_recalc(self, ...)
        if not broken then
            local ok, err = xpcall(raw_recalc, debug.traceback, self, ...)
            if ok then return end
            broken = true
            logError("recalc", err)
        end
        self.eink_hide_single_page = nil
        return orig_recalc(self, ...)
    end
    local function guarded_build(self, ...)
        if not broken then
            local ok, ret = xpcall(raw_build, debug.traceback, self, ...)
            if ok then return ret end
            broken = true
            logError("build", ret)
            self.item_group:clear()
            self.layout = {}
            self.items_to_update = {}
            self.eink_hide_single_page = nil
            orig_recalc(self)
        end
        return orig_build(self, ...)
    end
    for _, cls in ipairs({ Row, Hero }) do
        local update = cls.update
        cls.update = function(self, ...)
            local ok, err = xpcall(update, debug.traceback, self, ...)
            if not ok then
                logError("update " .. tostring(self.filepath), err)
                if not self.init_done then error(err, 0) end
            end
        end
    end
    new_recalc, new_build = guarded_recalc, guarded_build

    ListMenu._recalculateDimen = new_recalc
    ListMenu._updateItemsBuildUI = new_build

    -- 插件实例化时已把旧函数拷到 FileChooser 上，这里换成新的
    local FileChooser = require("ui/widget/filechooser")
    if FileChooser._updateItemsBuildUI == orig_build then
        FileChooser._updateItemsBuildUI = new_build
    end
    if FileChooser._recalculateDimen == orig_recalc then
        FileChooser._recalculateDimen = new_recalc
    end
    installed = true
end

userpatch.registerPatchPluginFunc("coverbrowser", function(plugin)
    if installed then return end
    local ok, err = pcall(install, require("bookinfomanager"))
    if not ok then
        logger.warn("eink-library: install failed:", err)
    end
end)

---------------------------------------------------------------------------
-- 文件管理器标题栏：左对齐大标题
---------------------------------------------------------------------------

FileManager.title = "书库"

local orig_setupLayout = FileManager.setupLayout
FileManager.setupLayout = function(self, ...)
    TitleBar.new = function(cls, o)
        if o and o.left_icon == "home" then
            o.align = "left"
            o.title_face = Font:getFace("tfont", 26)
            o.subtitle_face = Font:getFace("cfont", 14)
            o.subtitle_fullwidth = false
            o.title_top_padding = S(10)
            o.bottom_v_padding = S(10)
        end
        return Widget.new(cls, o)
    end
    local ok, err = pcall(orig_setupLayout, self, ...)
    TitleBar.new = nil
    if not ok then error(err) end
end

local orig_updateTitleBarPath = FileManager.updateTitleBarPath
FileManager.updateTitleBarPath = function(self, path)
    path = path or self.file_chooser.path
    if isHome(path) then
        local n = 0
        for _, e in ipairs(self.file_chooser.item_table or {}) do
            if e.is_file then n = n + 1 end
        end
        self.title_bar:setSubTitle(("共 %d 本"):format(n))
    else
        orig_updateTitleBarPath(self, path)
    end
end
FileManager.onPathChanged = FileManager.updateTitleBarPath
