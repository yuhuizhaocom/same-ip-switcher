# 网络一键切换（绿色版）使用说明

一个无需安装、可整体拷贝的 Windows 工具，用于在有线（工位）与无线（会议室 WiFi）之间切换，并让**两种网络都使用同一个固定的 IP 地址**，方便你电脑上的本地服务（如数据库、中间件、调试代理）无论在哪边都有稳定的地址可访问。

## 一、文件构成

| 文件 | 作用 |
|------|------|
| `网络切换.cmd` | 双击入口，自动以**管理员权限**调用主脚本 |
| `switch-network.ps1` | 主逻辑脚本（自动识别网卡，无需改名字） |
| `network-config.ps1` | **配置文件**，改 IP / 网段 / WiFi 只动这里 |
| `network-switch.log` | 运行日志（每次执行自动追加，UTF-8 编码） |

> 四个文件应放在同一个文件夹内。整个文件夹拷贝到任意电脑的任意盘符/路径均可直接运行（绿色版，不写注册表、不装系统服务）。

## 二、使用场景

单台电脑的**本地服务**需要固定 IP，而你会在两个网络之间来回切换：

- **工位（插网线）** → 有线网卡自动设为固定 IP，并停用无线网卡。
- **会议室（WiFi）** → 无线网卡自动连接指定 WiFi 并把同一 IP 设为自身地址，同时停固有线网卡。

关键点：**同一时间只有一块网卡持有该 IP**，Windows 不会因两块网卡地址冲突而报错。

### 切换逻辑（auto 模式，默认）

运行脚本时会按**优先级**自动判断，有线优先：

1. **检测到网线已连接**（有线网卡 up）→ 切到有线，并把有线网卡设为固定 IP（即使此时 WiFi 正占着该 IP，也会切过去修复）。
2. 没有网线，且 **WiFi 已在固定 IP 上并已连接** → 无需任何操作，直接结束（毫秒级完成）。
3. 没有网线，且 WiFi 不在固定 IP 上 → 切换并连接 WiFi，自动按 `$WifiSsids` 列表顺序连接列表里第一个能连上的 SSID。

> 关键点：**是否插了网线是首要判断依据**。插网线就切有线、拔了没网线才用 WiFi，确保你在工位插线时一定切到有线，不会因 WiFi 仍占着 IP 而留在无线。

### 手动指定方向

只想强制切到某一边（不自动判断）时，可通过传参运行：

```powershell
# 在管理员 PowerShell 中：
powershell -NoProfile -ExecutionPolicy Bypass -File "switch-network.ps1" eth    # 强制有线
powershell -NoProfile -ExecutionPolicy Bypass -File "switch-network.ps1" wifi   # 强制无线
powershell -NoProfile -ExecutionPolicy Bypass -File "switch-network.ps1" auto   # 自动判断
```

## 三、配置说明

所有需要按你的网络环境修改的内容，全部集中在 `network-config.ps1`：

```powershell
$IpActive  = "10.2.5.199"      # 两种网络都要使用的固定 IP（核心）
$Mask      = "255.255.248.0"   # 子网掩码（255.255.248.0 = /21）
$Gw        = "10.2.3.254"      # 默认网关
$WifiSsids = @("ENUO-12-5G", "ENUO-12")  # 待连接的 WiFi SSID，从上到下优先
```

| 参数 | 含义 | 改的时候注意 |
|------|------|--------------|
| `$IpActive` | 固定 IP | 切换到另一环境时改为该网络的静态 IP；需在网关/DHCP 排除范围外，避免和他人冲突 |
| `$Mask` | 子网掩码 | 必须与当前网络一致（用 `ipconfig` 查看本机实际掩码） |
| `$Gw` | 默认网关 | 改成对应网络的路由器/网关地址 |
| `$WifiSsids` | 可连接的 WiFi 清单 | 只保留你环境里真实存在的 SSID；脚本按顺序尝试，优先连 5G |

### 切换 IP 地址后如何确认生效

运行结束后，或执行：

```powershell
ipconfig
```

查看当前活动网卡是否为配置的固定 IP。

## 四、界面输出与日志

- **控制台与日志内容完全一致**，且每条都带完整时间戳 `[yyyy-MM-dd HH:mm:ss]`。
- 每次运行会在 `network-switch.log` 追加一行分隔标记 + 全部步骤 + 最终结果。
- 日志为空或看不出问题时，把最近几行贴给排查者即可。

控制台示例（插网线 → 切有线）：

```
[2026-09-16 15:04:12] ==== Portable Network Switch ====  Target=auto
[2026-09-16 15:04:12] Ethernet: Realtek Gaming GbE Family Controller  [idx 17]  169.254.117.9 (up=True)
[2026-09-16 15:04:12] WiFi:     Intel(R) Wi-Fi 6 AX201 160MHz  [idx 24]  10.2.5.199 (up=True)
[2026-09-16 15:04:12] Cable link found -> Ethernet.
[2026-09-16 15:04:12] -> Switching to Ethernet
[2026-09-16 15:04:15]  set Ethernet = 10.2.5.199 OK
[2026-09-16 15:04:18] Result:  Ethernet=10.2.5.199 (up=True)   WiFi= (up=False)
==============================
Closing automatically in 5s (press any key to close now)...
```

控制台示例（无网线 & WiFi 已就绪 → 秒退）：

```
[2026-09-16 15:04:12] ==== Portable Network Switch ====  Target=auto
[2026-09-16 15:04:12] Ethernet: Realtek Gaming GbE Family Controller  [idx 17]  (up=False)
[2026-09-16 15:04:12] WiFi:     Intel(R) Wi-Fi 6 AX201 160MHz  [idx 24]  10.2.5.199 (up=True)
[2026-09-16 15:04:12] No cable & WiFi already on 10.2.5.199 -> keep WiFi.
[2026-09-16 15:04:12] Already OK - WiFi is up on 10.2.5.199, no change needed (Ethernet up=False).
[2026-09-16 15:04:12] Result:  Ethernet= (up=False)   WiFi=10.2.5.199 (up=True)
==============================
Closing automatically in 5s (press any key to close now)...
```

## 五、常见问题（FAQ）

| 现象 | 原因 / 处理 |
|------|-------------|
| 双击后一闪而过，或提示 "ERROR: run as administrator" | 未以管理员运行。右键 `网络切换.cmd` → **以管理员身份运行**；或确认 UAC 弹窗点了“是” |
| 切到 WiFi 后 IP 不是固定的，而是 `169.254.x.x` | 那是 APIPA 自动私有地址，说明没拿到有效 IP。检查：WiFi SSID 是否在 `$WifiSsids` 里、掩码/网关是否设置正确、是否真的连上了网 |
| 代码里出现 `[netsh ...] 找不到元素` | 指的是在**已禁用/无配置**的网卡上做清理，属正常预期，不影响结果；脚本已按系统代码页解码，不会出现乱码 |
| 两台电脑或设备抢同一个 IP | `$IpActive` 需设为当前网络空闲的地址，否则会冲突掉线 |
| 没有无线网卡 / 没有有线网卡 | 脚本按网卡类型自动识别，缺哪个就打印 `NOT FOUND`，仍会尽力处理存在的那块（若两块都没有则无法切换） |
| 结果在 5 秒后自动关闭，来不及看 | 运行期间**按任意键可立即关闭**；想慢慢看，直接打开 `network-switch.log` |

## 六、技术说明（开发者）

- **网卡识别不依赖名称**：按 `PhysicalMediaType` 匹配（有线 `802.3`，无线 `802.11/Native`），换机器、换语系（以太网/WLAN 还是 Ethernet/Wi-Fi）都认得出。
- **目标判定有线优先**：`auto` 模式先查有线网卡是否 up（是否有网线）——有则切/修有线；无网线才看 WiFi 是否已就绪以快速跳过，否则切到 WiFi。
- **IP 冲突规避顺序**：切目标前先禁用并清掉旧网卡上的固定 IP → 再给目标网卡设置 → 隔离旧网卡（清 IP + 保持禁用）。
- **设置 IP 用 `netsh ... store=persistent`** 并事后校验当前地址，验证成功才显示 `OK`，否则重试 2 次。
- **管理员校验 / try-catch**：非管理员直接拒绝并提示；主流程包住 `try/catch`，异常会记录到日志并显示，不会导致窗口一直挂着不退出。