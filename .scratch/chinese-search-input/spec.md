# 修复搜索框无法输入中文

Type: task
Status: resolved

## 目标

让 AppDeck 的 Search Query 支持中文输入法组词、候选确认和连续输入，同时保留现有搜索排序、应用选择和安全确认行为。本文记录修复方案与实施结果；代码已修复并推送，桌面已切换到 AppDeck。

## 已确认的原因

搜索区域使用 `Text` 显示 `root.searchQuery`，实际接收焦点的是普通 `Item`（`keyCatcher`）。`Keys.onPressed` 手动追加 `event.text`，没有处理输入法的预编辑和提交事件。字符分支还要求 `event.text.length === 1`，无法作为多字符文本输入的通用实现。

在本机 Qt 最小复现中，提取当前键盘处理逻辑并直接发送事件，得到以下结果：

| 输入事件 | 当前实现 | 原生 `TextInput` 对照 |
| --- | --- | --- |
| 英文按键 `a` | Search Query 变为 `a` | 未测 |
| 输入法提交「中文」 | Search Query 仍为空 | 文本变为「中文」 |

当前接收焦点的 `Item` 未设置 `ItemAcceptsInputMethod`。这证明文本输入路径存在缺陷；该复现绕过了 Fcitx 和 Wayland，尚未验证实际桌面中的候选窗口、协议和焦点交互，也不能据此排除额外的环境问题。

参考：[Qt 输入法事件](https://doc.qt.io/qt-6/qinputmethodevent.html)、[TextInput 的组词状态](https://doc.qt.io/qt-6/qml-qtquick-textinput.html#inputMethodComposing-prop)。

## 修改方案

### 1. 使用原生文本输入控件

在 `AppDeck.qml` 中把显示查询的 `Text` 替换为 `TextInput`，沿用现有字体、颜色和布局。空输入提示使用独立的 `Text`，仅在已提交文本和预编辑文本均为空时显示。

通过 `TextInput` 接收普通文字、输入法预编辑和提交、粘贴及文本编辑。删除手动拼接 `event.text` 的分支；不要通过放宽单字符判断来修复。

`onTextEdited` 调用现有 `root.setSearchQuery(text)`，只把已提交文本传入搜索模型。预编辑文本由控件显示，不作为 Search Query 参与搜索。输入提交后的排序和 Selected App 更新继续复用现有实现，不修改 `AppDeckModel.js`。

查询重置统一同步控件文本和 `root.searchQuery`。打开面板、清空查询等程序修改必须走明确的同步入口，不依赖用户编辑信号，也不在每次输入时反写控件文本，以免打断组词或移动光标。

### 2. 调整焦点和生命周期

打开面板及 `restoreListFocus()` 时，将焦点交给搜索控件。搜索控件需要位于键盘处理容器的子树中，或直接承载面板快捷键，保证输入焦点下仍可执行应用导航。

关闭面板时取消未提交的组词；重新打开时清空已提交文本和预编辑状态。Kill 确认期间使用确认框的键盘处理路径；取消或操作完成后恢复搜索焦点，保留已提交的查询。

检查 `open()`、`restoreListFocus()`、`reportFocusError()` 和 Kill 确认的全部调用路径，避免只修改首次打开时的焦点。

### 3. 区分组词与面板快捷键

当搜索控件的 `inputMethodComposing` 为 `true` 且 `preeditText` 非空时，面板处理器不消费普通输入、Enter、Escape、方向键、翻页键、Home、End 和 Delete，将事件留给输入法或文本控件。确认候选的 Enter 不得触发 Focus 或 Start Running，组词期间的 Delete 不得触发 Graceful Close 或 Kill。

实际 Fcitx5 检查发现：取消或清空组词后，Qt 可能因输入法残留的光标属性继续报告 `inputMethodComposing === true`，即使预编辑文字已经为空。因此应用侧保护同时检查待提交文字，避免取消组词后一直屏蔽快捷键。Qt 平台输入法仍先于应用处理实际键盘事件，不改动输入法本身。

未组词时保留现有面板约定：Enter 激活 Selected App；上下键及翻页键移动选择；Home / End 跳到首尾结果；Escape 先清空查询，再关闭面板；Delete 发起 Graceful Close；Shift + Delete 打开 Kill 确认。

普通 Backspace、Ctrl + Backspace、选区编辑和粘贴交给 `TextInput`。Ctrl + U 保留清空查询行为。删除 AppDeck 对 `Util.editsFilter()` / `Util.editedFilter()` 的调用，不修改宿主的共享工具。

保留 Delete 的应用操作语义意味着它在未组词时不用于删除光标后的文字。本次修复不调整这一既有交互约定。

## 实施顺序

1. 先落地下面的 Qt 回归测试和运行入口，在未修复版本上运行，记录中文提交用例的失败输出。`/tmp` 中的诊断程序不算仓库测试。
2. 替换输入控件，接通已提交文本与 Search Query 的同步。
3. 调整焦点恢复、组词事件分流和关闭时的输入法清理。
4. 运行自动检查，再在当前 Omarchy / Fcitx 桌面完成手工验收。

## 验收

### 自动检查

修复前的 `tests/model.test.js` 主要覆盖分组、搜索、选择和动作目标计算，另有一个 QML 可见函数的源码声明检查。它没有加载搜索输入控件，也没有发送输入法事件或检查窗口焦点。因此原有 26 项测试通过，不能证明中文输入可用。下面的回归测试已按本次方案落地。

#### 运行入口与测试边界

新增 `tests/input.test.cpp`、`tests/input.test.qml` 和 `tests/run-input-tests.sh`，使用已有 Qt 6 和 C++ 工具链。C++ 文件提供 Qt 事件驱动，QML 文件加载完整插件并执行行为断言。脚本将产物写入临时目录，运行结束后清理；断言失败返回非零退出码。缺少依赖或 QML 加载失败报告错误，不当作测试通过。

测试必须加载项目实际 QML 输入和事件处理路径。通过窗口的真实焦点对象分发 `QInputMethodEvent` / `QKeyEvent`，处理事件循环后断言控件文本、`root.searchQuery`、Selected App 及动作调用次数。允许替换桌面数据和外部动作接口；不允许在测试中重写输入、同步、组词判断或快捷键处理逻辑。测试中使用固定的中文应用名称，避免依赖本机安装的软件。

先验证现有 `AppDeck.qml` 能否在测试宿主中加载。若无法加载，先解决宿主初始化；确有必要时才把实际搜索输入及其键盘处理提取为一个由 AppDeck 和测试共同加载的小组件。不要用原生 `TextInput` 对照测试代替 AppDeck 回归测试，也不要用源码字符串匹配证明输入正确。

使用以下命令运行检查：

```bash
bash tests/run-input-tests.sh
node tests/model.test.js
omarchy plugin validate .
```

#### 回归用例

| 用例 | 输入或操作 | 必须断言的结果 |
| --- | --- | --- |
| 中文提交（首个失败用例） | 打开面板，通过窗口发送提交字符串「中文」 | 实际输入控件文本与 Search Query 均为「中文」；候选按中文查询更新 |
| 组词与连续提交 | 发送预编辑 `zhongwen`，再提交「中文」，再提交「输入」 | 预编辑可在控件中读取，Search Query 在提交前不变；最终文本与查询均为「中文输入」 |
| 中英文与粘贴 | 输入 `a`、提交「中文」、粘贴 `b测试` | 控件文本与 Search Query 均为 `a中文b测试`，无丢字或重复追加 |
| 编辑与清空 | 在中文查询中 Backspace、选区替换、Ctrl + U，再输入 | 控件文本与 Search Query 每步一致；清空后可继续输入；光标和选区操作不因反写文本被重置 |
| 组词期间的动作保护 | 建立非空预编辑，分别发送 Enter、Delete、Shift + Delete | 激活、Graceful Close、Kill 请求次数均为 0，Kill 确认未打开，面板仍可输入 |
| 组词期间的导航保护 | 建立非空预编辑，分别发送 Escape、上下键、翻页键、Home、End | AppDeck 不因这些按键关闭面板、清空已提交查询或改变 Selected App；允许输入法处理预编辑 |
| 非组词快捷键 | 结束组词，分别发送 Enter、导航键、Delete、Shift + Delete | 原有导航和应用动作执行；Shift + Delete 只打开确认，未确认时 Kill 请求次数仍为 0 |
| 取消组词后的空光标状态 | 发送预编辑为空、带 Cursor 属性的输入法事件，再按 Delete / Shift + Delete | 即使 Qt 的组词标志仍为真，原有 Close / Kill 确认快捷键仍正常；未确认时 Kill 请求次数为 0 |
| 焦点与生命周期 | 打开、关闭再打开；取消 Kill 确认；模拟激活失败并恢复面板 | 打开或恢复后窗口焦点对象为实际输入控件；重新打开查询与预编辑均为空；取消确认及错误恢复保留已提交查询且可继续输入 |

每个动作和导航用例单独重置状态，避免前一按键结束组词后影响下一项判断。输入法候选确认的真实事件顺序仍需桌面验收；直接注入事件只能验证控件和应用分发逻辑。

修复前至少运行首个中文提交用例并确认失败；修复后所有用例通过，同时现有 26 项模型检查、插件验证及 QML 解析 / `qmllint` 检查通过。若自动测试覆盖不到某项，明确列出缺口和手工结果，不把未运行项目写为通过。

### 实际桌面验收

- 打开面板后直接切换中文输入法，输入拼音，候选可见并能确认；已提交中文进入查询。
- 用 Enter 确认候选时面板保持打开，应用不被激活；结束组词后再次按 Enter 才激活 Selected App。
- 连续输入中文词组、中文与英文混合文字，粘贴多字中文，查询内容正确。
- 在组词期间使用 Escape、方向键、Backspace 和 Delete，不误触发面板导航或应用动作。
- 未组词时检查 Enter、Escape、导航键、Ctrl + U、Delete 和 Shift + Delete，行为符合原有约定；Kill 仍必须显式确认。
- 关闭再打开面板，不残留预编辑内容；Kill 确认取消后输入焦点和已提交查询正常恢复。
- 若事件检查通过而桌面仍失败，再检查 Omarchy Shell 进程的输入法模块、Fcitx 与 Wayland 连接及 layer-shell 焦点。不得仅凭当前最小复现就修改全局输入法配置。

## 范围

预计修改 `AppDeck.qml`，新增一个 Qt 回归测试和运行脚本；只有测试宿主确实无法加载实际输入路径时才提取必要组件。无需修改搜索算法、引入输入法库、改动系统配置或重写宿主共享组件。候选窗口的实际显示及 Enter 确认时的事件顺序，以桌面验收结果为准。

## 实施结果

2026-10-03：在 `AppDeck.qml` 中替换原生 `TextInput`，移除手动字符追加，复用现有搜索模型；输入与查询按需同步，组词期间跳过面板快捷键，打开、确认取消和动作失败后恢复输入焦点，关闭时重置输入法。

- 同一份完整插件回归测试在修复前失败：提交「中文」后查询为空；修复后通过。无需提取产品组件，也未复制输入逻辑。
- 14 步输入回归检查覆盖中文查询、连续提交、粘贴、编辑、组词期间的动作保护、导航、Kill 取消、启动失败和 Focus 失败恢复、关闭及重新打开。
- 自动事件检查运行在当前 Wayland 会话，测试窗口不抓取桌面键盘。Close 与 Launch 使用测试接口；Focus 失败检查使用不存在的精确窗口地址；测试不确认 Kill。
- 原有 26 项模型测试、插件验证和 Qt 6 QML 解析通过。`qmllint` 在宿主动态类型、未限定访问及既有布局警告降为提示后通过；不声称静态检查无提示。
- 真实 Fcitx5 拼音检查确认候选框可见，Space 选词得到「中文」，连续选词得到「中文输入」。组词期间 Enter 按默认行为提交原始拼音，面板保持打开，启动次数为 0。因此验收以「组词按键不误触发应用动作」为准，不强制 Enter 改变输入法自身的确认习惯。
- 真实 Fcitx5 的候选导航、Escape 和 Delete 未触发应用动作；退出组词、打开并取消 Kill 确认后，可继续提交「中文输入」，没有 Kill 请求。该检查使用虚构 Running App 和 Close 接口，不操作真实应用。
- 另一个失败用例复现了空预编辑带 Cursor 属性时 Close 快捷键被持续屏蔽的问题；结合 `preeditText` 调整保护条件后通过，真实 Fcitx5 路径也通过。
- 代码修复完成时仍保留旧 ProcDeck 安装；随后按用户要求推送修复，并移除旧安装，详见部署记录。

## 部署记录

2026-10-03：修复已推送到 GitHub `main`。移除 `procdeck.app` 的插件链接和配置入口，将旧 `/home/zjh/Projects/ProcDeck` 源目录移入回收站。启用链接到当前仓库的 `appdeck.app`，将 `ALT + SPACE` 从 ProcDeck 切换到 AppDeck。配置修改前已备份。

Hyprland 配置检查无错误。运行中的 Omarchy Shell 已发现并启用 AppDeck，实际打开及关闭覆盖层均通过；旧 ProcDeck 不再出现在插件列表中。
