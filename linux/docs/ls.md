用 ls 自带的 --time-style 就行（macOS 的 BSD ls 不支持这个参数，但你贴的输出看起来像 GNU ls，Linux 上可用）。

显示完整时间戳（秒）：ls -al --time-style=full-iso
显示完整时间戳（纳秒）：ls -al --time-style=long-iso
自定义格式：ls -al --time-style='+%Y-%m-%d %H:%M:%S %z'
如果你在 macOS（BSD ls）上，需要用 stat：

stat -f '%Sm %N' -t '%Y-%m-%d %H:%M:%S %z' *

stat ./*