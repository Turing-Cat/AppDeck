# AppDeck 实时列表与操作失效修复方案

日期：2026-09-04

状态：已修复并完成现场验证

## 问题结论

| 用户现象 | 已确认根因 |
| --- | --- |
| 不要显示“子进程” | 多出来的并非进程树子进程，而是长驻 Quickshell 窗口模型中的历史窗口；其 Wayland handle 已为空，AppDeck 却仍将它们显示为独立的 Unidentified App |
| 应用无法切换 | 当前使用的 `Toplevel.activate()` 被 Hyprland 0.56.2 忽略；同时 AppDeck 的 Exclusive overlay 未先释放焦点，即使改用有效的 Hyprland 地址调度也无法切换 |
| 无法 Close | `gracefulCloseTargets` 仅是 Node `module.exports` 中的别名，QML 命名空间中不存在该函数，调用时直接抛出 `TypeError`；历史条目也会形成无 handle 的无效目标 |
| 无法 Force Kill | Quickshell 实际地址不带 `0x`，代码却只接受带 `0x` 的地址，因此所有真实窗口在生成请求前就被过滤掉 |

## 诊断证据

### 1. 列表包含非当前窗口

同一桌面会话中：

- `hyprctl clients -j | jq 'length'` 返回 13 个真实客户端窗口。
- AppDeck 在临时测试窗口均已关闭后仍显示 23 个 Running App、28 个 App Window。
- 列表底部存在已关闭的 WPS、WeChat 条目；它们没有 workspace，详情中显示为 `Unidentified App`。
- 新启动的只读 Quickshell 探针同时读取到 13 个 `Hyprland.toplevels` 和 13 个 `ToplevelManager.toplevels`，且全部具有有效 Wayland handle。

对应代码链路：

1. `AppDeck.qml:snapshots()` 无条件遍历 `Hyprland.toplevels.values`。
2. 当 `hyprlandToplevel.wayland === null` 时，仍生成 `handle: null`、`appId: ""` 的 snapshot。
3. `AppDeckModel.runningApps()` 将空身份按设计转换为独立的 Unidentified App。
4. 结果是已关闭的历史窗口重新变成可见行，但 Focus/Close 已没有可调用对象。

长驻窗口模型保留历史对象属于外部运行时条件；AppDeck 自身的缺陷是没有在共享输入边界上落实“可操作的 App Window”约束。

### 2. Focus 的 API 与 overlay 时序均不成立

使用一次性 Foot 窗口完成了三组对照：

- 没有可见 overlay 时，`Toplevel.activate()` 仍未激活目标，结果为 `activated: false`。
- 没有 Exclusive overlay 时，Hyprland 0.56 的 Lua 地址 dispatcher 成功激活同一目标，结果为 `activated: true`。
- 保持 Exclusive overlay 时，同一地址 dispatcher 仍无法激活目标。
- 在真实 AppDeck 中按 Enter 后，活动窗口保持为 ChatGPT，界面显示 `Unable to focus this app.`。

因此必须把“释放 overlay 焦点”和“改用 Hyprland 精确地址调度”作为同一次状态迁移；只改其中一项仍会失败。

官方行为依据：

- [Quickshell Toplevel](https://quickshell.org/docs/types/Quickshell.Wayland/Toplevel/) 明确说明 compositor 可以忽略 `activate()`。
- [Quickshell HyprlandToplevel](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandToplevel/) 提供精确 Hyprland 地址。
- [Hyprland dispatcher](https://wiki.hypr.land/Configuring/Basics/Dispatchers/) 定义了 0.56 的 Lua dispatcher 与 `address:0x...` selector。

### 3. Close API 有效，但 QML 调用了不存在的别名

在 Exclusive layer-shell overlay 保持活动时，对一次性 Foot 窗口直接调用 `Toplevel.close()`，对应客户端计数由 1 变为 0。

所以不应替换 Graceful Close API。现场日志进一步确认每次操作都会抛出：

```text
TypeError: Property 'gracefulCloseTargets' of object [object Object] is not a function
```

原因是原代码只在 Node 的 `module.exports` 中写了
`gracefulCloseTargets: appWindows`；QML 的 JavaScript 命名空间导入只暴露顶层函数声明，不读取 CommonJS 导出别名。修复时将该函数改为真正的顶层
`gracefulCloseTargets()`，内部调用和 Node 导出均复用同一个声明；同时继续在上游排除无 live handle 的历史窗口。

### 4. Force Kill 的测试数据与运行时格式不一致

Quickshell 的 `HyprlandToplevel.address` 实际值类似 `55e1...`，不带 `0x`。当前 `forceKillScope()` 只接受 `/^0x[0-9a-f]+$/`，所以真实窗口全部被拒绝。

现有 16 个模型测试全部通过，是因为测试手工构造了 `0xa1` 一类非运行时格式。以下运行时形状的检查已执行并稳定失败，结果为 `0 !== 1`：

```sh
node - <<'NODE'
const assert = require('node:assert/strict');
const { forceKillTargets } = require('./AppDeckModel.js');
const app = {
  identity: 'app:real',
  windows: [{ ownerIdentity: 42, hyprlandAddress: '55e1c24dd5b0' }]
};
assert.equal(forceKillTargets(app, true, [app]).length, 1);
NODE
```

## 最小修复设计

### A. 在共享边界过滤无效 App Window

列表中的 snapshot 必须同时满足：

- 具有非空 Wayland toplevel handle；
- Hyprland 地址可被规范化为有效地址；
- 同一规范化地址此前未出现。

等待 Wayland 关联的新窗口应暂时不显示，并监听 `waylandHandleChanged` 后重建；不得通过轮询等待。

必须保留“handle 有效但 `appId` 为空”的真实 Unidentified App。这与 ADR 0001 一致。不要增加进程祖先分析、`/proc` 扫描、PID 树规则或后台 daemon；那些都与问题无关，也违反 ADR 0004 的边界。

过滤应放在模型/快照的共享入口，而不是分别给渲染、Focus、Close、Force Kill 添加补丁。

### B. 统一 Hyprland 地址格式

增加一个小型纯函数：

1. 去除首尾空白；
2. 接受带或不带 `0x` 的十六进制地址；
3. 统一输出小写 `0x...`；
4. 拒绝其他格式。

snapshot、去重、确认范围、Focus 和 Force Kill 都使用同一规范化结果，禁止各自拼接 selector。

### C. 将 Focus 改为两阶段操作

1. 冻结 Selected App 的 identity、Wayland handle 和规范化 Hyprland 地址。
2. 先设置 `opened = false`，使 PanelWindow 隐藏并立即将 `WlrLayershell.keyboardFocus` 变为 `None`。
3. 在下一次 Qt event-loop 中通过 `Hyprland.dispatch()` 发送精确 `address:0x...` 的 Hyprland 0.56 Lua focus action。该调用仍在 shell 内部完成，不启动辅助进程。
4. 保留激活确认；只有现场测试证明 250ms 不够时才延长 timeout。
5. 确认成功后调用 shell hide 路径，同步宿主的 `openPanelIds`。
6. timeout 或异常时重新打开 AppDeck，保留原选择，恢复键盘焦点并显示 inline error。

不能只设置 `opened = false`：否则宿主仍认为插件处于打开状态，下次快捷键会执行错误方向的 toggle。

### D. 保留原生 Graceful Close

继续对 Selected App 启动操作时冻结的 live App Window 数组逐个调用 `Toplevel.close()`。不需要释放 overlay 焦点，也不需要 shell 命令。继续区分“请求已发送”和“应用已关闭”，保留部分失败反馈。

### E. Force Kill 复用规范化确认范围

确认页快照和最终请求均使用规范化地址。发送前继续复核：

- Running App identity 未改变；
- App Window 数量未改变；
- owner/address 范围完全一致；
- owner 未被其他 Running App 共享。

保留显式确认、不提权、不按进程名匹配、不推断 PID 树等 ADR 0002 安全要求。

## 实施前先补的回归测试

在现有无依赖 Node 测试中增加最小失败用例：

1. `handle: null` 的 snapshot 被排除；有 handle 且空 `appId` 的真实 Unidentified App 仍被保留。
2. 相同规范化地址的重复 snapshot 只产生一个 App Window。
3. 带/不带 `0x` 的地址得到相同规范化值，非法 selector 被拒绝。
4. 真实形状的不带前缀地址能生成一个 Focus selector 和一个 Force Kill target。
5. Focus 状态迁移满足“先隐藏/释放、再 dispatch”；成功时同步宿主状态，失败时恢复 overlay 和选择。

## 现场验证矩阵

使用一次性窗口执行，不影响真实应用：

| 场景 | 预期结果 |
| --- | --- |
| 对比 `hyprctl clients` 与 AppDeck | App Window 数相同，不再显示旧 WPS/WeChat 条目 |
| live 空 `appId` 窗口 | 仍显示为一个独立 Unidentified App |
| Enter / Focus 按钮 | overlay 先释放，精确目标激活，宿主打开状态同步关闭 |
| 人为制造 Focus 失败 | AppDeck 重新出现，选择不变并显示 inline error |
| Close 单个一次性窗口 | 仅向该窗口发送 Close Request |
| Close 同一 Running App 的两个窗口 | 两个窗口均收到请求，不影响其他应用 |
| 取消 Force Kill | 不执行任何破坏操作 |
| 确认 Force Kill | 仅结束已确认的一次性 owner |
| 确认期间目标发生变化 | 拒绝请求并要求重新确认 |

随后执行完整仓库检查：

```sh
node --test
omarchy plugin validate .
qmlformat AppDeck.qml
qmllint -I /usr/share/omarchy/shell -I /usr/lib/qt6/qml AppDeck.qml
git diff --check
```

## 预计改动范围

- `AppDeckModel.js`：地址规范化与共享的有效窗口规则。
- `AppDeck.qml`：snapshot 过滤/信号监听、两阶段 Focus 调度。
- `tests/model.test.js`：贴近真实运行时格式的回归测试。
- 只有行为文字发生变化时才更新 README/现有 issue 记录。

不增加依赖、daemon、辅助可执行文件、进程扫描器或设置页面。

## 验收标准

- 不显示缺少 live handle/address 的历史窗口。
- 已关闭窗口不会继续留在列表。
- 真实 Unidentified App 仍独立显示。
- Focus 切换到精确 Selected App，且宿主 toggle 状态正确。
- Graceful Close 向 Selected App 的每个且仅这些 App Window 发送请求，不声称应用一定接受请求。
- Force Kill 能接受 Quickshell 的真实地址格式，保留确认，并且只结束已确认的唯一 owner。
- 所有失败路径保持 AppDeck 可用并显示 inline error。
- 实现继续符合 ADR 0001 至 0004。

## 实施与验证结果

- 重启 shell 后，AppDeck 从错误的 23 个应用/28 个窗口恢复为 8 个应用/13 个窗口，与 `hyprctl clients` 的 13 个真实客户端一致。
- Focus：对一次性 `appdeck-focus-test` 窗口按 Enter 后，活动窗口地址精确切换到该目标，overlay 与宿主打开状态同步关闭。
- Close：通过插件方法调用和可见面板中的 Delete 两条路径，均只关闭选中的一个一次性 Foot 窗口；footer 显示 `Close Request sent to 1 window.`。
- Force Kill：确认页显示唯一一次性应用及 1 个窗口，确认后仅该窗口消失。
- 所有一次性测试窗口均已清理，真实客户端计数回到 13。
- `node --test`、`qmllint`、`omarchy plugin validate .`、`git diff --check` 全部通过；最新 shell 日志无新的 AppDeck 运行时异常。
