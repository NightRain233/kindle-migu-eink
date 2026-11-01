# DU4/DU 字体清晰度复测（2026-10-31）

## 结论

字体发虚主要来自两部分：快波形减少了可表达的灰阶，KOReader 的抗锯齿边缘因此变浅；另外，直接改 `metadata.epub.lua` 后如果继续命中同一个 CR3 排版缓存，字体参数不会重新栅格化，看起来就像 gamma 或字重参数失效。

当前设备的推荐组合是：

```text
SurfaceFlinger waveform = DU4 (7)
font_face               = LXGW WenKai
font_base_weight        = +1
font_gamma              = 25–30
font_hinting            = 1
```

DU(1) 仍是 1-bit 快波形，无法靠字体设置恢复抗锯齿灰边；它适合追求速度的场景，不适合中文正文长期阅读。DU4(7) 保留 4 级灰度，配合渲染侧加粗和提高 gamma 后，速度与字重更平衡。

## 实机复测

测试对象为 `/sdcard/Books/挽救计划.sdr/metadata.epub.lua`，每次修改后删除对应 CR3 文件并重开同一本书。字体使用 FontList 识别出的内部家族名 `LXGW WenKai`，DU4 保持不变。

| gamma | base weight | 暗像素（同一测试页） | 观感 |
|---:|---:|---:|---|
| 10 | +1 | 32,651 | 较淡 |
| 15 | +1 | 35,320 | 默认对比度 |
| 25 | +1 | 39,377 | 清晰，推荐起点 |
| 30 | +1 | 41,992 | 更实，当前配置 |
| 36 | +1 | 44,166 | 最黑，边缘开始偏硬 |

`base_weight=+3` 的笔画明显过重，且会改变分页；`hinting=0/1/2` 在 26 px 中文上的差异很小，`1` 可作为稳定默认值。当前设备已应用 `DU4 + LXGW WenKai + base_weight=1 + gamma=30 + hinting=1`，并保留了：

```text
/sdcard/koreader/settings.reader.lua.bak-fontclarity-20261031
/sdcard/Books/挽救计划.sdr/metadata.epub.lua.bak-fontclarity-20261031
```

《13.67》原来单独保存的是 `STSongBold + gamma15 + base_weight0`，所以不会继承全局设置；
而且这个宋体的细笔画在 DU4 下仍然偏虚。现在也改为同一套 `LXGW WenKai + base_weight1 + gamma30 + hinting1`，原设置保存在：

```text
/sdcard/Books/13.67.sdr/metadata.epub.lua.bak-fontclarity-20261031
```

## 字体名称注意

KOReader FontList 记录的家族名不是文件名。当前外部字体对应关系为：

| 文件 | 应使用的 `font_face` |
|---|---|
| `LXGWWenKai-Regular.ttf` | `LXGW WenKai` |
| `STSongMedium.ttf` | `STBShusong` |
| `STSongBold.ttf` | `STBShusong-Bold` |
| `MYingHeiTMedium.ttf` | `MYing Hei T` |

使用文件名别名会触发回退字体或让对比实验失真。`font_base_weight` 的取值是相对 Regular(400) 的增量：`+1` 对应 Medium(500)，`+3` 对应 Bold(700)。

## 以后改参数的正确步骤

优先在 KOReader 菜单里改“Contrast / Font Weight”，让它自己失效缓存。如果直接编辑书籍 metadata，需删除该书 `cache_file_path` 指向的 `.cr3` 文件，再重开书；否则旧的字形位图会继续被复用。

