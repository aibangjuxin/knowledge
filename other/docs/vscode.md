在 VS Code 中,可以通过快捷键快速插入当前时间。操作步骤如下:

1. 打开 VS Code 的键盘快捷键设置页面。你可以通过以下任意一种方式打开:

- 在 VS Code 中按 F1,输入 keyboard shortcuts 并选择 Keyboard Shortcuts
- 点击底部状态栏中的键盘图标按钮
- 打开 Command Palette (View -> Command Palette),输入 keyboard shortcuts

2. 在键盘快捷键页面搜索 "insert date",找到 editor.action.insertDateString 命令。

![search insert date](https://i.loli.net/2020/10/01/o1J3Cr8Xi2KV59T.png)

3. 点击命令右侧的更改键绑定按钮,为该命令绑定你希望的快捷键,例如 Ctrl+Alt+D。

![change keybinding](https://i.loli.net/2020/10/01/wEPm7lVJu4aCrSB.png)

4. 按 Esc 键退出键盘绑定设置,保存设置。

5. 现在,在 VS Code 的编辑器中,按 Ctrl+Alt+D 就可以快速插入当前日期和时间了。默认格式为 2020-10-01 15:26:42。

如果你需要自定义日期格式,可以修改 editor.insertDateFormat 和 editor.insertTimeFormat 的设置。例如:

- 改为日期格式为 YYYY-MM-DD,设置 "editor.insertDateFormat": "YYYY-MM-DD"
- 改为时间格式为 HH:mm,设置 "editor.insertTimeFormat": "HH:mm"

 then按快捷键就会插入 2020-10-01 17:35 这种格式了。

希望这个提示能够帮助你在 VS Code 中快速高效的插入日期和时间。如有任何其他问题,请随时提问。