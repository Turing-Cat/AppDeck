# AppDeck 架构重构

Status: resolved

## 范围

用户已确认架构评估报告，要求重构并保持原有功能。集中处理桌面数据转换与聚焦确认、应用与窗口选择状态，以及确认后的 Kill 请求生命周期。

保持 Omarchy 插件入口、原生 TextInput 与 Fcitx5 行为、全部快捷键、应用级 Close / Kill 范围，以及 ADR 0001–0005。无新增产品功能或运行依赖。

## 实现

| 文件 | 职责 |
| --- | --- |
| `AppDeck.qml` | 插件入口、操作协调、启动与 Graceful Close |
| `AppDeckView.qml` | 布局、原生输入框、窗口列表、确认界面与滚动 |
| `AppDeckSelection.qml` | Activity Order、搜索、Selected App 与显式 App Window 选择 |
| `AppDeckDesktop.qml` | Hyprland 数据转换、事件订阅与动作发送 adapter |
| `AppDeckFocus.qml` | 延迟聚焦、目标重验、确认、超时与取消 |
| `AppDeckKill.qml` | 确认范围、目标重验、独占 owner 检查与批量响应汇总 |
| `AppDeckKillRequest.qml` | 单条 socket 请求、分片响应、断连与超时 |

保留 `AppDeckModel.js` 的纯策略函数。测试通过替身桌面 adapter 提供观察和响应，不再屏蔽 Hyprland 信号或直接改写派生应用列表。取消或替换聚焦请求后，旧回调不能发送新请求。

## 验证

重构前：26 项模型测试与 26 项 Qt 交互测试通过。

重构后：

- `node --test tests/model.test.js`：26 项通过。
- `bash tests/run-input-tests.sh`：原有 26 项与新增 11 项通过。覆盖真实 Qt 输入法事件、键盘、鼠标、窗口选择、聚焦生命周期、Kill 目标变化、共享 owner、重复与乱序响应。
- `python tests/native-desktop.test.py`：2 次真实跨桌面窗口聚焦通过；真实 socket 的分片成功响应、错误响应、超时通过。socket 连接本地测试 responder，不发送实际 Kill。
- Omarchy shell 加载与界面检查通过；测试窗口与临时进程已清理，恢复验证前的窗口焦点。
- QML 测试运行器会将运行时类型、引用和绑定错误视为失败。
- `git diff --check` 通过。

实机仅有单显示器，多显示器场景未验证。本次范围不包括提交或推送。
