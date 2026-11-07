"""
yamlmin —— 极简 YAML 子集解析器（零三方依赖）。

**为什么需要它**
  Argo CD 的清单里有几类东西没法用"按行 grep"的方式校验：
    · 多文档 YAML（--- 分隔）
    · 嵌套结构（ConfigMap.data 里的整段 YAML、AppProject 的列表项）
    · 块标量（| / >）
    · flow 集合（{} / []）
  而 `pip install pyyaml` 在很多环境里又不一定做得到（尤其是受限的 CI 镜像）。
  所以这里手写一个**够用**的子集解析器。

**支持什么**
  · 块映射、块序列（序列项可以与 key 同缩进，也可以多缩进两格）
  · 序列项内联映射（`- key: value` 及其后续同缩进兄弟键）
  · 块标量 `|` `|-` `|+` `>` `>-` `>+`
  · flow 集合 `{a: 1}` / `[1, 2]`（单行）
  · 引号标量（单双引号）、裸标量、bool / int / float / null
  · 注释剥离（` #` 才算注释，`a#b` 不算）
  · 多文档（`---` 分隔）

**不支持什么（故意的）**
  · 锚点 / 别名（& / *）、复杂键（? :）、标签（!!str）、多行 flow 集合
  · 合并键 `<<`
  → 这些在 K8s / Argo CD 清单里几乎不出现；真出现了会抛 YamlError。

**用法**
    from yamlmin import load_all, load_file
    docs = load_all(text)
"""

import re

__all__ = [
    "YamlError",
    "load",
    "load_all",
    "load_file",
    "load_all_files",
    "flatten",
    "select_equal",
]


class YamlError(Exception):
    """解析失败。消息里带行号，方便定位。"""


# ---------------------------------------------------------------------------
# 词法辅助
# ---------------------------------------------------------------------------

def _strip_comment(text):
    """去掉行尾注释。只把「前面有空白」或行首的 # 当注释。"""
    out = []
    quote = None
    i = 0
    while i < len(text):
        ch = text[i]
        if quote:
            out.append(ch)
            if ch == quote:
                # '' 转义？
                if quote == "'" and i + 1 < len(text) and text[i + 1] == "'":
                    out.append(text[i + 1])
                    i += 2
                    continue
                quote = None
            elif quote == '"' and ch == "\\" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
                continue
            i += 1
            continue
        if ch in "'\"":
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "#" and (i == 0 or text[i - 1] in " \t"):
            break
        out.append(ch)
        i += 1
    return "".join(out).rstrip()


def _unquote(text):
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
        inner = text[1:-1]
        if text[0] == "'":
            return inner.replace("''", "'")
        return (inner.replace('\\"', '"').replace("\\n", "\n")
                       .replace("\\t", "\t").replace("\\\\", "\\"))
    return None


def split_key(text):
    """把 `key: value` 拆成 (key, value)。value 可能是 None（后面跟嵌套块）。"""
    text = text.strip()
    if not text:
        return None, None
    # 引号开头的 key
    if text[0] in "'\"":
        q = text[0]
        i = 1
        while i < len(text):
            if text[i] == q:
                break
            i += 1
        if i >= len(text):
            raise YamlError("引号未闭合: %r" % text)
        key = _unquote(text[: i + 1])
        rest = text[i + 1:]
        if not rest.startswith(":"):
            return None, None
        rest = rest[1:].strip()
        return key, (rest if rest else None)
    # 裸 key：找第一个 ':' 且其后是空白或行尾
    depth = 0
    for i, ch in enumerate(text):
        if ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
        elif ch == ":" and depth == 0:
            after = text[i + 1:]
            if after == "" or after[0] in " \t":
                key = text[:i].strip()
                val = after.strip()
                return (key, val if val else None)
    return None, None


def _is_map_entry(text):
    key, _ = split_key(text)
    return key is not None


# ---------------------------------------------------------------------------
# flow 集合（单行）
# ---------------------------------------------------------------------------

def _parse_flow(text):
    value, pos = _flow_value(text, 0)
    rest = text[pos:].strip()
    if rest:
        raise YamlError("flow 集合后有多余内容: %r" % rest)
    return value


def _flow_skip(text, i):
    while i < len(text) and text[i] in " \t":
        i += 1
    return i


def _flow_value(text, i):
    i = _flow_skip(text, i)
    if i >= len(text):
        raise YamlError("flow 集合意外结束")
    ch = text[i]
    if ch == "[":
        items = []
        i += 1
        while True:
            i = _flow_skip(text, i)
            if i >= len(text):
                raise YamlError("flow 列表未闭合")
            if text[i] == "]":
                return items, i + 1
            val, i = _flow_value(text, i)
            items.append(val)
            i = _flow_skip(text, i)
            if i < len(text) and text[i] == ",":
                i += 1
    if ch == "{":
        out = {}
        i += 1
        while True:
            i = _flow_skip(text, i)
            if i >= len(text):
                raise YamlError("flow 映射未闭合")
            if text[i] == "}":
                return out, i + 1
            # key
            if text[i] in "'\"":
                q = text[i]
                j = i + 1
                while j < len(text) and text[j] != q:
                    j += 1
                key = _unquote(text[i: j + 1])
                i = j + 1
            else:
                j = text.find(":", i)
                if j < 0:
                    raise YamlError("flow 映射缺 ':'")
                key = text[i:j].strip()
                i = j
            i = _flow_skip(text, i)
            if i < len(text) and text[i] == ":":
                i += 1
                val, i = _flow_value(text, i)
            else:
                val = None
            out[key] = val
            i = _flow_skip(text, i)
            if i < len(text) and text[i] == ",":
                i += 1
    # 标量
    j = i
    if ch in "'\"":
        q = ch
        j = i + 1
        while j < len(text):
            if text[j] == q:
                break
            j += 1
        return _unquote(text[i: j + 1]), j + 1
    while j < len(text) and text[j] not in ",]}":
        j += 1
    return _scalar(text[i:j].strip()), j


# ---------------------------------------------------------------------------
# 标量
# ---------------------------------------------------------------------------

_BOOL = {"true": True, "false": False, "True": True, "False": False,
         "TRUE": True, "FALSE": False}
_NULL = {"null", "Null", "NULL", "~", ""}


def _scalar(text):
    text = text.strip()
    unq = _unquote(text)
    if unq is not None:
        return unq
    if text in _NULL:
        return None
    if text in _BOOL:
        return _BOOL[text]
    if re.fullmatch(r"[-+]?\d+", text):
        try:
            return int(text)
        except ValueError:
            return text
    if re.fullmatch(r"[-+]?(\d+\.\d*|\.\d+|\d+)([eE][-+]?\d+)?", text):
        try:
            return float(text)
        except ValueError:
            return text
    if text.startswith(("{", "[")):
        return _parse_flow(text)
    return text


# ---------------------------------------------------------------------------
# 分词
# ---------------------------------------------------------------------------

class _Tok:
    __slots__ = ("indent", "kind", "key", "text", "body", "style", "dash_col",
                 "map_key", "block_body", "block_style")

    def __init__(self, indent, kind, key=None, text=None, body=None, style=None,
                 dash_col=0, map_key=None, block_body=None, block_style=None):
        self.indent = indent
        self.kind = kind          # entry | block | seqitem
        self.key = key
        self.text = text
        self.body = body
        self.style = style
        self.dash_col = dash_col
        self.map_key = map_key          # seqitem 是 `- key: |` 时的 key
        self.block_body = block_body    # seqitem 是 `- key: |` 时的块标量内容
        self.block_style = block_style


def _tokenize(text, lineno_base=0):
    raw_lines = text.split("\n")
    toks = []
    i = 0
    while i < len(raw_lines):
        raw = raw_lines[i]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            i += 1
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        content = _strip_comment(stripped)

        # ---- 序列项 ----
        if content == "-" or content.startswith("- "):
            if content == "-":
                toks.append(_Tok(indent, "seqitem", text=None, dash_col=indent))
                i += 1
                continue
            after = content[1:]
            lead = len(after) - len(after.lstrip(" "))
            body = after.strip()
            dash_col = indent + 1 + lead

            # `- key: |` —— 序列项本身就是块标量（kustomize 会把 rego 渲染成这样）
            mkey, mval = split_key(body)
            if mkey is not None and mval in ("|", "|-", "|+", ">", ">-", ">+"):
                body_lines = []
                j = i + 1
                block_indent = None
                while j < len(raw_lines):
                    l = raw_lines[j]
                    if not l.strip():
                        body_lines.append("")
                        j += 1
                        continue
                    ind = len(l) - len(l.lstrip(" "))
                    if ind <= dash_col:
                        break
                    if block_indent is None:
                        block_indent = ind
                    body_lines.append(l[block_indent:] if len(l) >= block_indent else l.strip())
                    j += 1
                while body_lines and body_lines[-1] == "":
                    body_lines.pop()
                toks.append(_Tok(indent, "seqitem", text=None, dash_col=dash_col,
                                 map_key=mkey, block_body=body_lines,
                                 block_style=mval))
                i = j
                continue

            toks.append(_Tok(indent, "seqitem", text=body, dash_col=dash_col))
            i += 1
            continue

        # ---- 映射项 ----
        key, val = split_key(content)
        if key is None:
            raise YamlError("第 %d 行无法解析: %r" % (lineno_base + i + 1, stripped))
        if val in ("|", "|-", "|+", ">", ">-", ">+"):
            # 块标量：收集缩进更大的行
            body_lines = []
            j = i + 1
            block_indent = None
            while j < len(raw_lines):
                l = raw_lines[j]
                if not l.strip():
                    body_lines.append("")
                    j += 1
                    continue
                ind = len(l) - len(l.lstrip(" "))
                if ind <= indent:
                    break
                if block_indent is None:
                    block_indent = ind
                body_lines.append(l[block_indent:] if len(l) >= block_indent else l.strip())
                j += 1
            # 去掉尾部空行（chomping 决定要不要留）
            while body_lines and body_lines[-1] == "":
                body_lines.pop()
            toks.append(_Tok(indent, "block", key=key, body=body_lines, style=val))
            i = j
            continue
        toks.append(_Tok(indent, "entry", key=key, text=val))
        i += 1
    return toks


def _render_block(body, style):
    if style.startswith(">"):
        text = ""
        for idx, line in enumerate(body):
            if not line:
                text += "\n"
            elif idx == 0 or not body[idx - 1]:
                text += line
            else:
                text += " " + line
        text += "\n"
    else:
        text = "\n".join(body)
        if body:
            text += "\n"
    if style.endswith("-"):
        text = text.rstrip("\n")
    return text


# ---------------------------------------------------------------------------
# 解析
# ---------------------------------------------------------------------------

def _parse_map(toks, i, indent):
    result = {}
    while i < len(toks) and toks[i].indent == indent and toks[i].kind in ("entry", "block"):
        t = toks[i]
        if t.kind == "block":
            result[t.key] = _render_block(t.body, t.style)
            i += 1
            continue
        if t.text is None:
            if i + 1 < len(toks):
                nt = toks[i + 1]
                if nt.indent > indent:
                    val, i = _parse_block(toks, i + 1, nt.indent)
                elif nt.indent == indent and nt.kind == "seqitem":
                    val, i = _parse_seq(toks, i + 1, indent)
                else:
                    val = None
                    i += 1
            else:
                val = None
                i += 1
        else:
            val = _scalar(t.text)
            i += 1
        result[t.key] = val
    return result, i


def _parse_seq(toks, i, indent):
    items = []
    while i < len(toks) and toks[i].indent == indent and toks[i].kind == "seqitem":
        t = toks[i]
        if t.map_key is not None:
            # `- key: |` → 就地转成块标量 entry，再按映射解析（拿得到后面的兄弟键）
            toks[i] = _Tok(t.dash_col, "block", key=t.map_key,
                           body=t.block_body, style=t.block_style)
            val, i = _parse_map(toks, i, t.dash_col)
            items.append(val)
        elif t.text is None:
            if i + 1 < len(toks) and toks[i + 1].indent > indent:
                val, i = _parse_block(toks, i + 1, toks[i + 1].indent)
            else:
                val = None
                i += 1
        elif _is_map_entry(t.text):
            # 内联映射：`- key: value` 及其后续同缩进兄弟键。
            # ⚠️ 必须**就地**解析：兄弟键可能排在更深的嵌套键之后
            #    （例：`labels: [- pairs: {a: b}\n    includeSelectors: false]`），
            #    拷贝过滤一遍会漏掉后面的兄弟键。
            key, val_txt = split_key(t.text)
            toks[i] = _Tok(t.dash_col, "entry", key=key, text=val_txt)
            val, i = _parse_map(toks, i, t.dash_col)
            items.append(val)
        else:
            items.append(_scalar(t.text))
            i += 1
    return items, i


def _parse_block(toks, i, indent):
    if toks[i].kind == "seqitem":
        return _parse_seq(toks, i, indent)
    return _parse_map(toks, i, indent)


def load_all(text):
    """解析多文档 YAML，返回 list。空文档会被跳过。"""
    docs = []
    current = []
    for line in text.split("\n"):
        if line.strip() == "---":
            docs.append("\n".join(current))
            current = []
            continue
        if line.strip() == "...":
            continue
        current.append(line)
    docs.append("\n".join(current))

    out = []
    for doc in docs:
        if not doc.strip():
            continue
        toks = _tokenize(doc)
        if not toks:
            continue
        value, _ = _parse_block(toks, 0, toks[0].indent)
        out.append(value)
    return out


def load(text):
    """解析单文档 YAML（取第一个文档）。"""
    docs = load_all(text)
    return docs[0] if docs else None


def load_file(path):
    with open(path, encoding="utf-8") as fh:
        return load(fh.read())


def load_all_files(path):
    with open(path, encoding="utf-8") as fh:
        return load_all(fh.read())


# ---------------------------------------------------------------------------
# Argo CD git 文件生成器的 flatten 语义
# ---------------------------------------------------------------------------

def flatten(obj, keys=None, prefix=""):
    """
    模拟 Argo CD `git.files[].flatten` 的行为。

    flatten 列表里的每个 key，若其值是标量 → 变成模板参数；
    若是字典 → 递归展开成 `a.b` 形式。
    """
    out = {}
    if not isinstance(obj, dict):
        return out
    if keys is None:
        keys = list(obj.keys())
    for key in keys:
        if key not in obj:
            continue
        value = obj[key]
        name = f"{prefix}{key}"
        if isinstance(value, dict):
            out.update(flatten(value, list(value.keys()), prefix=f"{name}."))
        elif isinstance(value, list):
            for idx, item in enumerate(value):
                if isinstance(item, dict):
                    out.update(flatten(item, list(item.keys()), prefix=f"{name}."))
                else:
                    out[f"{name}.{idx}"] = item
        else:
            out[name] = value
    return out


def select_equal(obj, expression):
    """
    极简 JMESPath：只支持 `key == "value"` / `key != "value"` / 裸 `key`。

    Argo CD 的 `selector` 常用这种简单比较；复杂表达式直接报错而不是猜。
    """
    expr = (expression or "").strip()
    if not expr:
        return True
    m = re.match(r'^([A-Za-z_][\w.]*)\s*(==|!=)\s*[\'"](.*)[\'"]$', expr)
    if m:
        key, op, want = m.group(1), m.group(2), m.group(3)
        cur = obj
        for part in key.split("."):
            if isinstance(cur, dict) and part in cur:
                cur = cur[part]
            else:
                cur = None
                break
        if op == "==":
            return str(cur) == want
        return str(cur) != want
    m = re.match(r'^([A-Za-z_][\w.]*)$', expr)
    if m:
        cur = obj
        for part in m.group(1).split("."):
            if isinstance(cur, dict) and part in cur:
                cur = cur[part]
            else:
                return False
        return bool(cur)
    raise YamlError("暂不支持的 selector 表达式: %r" % expression)
