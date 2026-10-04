# AppDeck

**中文** | [English](README.md)

AppDeck 是 Omarchy 桌面的应用启动与窗口切换插件。打开面板后，可以搜索并启动应用，也可以在正在运行的应用及其多个窗口之间切换，包括位于不同虚拟桌面的窗口。

- 左侧列出应用，右侧展示所选应用的窗口标题和工作区。
- 支持模糊搜索、键盘操作和鼠标点击。
- 支持中文输入和 Fcitx5，沿用桌面的输入法配置。
- 可以请求关闭所选应用的全部窗口，也可以在确认后强制结束应用。

![AppDeck 应用搜索与启动面板](preview.png)

## 安装

### 环境要求

- Omarchy 4，使用 Hyprland／Wayland、Omarchy Shell 和 Quickshell。
- 支持 `omarchy plugin` 命令的 Omarchy 安装。
- Git，用于下载插件。

无需额外编译或安装后台服务。

### 安装并启用插件

在终端运行，并按提示确认安装：

```bash
omarchy plugin add https://github.com/Turing-Cat/AppDeck.git --enable
```

已安装但尚未启用时，运行：

```bash
omarchy plugin enable appdeck.app
```

### 配置打开快捷键

插件安装不会自动添加快捷键。在 `~/.config/hypr/bindings.lua` 中加入以下配置，将 `Alt + Space` 绑定到 AppDeck。`hl.unbind` 会替换这个组合键已有的绑定；也可以改成其他组合键。

```lua
hl.unbind("ALT + SPACE")
o.bind("ALT + SPACE", "AppDeck", "omarchy-shell shell toggle appdeck.app")
```

重新加载并检查配置：

```bash
hyprctl reload
hyprctl configerrors
```

也可以直接通过终端打开或关闭面板：

```bash
omarchy-shell shell toggle appdeck.app
```

### 禁用或卸载

仅禁用插件、保留文件：

```bash
omarchy plugin disable appdeck.app
```

卸载插件，在终端运行并按提示确认：

```bash
omarchy plugin remove appdeck.app
```

如果配置了上文的快捷键，请从 `~/.config/hypr/bindings.lua` 中移除对应两行，再运行 `hyprctl reload`。如需恢复原来的绑定，在该文件中重新配置。插件不会自动修改快捷键。

## 使用

1. 按 `Alt + Space` 打开面板。
2. 输入应用名称，用 `↑`／`↓` 选择应用。
3. 按 `Enter`：尚未运行的应用会收到启动请求；正在运行的应用会切换到最近使用的窗口。
4. 需要指定窗口时，按 `Tab` 进入右侧窗口选择，再用 `Tab`／`Shift + Tab` 循环选择，按 `Enter` 切换。也可以直接点击目标窗口。

上下键始终选择应用。首次按 Tab 会选中最近使用的窗口；后续按键才移到其他窗口。编辑搜索或切换应用会退出窗口选择。目标窗口位于其他虚拟桌面时，会切到该窗口所在的桌面并聚焦它。

应用列表随窗口打开、关闭和移动实时更新。窗口选择保留在同一个窗口上；目标消失时会提示重新选择。

中文输入需要桌面输入法已正确配置。输入法正在组合文字时，候选操作交由输入法处理，不触发应用启动或窗口切换。

## 快捷键

| 快捷键或操作 | 功能 |
| --- | --- |
| `Alt + Space` | 打开／关闭面板，需按上文配置 |
| 输入文字 | 按应用名称模糊搜索 |
| `↑` / `↓` | 选择上一个／下一个应用 |
| `Page Up` / `Page Down` | 按页选择应用 |
| `Home` / `End` | 选择第一个／最后一个应用 |
| `Tab` | 进入窗口选择；随后选择下一个窗口，循环到首项 |
| `Shift + Tab` | 进入窗口选择；随后选择上一个窗口，循环到末项 |
| `Enter` / Focus 按钮 | 切换到指定窗口；未选择窗口时切到最近窗口，未运行的应用则启动 |
| 点击应用行 | 切换到该应用的最近窗口，或启动该应用 |
| 点击窗口行 | 切换到该窗口 |
| `Ctrl + U` | 清空搜索 |
| `Delete` | 请求关闭所选应用的全部窗口 |
| `Shift + Delete` | 打开所选应用的 Kill 确认框 |
| `Escape` | 搜索非空时清空搜索；搜索为空时关闭面板 |

窗口选择状态下，`Delete` 和 `Shift + Delete` 不执行关闭操作。Close 和 Kill 按钮始终作用于所选应用的全部窗口。

Close 会请求应用正常关闭，应用可能继续显示保存提示。Kill 需要确认，可能丢失未保存的内容；确认框默认选中 Kill，可用 `←`／`→` 或 Tab 切换选项，按 `Enter` 执行当前选项，按 `Escape` 取消。

## 许可证

[MIT](LICENSE)
