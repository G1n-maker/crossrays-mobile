# nxnative 的改动

这个移植基于 [nxnative](https://github.com/seedds/nxnative)，对它做了 **7 个文件的修改**（共 46 行新增、11 行删除）。

## 应用方式

```bash
# 1. 取一个干净的 nxnative
git clone https://github.com/seedds/nxnative.git
cd nxnative

# 2. 打上我们的改动
git apply ../patches/nxnative-crossrays.patch

# 3. 放入游戏 profile
cp -R ../profile/010055700CEA8000 dm/games/

# 4. 确认
GAME=010055700CEA8000 make -C dm/host -j12
```

## 七个改动各有用途

| 文件 | 改动 | 修的是什么 |
|---|---|---|
| `dm/gfx/nvn/nvn_mtl.m` | `tex_init_fill` 去掉 `COMPRESSIBLE` 排除条件 | ★ **全黑有文字**：所有纹理不上传 |
| `dm/gfx/nvn/nvn_mtl.m` | `present_viewport` 加 `crop` / `stretch` 模式 | 全屏（填满手机屏幕） |
| `dm/host/hle_fs.c` | 补 `nn::fs::ReadFile` 缺的那个重载 | 卡在 `nnMain` 早期，`sdk+0x62a78` 崩 |
| `dm/ios/Sources/front_ios.m` | `game_rect`：`present_fill` 时用完整 bounds | 全屏的真正原因（view 被锁成 16:9） |
| `dm/ios/Sources/DmGamepad.m` | 肩键用 `corner` 而非 `safe`，边距 44→30 | 触屏肩键离边缘太远 |
| `dm/games/game.py` | 新增 `present_fill` profile 键 | 全屏模式的配置入口 |
| `dm/games/settings.tsv` | 新增 `DM_PRESENT_FILL` 启动器设置 | 让玩家能切换全屏模式 |
| `dm/host/front_mac.m` | 新增 `DM_WINDOW_SIZE` | 调试用：模拟手机比例 |

## 值得回馈上游的两条

前两个是**通用 bug 修复**，不限于这个游戏：

1. **`COMPRESSIBLE` 条件** —— 任何"给所有纹理设此标志 + 用 `SetStorage` 自己写内存"的游戏都会黑屏
2. **`ReadFile` 重载** —— 任何 SDK 9+ 且用这个签名的游戏都会崩

细节见 [../docs/PORTING-WORKFLOW.md](../docs/PORTING-WORKFLOW.md) 的第 9 节。
