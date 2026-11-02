# Cross Rays 移植记录

SD GUNDAM G GENERATION CROSS RAYS（`010055700CEA8000`）Platinum Edition 的完整移植过程。
TOM CREATE / Bandai Namco，**SDK 9.4.1**，NVN，CRIWARE + 自研引擎。

工作流见 [PORTING-WORKFLOW.md](PORTING-WORKFLOW.md)，Mac 测试见 [MAC-TESTING.md](MAC-TESTING.md)。

---

## 最终状态

**已完成并验证：Mac 与 iPhone 16 Pro 双端可玩。**

| 项 | Mac (M5 Ultra) | iPhone 16 Pro (A18 Pro) |
|---|---|---|
| 画面 | ✅ 完整（标题、菜单、战斗、贴图） | ✅ 完整 |
| 帧率 | 60 fps | 60 fps，零丢帧 |
| 内存 | footprint ~1.8 GB | footprint ~1.3 GB |
| 音频 | ✅ | ✅ |
| 触屏操作 | — | ✅ 含肩键布局调整 |
| 全屏 | — | ✅ `Fill screen`（裁上下 9%） |
| RED 日志 | 0 条 | 0 条 |

用户验收："**完美**"。

---

## 五个修复

按发现顺序。前三个是**启动/画面**的硬阻塞，后两个是**体验优化**。

### 修复 1：`mem_used 0x8000000` —— 启动即崩

**症状**
```
[mem] SetHeapSize 0xc9400000 + modules 0x7800000 > app pool 0xcd500000
[dm] CRASH sig=11 addr=0 pc=main+0x5cc508
x8=0  x2=0xc9400000
```

反汇编 `main+0x5cc4e8`：
```asm
5cc4e8: ldr x9, [x20]        ; 全局堆管理器
5cc4ec: ldr x8, [x19]        ; x8 = *x19 = 0
5cc4fc: add x12, x8, x9
5cc508: str x10, [x8]        ; ← 向 null 写入
```

**根因**

`main+0x5cc4d0` 调的是 `nn::os::AllocateMemoryBlock`（用 `DT_JMPREL` 解析 GOT 槽 `0x156a6d8` 确认）。它从 heap 里划内存，返回 0 表示失败——**游戏没有检查返回值**。

而 heap 大小是 `nninitStartup` 用 `pool − used_memory` 算的。Host 报 `used = 64 MB`，但这个游戏的模块占 `0x7800000`（120 MB），所以 `SetHeapSize` 因 `ResultLimitReached` 失败。

**修法**：`game.tsv` 加
```tsv
mem_used	0x8000000
```

**参照**：`docs/reference/memory.md` 的 "Heap sized from the application pool less used memory"。
Hyrule Warriors: Age of Calamity（同为 SDK 9）用同样的方案（`0x4800000`）。

**通用性**：任何模块 > 64 MB 且用 `SetHeapSize` 的游戏都需要。

---

### 修复 2：`ReadFile` 重载缺失 —— 卡在 `nnMain` 早期

**症状**
```
[dbgfs] GetFileSize img h=0x400000000000039 -> 589868   ← 这个成功了
[dm] CRASH sig=11 addr=0x40000000000003b4 pc=sdk+0x62a78
x0=0x4000000000000390
```

`sdk+0x62a78` 是 `ldr w8, [x0, #0x24]`，`x0` 是垃圾值。

**定位过程**

1. 反汇编 `main+0x5cb328..0x5cb364`，看到三次调用：
```asm
5cb330: bl  0x79ad10   ; nn::fs::GetFileSize
5cb340: bl  0x5cc980   ; 按 size 分配
5cb360: bl  0x79ad20   ; ← 崩在它里面
```
2. 解析 `0x79ad20` 的 PLT 跳板 → GOT 槽 `0x156a460`
3. 用 `DT_JMPREL` 重定位表拿到符号名：

```python
for k in range(PLTRELSZ // 24):
    r_off, r_info, r_add = struct.unpack_from('<QQq', img, JMPREL + k*24)
    if r_off == 0x156a460:
        print(symname(r_info >> 32))
# → _ZN2nn2fs8ReadFileENS0_10FileHandleElPvmRKNS0_10ReadOptionE
```

4. 对比 host 的 `HLE_FORCE` 列表：

```
main 导入:  _ZN2nn2fs8ReadFileENS0_10FileHandleElPvmRKNS0_10ReadOptionE
host 有:    _ZN2nn2fs8ReadFileEPmNS0_10FileHandleElPvmRKNS0_10ReadOptionE
                                    ^^^ 多了 out 参数
```

**这个重载没有 hook。** 调用落到 `sdk` 自己的实现，它期望真实的 `FileAccessor*`，
而 host 的 handle 是合成编码（`1<<58 | mount<<32 | index`，给 guest 时左移 4）。

**修法**：`dm/host/hle_fs.c`
```c
HLE_FORCE("_ZN2nn2fs8ReadFileENS0_10FileHandleElPvmRKNS0_10ReadOptionE",
          "fsp-srv → pread(2) (overload with read options and no bytes-read output, which the host ignores)",
          Result, h_fs_ReadFileOpt2,
          uint64_t h, int64_t off, void *buf, size_t sz, const void *opt) {
    (void)opt; size_t got = 0; return h_fs_ReadFile(&got, h, off, buf, sz);
}
```

**效果**：修完后游戏从"启动即崩"直接跳到"60 fps 跑满"。

**通用性**：SDK 9 引入这个重载。任何 SDK 9+ 且用它加载资源的游戏都会中招。

---

### 修复 3：`COMPRESSIBLE` 挡住纹理上传 ★

**症状**：游戏 60 fps、62 draws/帧、零错误，但**全屏黑，只有文字**。

**诊断链**

```
① TextureInitialize=74                ← 只创建了 74 个纹理
② packaged textures: first uploads 0  ← 一个都没上传
③ [dbgtex] ser=214 2048x1024 fmt=0x44 tflags=0x8 any=1
                                       BC3        有数据
④ [dbgtex] ser=214 NEW texture fill=0  ← ★ 有数据但不上传
```

③④ 靠新加的 `DM_DBGTEX=1` 探针拿到。

**根因**

```c
// dm/gfx/nvn/nvn_mtl.m  tex_init_fill()
if (t->d.samples > 1 || (t->d.flags & NVN_TEXTURE_FLAGS_COMPRESSIBLE) || ...) return 0;
```
```c
// dm/gfx/nvn/include/nvn.h
NVN_TEXTURE_FLAGS_COMPRESSIBLE = 0x8
```

Cross Rays **给所有纹理都设了 `0x8`**。

这个标志在 Switch 上是**内存压缩提示**，不是数据格式——游戏仍然把普通纹素写进池。
Host 从不实现池压缩，所以这个排除条件对 host 没有实际保护作用，却把**所有**纹理的上传挡掉了。

**修法**
```c
// COMPRESSIBLE is a Switch memory-compression hint, not a data format: the game still
// writes plain texels into the pool. The host never implements pool compression, so
// skipping the fill on this flag left every texture of a game that sets it on all of
// them (SD GUNDAM G GENERATION CROSS RAYS, SDK 9.4.1) with content 0 — the whole
// screen black but for text.
if (t->d.samples > 1 || ((int)mt.pixelFormat >= 250 && (int)mt.pixelFormat <= 262)) return 0;
```

**效果**：`fill=0` → `fill=1`，BC3 贴图成功上传，**画面完全恢复**。

**通用性**：★ **最有价值的一条**。任何"给所有纹理设 COMPRESSIBLE + 用 `SetStorage` 自己写内存"的游戏都会中招。

---

### 修复 4：全屏（`present_fill`）

**问题**：iPhone 16 Pro 屏幕 2622x1206（2.174:1），游戏 1920x1080（1.778:1），左右各 239 px 黑边。

**根因有两层**

1. **iOS view 层**（真正的原因）：
```objc
// dm/ios/Sources/front_ios.m
static CGRect fit_16_9(CGRect b) {   // the largest centered 16:9 rectangle in b
    if (w / h > 16.0 / 9.0) w = h * 16.0 / 9.0;
    ...
}
```
整个游戏视图被约束成 16:9，所以 drawable 只有 **2144x1206**。黑边是**屏幕上的空白**，不是渲染结果。

2. **Metal viewport 层**：在 16:9 内部再居中。

只改第 2 层看不出来——第 1 层已经决定了可用区域。

**修法**

`dm/ios/Sources/front_ios.m`：
```objc
static BOOL present_fill_on(void) { const char *e = getenv("DM_PRESENT_FILL"); return e && *e; }
static CGRect game_rect(CGRect b) { return present_fill_on() ? b : fit_16_9(b); }
```

`dm/gfx/nvn/nvn_mtl.m`（`present_viewport`）：
```c
static int fill = -1; if (fill < 0) {
    const char *e = getenv("DM_PRESENT_FILL"); if (!e || !*e) e = DM_GAME_PRESENT_FILL;
    fill = !e || !*e ? 0 : !strcmp(e, "crop") ? 1 : !strcmp(e, "stretch") ? 2 : 0;
}
if (fill == 2) return (MTLViewport){0, 0, dw, dh, 0, 1};      // stretch
double s = fill == 1 ? fmax(dw/cw, dh/ch) : fmin(dw/cw, dh/ch); // crop : letterbox
```

`dm/games/game.py` 加 `present_fill` 键 → `#define DM_GAME_PRESENT_FILL "crop"`。

**三种模式**

| 模式 | 效果 | 代价 |
|---|---|---|
| `''`（letterbox） | 完整画面居中 | 左右黑边 239 px |
| **`crop`** | 填满，上下各切 9%（98 px / 1080） | 看不到画面上下边缘 |
| `stretch` | 填满 | 横向拉宽 22.3%，变形 |

默认 `crop`：形状正确，切掉的信息量最低（策略游戏上下边缘通常是背景）。

启动器加 `Screen fill` 设置，可随时切换。

---

### 修复 5：触屏肩键贴边

**问题**：截图显示 ZL/L/ZR/R 离屏幕边缘太远，而方向键和 ABXY 位置合适。

**根因**：两类控件用了不同的安全区矩形。

```objc
- (CGRect)safe   { return UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets); }              // 扣满
- (CGRect)corner { ... i.left *= K_CORNER_IN; i.right *= K_CORNER_IN; ... }                       // 只扣 50%
```

```objc
- (CGPoint)faceCenter { CGRect s = self.corner; ... }   // ABXY 用 corner ✅
- (CGPoint)stickHome  { CGRect s = self.corner; ... }   // 摇杆用 corner ✅
- (CGPoint)dropCenter { CGRect s = self.safe; ... }     // 肩键用 safe ❌
```

横屏时左右 `safeAreaInsets` 约 59pt，所以肩键实际距屏幕边缘 `59 + 44` ≈ 87pt。

**修法**（`dm/ios/Sources/DmGamepad.m`）

```objc
K_ZL_X = 30, K_ZL_Y = 36    // 之前 44 / 40
K_L_X  = 30, K_L_Y  = 100   // 之前 44 / 108
K_CLICK_X = 88              // 之前 102（L3/R3 跟着内移）

- (CGPoint)dropCenter:(int)b { CGRect s = self.corner; ... }   // safe → corner
- (CGPoint)clickCenter:(int)b { CGRect s = self.corner; ... }  // safe → corner
```

效果：距屏幕边缘从 87pt 降到约 57pt，和 ABXY / 方向键风格一致。

---

## 为什么 shader 环节这么干净

1090 个 GLSLC 输出**全部**通过三重校验，SPIR-V 和 MSL 各 639/639 零失败。

原因：**这个游戏的结构和 13 Sentinels: Aegis Rim（已在 iPhone 上跑通）高度同构**。

| | Cross Rays | 13 Sentinels |
|---|---|---|
| SDK | 9.4.1 | 11.4.3 |
| 图形 | NVN | NVN |
| 中间件 | CRIWARE | CRIWARE |
| 模块 | `main` `sdk` `subsdk0`(movie) | 同 |
| **shader** | **1090 GLSLC 内嵌 main** | **838 GLSLC 内嵌 main** |
| 资源容器 | `/Data.bin` 15.14 GB | `ROBO_*.CPK` 4.3 GB |

这条"GLSLC 内嵌 main 只读段"的路径在 nxnative 里已经打磨过，所以一次就过。

**教训**：移植前先找同 SDK / 同中间件的已跑通游戏，能省掉大量试错。

---

## 资源结构（供后续参考）

```
RomFS (18.91 GB → 合并 update 后 20.3 GB)
├── /Data.bin          15.14 GB   ← 主资源包（贴图、模型、脚本）
├── /FileTable.bin                ← 哈希索引
├── /FileList.bin                 ← 文件清单
├── /Data.v1xx.bin     ~385 MB    ← 版本补丁（v101…v163）
├── /data/sound       21,179 个 .hca (1.99 GB)
├── /data/movie          114 个 .usm (0.64 GB)
└── /screen_shot_overlay   5 个 .tga
```

游戏启动时打开 133 个文件：`FileTable.bin` + `Data.bin`（主包）、
每个 DLC 的 `AocInfo.lua` / `FileList.bin` / `FileTable.bin` / `Data.bin`、
然后 `rom:/data/movie/event/EVBTL000.usm`（开场视频）和 BGM。

**贴图不在独立文件里**——内嵌在 `Data.bin`，靠 `FileTable.bin` 的哈希索引定位。

---

## 键位映射（Mac 测试）

```c
// dm/host/front_mac.m  key_bit()
case 38: return 0;  case 40: return 1;  case 32: return 2;  case 34: return 3;   // J K U I → A B X Y
case 3: return 4;   case 5: return 5;                                            // F G → 按下左摇杆
case 12: return 6;  case 14: return 7;  case 6: return 8;   case 8: return 9;    // Q E Z C → L R ZL ZR
case 36: return 10; case 48: return 11;                                          // Return Tab → + −
case 123: return 12; case 126: return 13; case 124: return 14; case 125: return 15; // ← ↑ → ↓
// WASD (0,1,2,13) → 左摇杆；Shift + 方向键 → 右摇杆
```

| Switch | 键盘 | | Switch | 键盘 |
|---|---|---|---|---|
| A 确认 | **J** | | L / R | **Q / E** |
| B 取消 | **K** | | ZL / ZR | **Z / C** |
| X | **U** | | + / − | **Return / Tab** |
| Y | **I** | | 方向键 | **← ↑ → ↓** |
| 左摇杆 | **WASD** | | 右摇杆 | **Shift + 方向键** |
| 按下左摇杆 | **F** / **G** | | | |

---

## 关键命令

```bash
cd <project>

# ---- Mac 运行 ----
./play.sh                              # 不限时长，关窗口或 Ctrl-C 结束

# ---- 完整重建 iOS ----
export PATH="$PWD/.tools/uv:$PWD/.tools/dotnet:$PWD/.tools/xcodegen/bin:$PWD/.tools/glslang/bin:$PWD/.tools/bin:$PATH"
export DOTNET_ROOT="$PWD/.tools/dotnet"
.venv/bin/python nxnative/scripts/build_ipa_from_nsp.py Game -k keys/prod.clean.keys \
  --romfs separate --prepare-xcode --team-id XGQZ2R37U9 --work-dir work/build

# 归档（★ 必须先清 derived data，否则可能打进旧代码）
rm -rf work/build/xcode-derived-data
cd work/build/xcode
DM_TEAM_ID=XGQZ2R37U9 DM_COPY_ROMFS=NO xcodebuild \
  -project DmIOS.xcodeproj \
  -scheme "SD GUNDAM G GENERATION CROSS RAYS (010055700CEA8000)" \
  -configuration Release -destination "generic/platform=iOS" \
  -archivePath /tmp/CR.xcarchive archive \
  DEVELOPMENT_TEAM=XGQZ2R37U9 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates

# 安装（无线即可，配对过一次就行）
xcrun devicectl device install app --device 00008140-001E1DE92082201C \
  /tmp/CR.xcarchive/Products/Applications/DmIOS.app

# ---- 游戏数据（19 GB，用 Finder 拖，devicectl 会截断）----
# Finder → iPhone → 文件 → app → Documents → 拖入 RomFS.img
```

---

## 踩过的坑（按痛苦程度排序）

| 坑 | 现象 | 解法 |
|---|---|---|
| **`COMPRESSIBLE`** | 全黑有文字，`fill=0` | 去掉 `tex_init_fill` 里的该条件 |
| **iOS `fit_16_9`** | 改了 viewport 全屏没反应 | 同时改 `game_rect`（view 层） |
| **derived data 缓存** | 改了代码但 app 没变化 | `rm -rf xcode-derived-data` |
| **`devicectl` 大文件** | 19 GB 传完镜像校验失败 `errno=22` | 用 Finder 拖 |
| **`shader_split` 参数** | `IsADirectoryError` | 第一个参数传 `RomFS.img`，不是目录 |
| **`nohup ... &`** | 调试进程莫名消失 | Python `start_new_session=True` |
| **缺配置文件** | `pso_manifest.tsv` / `shader_map.tsv.conflicts.tsv` 找不到 | 建空占位（带表头） |
| **`DM_COPY_GAME_RESOURCES=NO`** | app 里没有 `msl/`，shader 加载失败 | 用 `DM_COPY_ROMFS=NO` |
| **`prod.keys` 坏行** | `Unable to decrypt NCA header` | 剔掉长度异常的行（34 字符的 `master_kek_source_*`） |

---

## 未验证 / 已知限制

- **120 fps 做不到**：`fps_target` 改的是游戏引擎自己的帧率上限（0/30/60）。Cross Rays 是 60 fps 游戏，强设 120 会让游戏跑 2 倍速。
- **教学画面的贴图错位**：用户报告某个教学画面有轻微贴图错位（文字重叠、色块），后续画面正常。未定位根因。
- 长时间运行（> 1 小时）的内存稳定性未测
- 31 个 DLC 的实际内容未逐一验证（挂载正常）
- 存档 / 读档未深度测试
- 视频播放（USM 开场动画）解码正常，但未确认画面输出

---

## 时间线

| 时间 | 事件 |
|---|---|
| 00:26 | 开始，读 XCI 头（1G+1U 合并卡带，secure 22.586 GB，31 DLC） |
| 01:18 | keys 到位，survey 完成（43 秒） |
| 01:25 | shader 拆出 639 个，SPIR-V + MSL 各 639/639 通过 |
| 07:05 | Xcode 27.2 装好，Metal 编译器 `32023.922` 匹配 lock |
| 07:19 | 首个 IPA 构建成功（1.9 GB） |
| 07:33 | **修复 1**（`mem_used`），进入 `nnMain` |
| 07:34 | **修复 2**（`ReadFile` 重载），冲到 60 fps |
| 12:41 | **修复 3**（`COMPRESSIBLE`），贴图恢复 |
| 12:58 | Mac 完整验证通过（用户："一切正常"） |
| 13:20 | iPhone 上验证，贴图完整 |
| 15:15 | **修复 4**（全屏），找到 iOS 层的 `fit_16_9` |
| 16:33 | **修复 5**（肩键贴边） |
| 16:41 | 用户验收："完美" |

**总耗时约 16 小时**（含环境搭建、Xcode 下载、多次打包验证）。
