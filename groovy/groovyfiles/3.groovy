
要启动一个Docker镜像但禁止其输出到stdout和stderr,可以使用以下选项:

- --detach或`-d`: 以detached模式运行容器,不挂起控制台。这可以避免容器的stdout输出显示在控制台。

- --log-driver none: 使用空的日志驱动,这将禁止任何日志输出。

所以docker run命令会是:
bash
docker run -d --log-driver none your-image


这将启动容器在后台运行,并禁止任何日志输出。

你也可以结合使用`--detach-keys`来使容器在按指定按键时进入前台:

bash 
docker run -d --log-driver none --detach-keys "ctrl-p,ctrl-q" your-image


这将允许你使用`ctrl+p`和`ctrl+q`两个按键将容器带到前台,从而查看其输出和控制台。

除了使用`--log-driver none`,你也可以重定向stdout和stderr到`/dev/null`:

bash 
docker run -d your-image > /dev/null 2>&1


这将启动容器,但重定向stdout到`/dev/null`,并将stderr重定向到与stdout相同的位置。

以上任意一种方法都可以启动一个Docker容器并禁止其标准输出和错误输出。请让我知道如果你有任何其他问题!


在启动Docker容器的时候，可以使用“-d”参数来使该容器在后台运行，并抑制 stdout 和 stderr 的输出。具体操作如下：

```
docker run -d {image} >/dev/null 2>&1
```

其中“-d”表示以后台模式运行容器，“>/dev/null 2>&1”则将容器的标准输出和标准错误输出重定向到 /dev/null 中，从而禁止了输出。

或者，也可以在使用“docker run”启动容器时，使用“-log-driver none”参数来禁止Docker将日志发送到标准输出。具体示例如下：

```
docker run -d --log-driver none {image}
```

这样，即使没有重定向日志输出到 /dev/null，Docker也不会将容器的输出写入标准输出中。

需要注意的是，禁止容器输出 stdout 和 stderr 并不利于对容器运行状态的监控和排查问题，建议在实际应用场景中慎重考虑。



