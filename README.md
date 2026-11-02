# SD Gundam G Generation Cross Rays — iOS 移植

把 Switch 版《SD高达G世纪：火线纵横》Platinum Edition（含 31 个 DLC）移植到 iPhone / iPad / Mac。
**不是模拟器**：游戏自己的 ARM64 代码直接在 Apple 芯片上运行，只有 Apple 内核跑不了的指令被重写，
Horizon 系统服务由 Host 顶替，NVN 图形 API 重建在 Metal 上。

**自带游戏文件**（Bring your own game）：这个仓库不含任何游戏内容。

---

## 状态

| 平台 | 状态 |
|---|---|
| **iPhone 16 Pro**（A18 Pro，iOS 27） | ✅ 已验收 |
| **Mac**（Apple Silicon） | ✅ 已验收 |
| 游戏版本 | 1.6.3（v720896）+ 31 DLC |

- 60 fps，零丢帧
- 内存 footprint：Mac ~1.8 GB / iPhone ~1.3 GB
- 画面完整（标题、菜单、战斗、贴图、特效）
- 音频正常
- 触屏操作含完整按键布局，可全屏

---

## 怎么玩

```bash
# 1. 准备（一次性）
#    - 你的 prod.keys（自己 dump 的）
#    - Xcode 27.2 + MetalToolchain
#    - 游戏文件（XCI 或 NSP 文件夹）

# 2. Survey（可选，45 秒）
./run_nxnative.sh Game -k keys/prod.keys --survey-only

# 3. Mac 上跑
./run_nxnative.sh Game -k keys/prod.keys --platform mac
./play.sh

# 4. 打包 iOS
./run_nxnative.sh Game -k keys/prod.keys --romfs separate --prepare-xcode --team-id <TEAM_ID>
```

详细的移植流程见 [docs/PORTING-WORKFLOW.md](docs/PORTING-WORKFLOW.md)。

---

## 这个移植做了什么

在 [nxnative](https://github.com/seedds/nxnative) 的基础上，为这个游戏：

- 写了完整的 **game profile**（`nxnative/dm/games/010055700CEA8000/`，含 5 张 shader 表）
- 修了 **3 个启动/画面的硬阻塞**
- 加了 **2 个体验优化**（全屏、触屏布局）

### 三个硬阻塞

| # | 问题 | 根因 | 影响范围 |
|---|---|---|---|
| 1 | 启动即崩（`main+0x5cc508` 写 null） | `AllocateMemoryBlock` 返回 0——host 报的"已用内存"64 MB 小于模块实际 120 MB | 任何模块 > 64 MB 且用 `SetHeapSize` 的游戏 |
| 2 | 卡在 `nnMain` 早期（`sdk+0x62a78`） | `nn::fs::ReadFile` 有一个重载没 hook，调用落到 SDK 实现解引用假 handle | 任何 SDK 9+ 且用这个签名的游戏 |
| 3 | **全黑但有文字** | `NVN_TEXTURE_FLAGS_COMPRESSIBLE`(0x8) 让 `tex_init_fill` 跳过所有纹理上传 | ★ **任何给所有纹理设此标志 + 用 `SetStorage` 写内存的游戏** |

第 3 条是**通用 bug**，不只修了 Cross Rays。

### 两个体验优化

- **全屏**：iPhone 屏幕 2.174:1 vs 游戏 1.778:1。找到 iOS 端 `fit_16_9` 把视图约束成 16:9 的问题，加 `present_fill` 支持三种模式（letterbox / crop / stretch）。
- **触屏肩键贴边**：肩键原本用 `safe`（扣满 `safeAreaInsets`，横屏 59pt），改成 `corner`（只扣 50%），并缩小边距。

---

## shader 环节

1090 个 GLSLC 输出全部通过三重校验，最终 **639 个唯一 shader**（127 vs + 512 ps）。

```
1090 GLSLC → 639 唯一
           → SPIR-V:  639 ok / 0 failed   (1.3 s)
           → MSL:     639 ok / 0 failed   (2.1 s)
           → metallib (macOS): 1273 编译, 0 失败
           → metallib (iOS):   1272 编译, 0 失败
```

之所以这么干净，是因为这个游戏的结构和 **13 Sentinels: Aegis Rim**（已跑通）高度同构：
都是 SDK 9-11 + NVN + CRIWARE + **GLSLC 内嵌 main 只读段**。

---

## 已知限制

- **120 fps 做不到**：`fps_target` 改的是游戏引擎自己的帧率上限。Cross Rays 是 60 fps 游戏，强设 120 会让游戏跑 2 倍速。
- 某个教学画面有轻微贴图错位（文字重叠、色块），后续画面正常。未定位。
- 长时间运行（> 1 小时）的内存稳定性未测。
- 31 个 DLC 挂载正常，但内容未逐一验证。

---

## 文件结构

```
.
├── README.md                      # 本文件
├── play.sh                        # Mac 启动脚本
├── run_nxnative.sh                # 构建包装脚本
├── docs/
│   ├── PORTING-WORKFLOW.md        # ★ 移植任意 Switch 游戏的标准工作流
│   ├── CROSSRAYS-NOTES.md         # 本次移植的完整记录（5 个修复的推导过程）
│   └── MAC-TESTING.md             # 测试方法 + 键位表
├── profile/
│   └── 010055700CEA8000/          # ★ 这个游戏的 game profile + 5 张 shader 表
├── patches/
│   ├── nxnative-crossrays.patch   # ★ 对 nxnative 的 7 个文件改动（200 行）
│   └── README.md                  # 每个改动的用途
└── keys/                          # 你的 prod.keys（不进 git）
```

## 怎么用

```bash
# 1. 取 nxnative
git clone https://github.com/seedds/nxnative.git
cd nxnative && git apply ../patches/nxnative-crossrays.patch

# 2. 放入 profile
cp -R ../profile/010055700CEA8000 dm/games/

# 3. 准备游戏文件（你自己的 XCI/NSP）+ prod.keys，然后
cd ..
./run_nxnative.sh Game -k keys/prod.keys --platform mac    # Mac 上跑
./run_nxnative.sh Game -k keys/prod.keys --romfs separate  # 打 iOS 包
```

完整的移植流程见 [docs/PORTING-WORKFLOW.md](docs/PORTING-WORKFLOW.md)。

---

## 许可

MIT。第三方代码保留各自许可（见 `nxnative/dm/third_party/`）。

与 Nintendo、Bandai Namco 无关。需要你自己合法拥有的游戏文件和主机密钥。
