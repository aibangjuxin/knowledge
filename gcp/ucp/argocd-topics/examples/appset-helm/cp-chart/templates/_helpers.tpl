{{/*
把一段文本「原样」留给 ApplicationSet controller。

两层模板引擎（Helm + ApplicationSet）作用在同一段文本上时，
Helm 必须对下游的 {{ }} 视而不见。Helm 的字符串字面量写法就是：

    {{`{{ .path.basename }}`}}

渲染结果是 {{ .path.basename }}，一个字都没变。

这个 helper 把这段写法封装起来，参数是「点号后面的名字」：

    {{ include "platform-cp.appsetVar" "app.path.basename" }}
    → {{ .app.path.basename }}

注意：helper 只能整体转义一段**变量引用**。
如果要转义的是「一段带函数调用的表达式」，直接写字面量更清楚：

    '{{`{{ .cluster | normalize }}`}}'
*/}}

{{- define "platform-cp.appsetVar" -}}
{{`{{ .`}}{{ . }}{{` }}`}}
{{- end -}}
