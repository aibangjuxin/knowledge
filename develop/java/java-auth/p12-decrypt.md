# Q
在 Bash 里把 `.p12.pwd`(PKCS12 keystore 密码文件)做 base64,有两种写法:

```bash
# 方法 1 — echo + 命令替换
pwdEncode=$(echo -n $(cat $dir/*.p12.pwd) | base64)

# 方法 2 — 直接 base64 文件
pwdEncode=$(base64 -w 0 $dir/*.p12.pwd)
```

哪种是最佳实践?为什么?在 Java/PKI 解密场景里,这两行真的一样吗?

# Alm

## 一句话结论

**方法 1(`echo -n $(cat ...) | base64`)是最佳实践**。方法 2 在文件带尾部换行(几乎所有编辑器/重定向都会留)时,生成的 base64 串**不等于**真实密码的 base64,Java 用它解开 `.p12` 会直接报 `Decryption failed` 或更隐蔽的 `Given final block not properly padded`。

## 一、可复现验证

```bash
$ cd /tmp/p12test
$ printf 'MyP@ssw0rd!#$' > pwd-no-nl   # 13 bytes, 无尾部换行
$ echo  'MyP@ssw0rd!#$' > pwd-with-nl  # 14 bytes, 有尾部 \n

# 方法 1
$ echo -n $(cat pwd-no-nl)  | base64
TXlQQHNzdzByZCEjJA==
$ echo -n $(cat pwd-with-nl) | base64
TXlQQHNzdzByZCEjJA==        # ← 一样的

# 方法 2
$ base64 -i pwd-no-nl
TXlQQHNzdzByZCEjJA==
$ base64 -i pwd-with-nl
TXlQQHNzdzByZCEjJAo=         # ← 多了 "Ao="(0x0A = '\n')
```

注意 **macOS `base64` 没有 `-w 0`**(那是 GNU coreutils 的 flag),要用 `-i FILE`。BSD `base64` 默认 76 字符换行,要压成一行用 `-b 99999`(不是 `-w 0`)。

## 二、原理:为什么方法 1 永远对

### 方法 1:`echo -n $(cat FILE) | base64`

```bash
$(cat FILE)            # 命令替换:捕获 cat 输出
                       # 关键规则:末尾的换行符被吞掉,中间的换行保留
echo -n <captured>     # -n 禁止 echo 自己再加一个 \n
| base64               # 输入是纯密码字节,不带任何 \n
```

`$()` 在 POSIX shell 里定义就是 *"strip trailing newlines"*。配合 `echo -n` 禁止 echo 自己再加一个,最终 base64 的输入 = 文件中所有非末尾换行 + 末尾的最后一个非换行字符之前的内容 = **真正的密码字节序列**(不算文件结尾那个 `\n`)。

无论 `.p12.pwd` 是 `printf` 写的、编辑器存的、`echo > file` 写的、git 拉下来的,方法 1 都会产出同一个 base64。

### 方法 2:`base64 -i FILE`(或 `cat FILE | base64`)

`base64` 不知道也不在乎"密码文件"是什么语义,它就是个字节流编码器。文件里每一个 byte 都会被编码,包括末尾那个 `\n`:

```
密码 "MyP@ssw0rd!#$"      → base64 = TXlQQHNzdzByZCEjJA==
密码 "MyP@ssw0rd!#$\n"    → base64 = TXlQQHNzdzByZCEjJAo=    ← 不同的!
```

Java 拿到 `TXlQQHNzdzByZCEjJAo=` 解 base64,得到 `MyP@ssw0rd!#$\n`(13 字符 + 换行),用它去开 PKCS12,密码对不上 → 报错。

## 三、Java 端会发生什么

两种典型报错(取决于 JDK 实现):

```text
java.io.IOException: failed to decrypt safe contents entry:
    javax.crypto.BadPaddingException: Given final block not properly padded
        at sun.security.pkcs12.PKCS12KeyStore.engineLoad(...)
```

或更隐晦的:

```text
java.io.IOException: failed to decrypt safe contents entry:
    java.security.UnrecoverableKeyException: No PKCS12 encrypted data found
```

排查时人很容易被误导,以为是:
- `.p12` 本身损坏 ❌
- 证书密码记错 ❌
- JDK 版本不兼容 ❌

**真正的坑就是 `.p12.pwd` 文件末尾那个肉眼看不到的 `\n`**。

## 四、最佳实践

### 推荐(方法 1 模板)

```bash
dir=/path/to/keystore
pwdEncode=$(echo -n $(cat $dir/*.p12.pwd) | base64)

# 可选:一致性检查,防止 .p12.pwd 是空文件 / 多个文件 / 二进制乱码
[ "$(echo $pwdEncode | wc -c)" -gt 4 ] || { echo "empty or suspicious pwd file" >&2; exit 1; }

# 传给 Java(注意不要 echo 二次加 \n)
java -Djavax.net.ssl.keyStore=$dir/server.p12 \
     -Djavax.net.ssl.keyStorePassword="$pwdEncode" \
     -jar app.jar
```

### 反模式(方法 2)

```bash
# ❌ GNU-only, macOS/BSD 上直接 invalid argument
pwdEncode=$(base64 -w 0 $dir/*.p12.pwd)

# ❌ macOS 上能跑,但密码带尾部 \n 时 base64 不一致
pwdEncode=$(base64 -i $dir/*.p12.pwd)

# ❌ 同样问题,多一个 cat
pwdEncode=$(cat $dir/*.p12.pwd | base64)
```

### 跨平台兼容写法(Linux + macOS 都能跑)

```bash
# 任意 base64 实现,先 base64 再剥换行,效果等同 echo -n $(cat)
pwdEncode=$( (base64 "$dir/server.p12.pwd" 2>/dev/null || base64 -i "$dir/server.p12.pwd") \
            | tr -d '\n' )
```

但**这个写法仍然包含文件末尾 `\n`**,只有方法 1(命令替换吞换行 + echo -n)才能从根上把"密码"和"密码文件"区分开。

### 根治方案:写入时就别留换行

```bash
# 生成 .p12.pwd
printf '%s' 'MyP@ssw0rd!#$' > server.p12.pwd
#                                 ↑ 没有 \n
```

`printf '%s'` 不输出换行,`echo -n` 同理,`heredoc` + `<<-EOF` 同理。这是 0 依赖的根治法,任何 base64 实现都安全。

## 五、对照速查表

| 写入方式                     | 文件末尾字节 | 方法 1 base64 | 方法 2 base64 | 解密结果        |
| ---------------------------- | ------------ | ------------- | ------------- | --------------- |
| `printf '%s' 'pwd'`          | 无           | `TXl...JA==`  | `TXl...JA==`  | ✅ 成功         |
| `echo 'pwd'`                 | `\n`         | `TXl...JA==`  | `TXl...JAo=`  | 方法 2 ❌ 失败   |
| `echo -n 'pwd'`              | 无           | `TXl...JA==`  | `TXl...JA==`  | ✅ 成功         |
| 编辑器(vim/VSCode)保存       | 通常 `\n`    | `TXl...JA==`  | `TXl...JAo=`  | 方法 2 ❌ 失败   |
| `cat heredoc <<EOF` + `EOF`   | `\n`         | `TXl...JA==`  | `TXl...JAo=`  | 方法 2 ❌ 失败   |

## 六、TL;DR

> **`.p12.pwd` 是密码,不是密码+换行。** 用 `echo -n $(cat FILE) | base64` 让 `$()` 吞掉文件末尾的 `\n`,再用 `echo -n` 禁止 echo 再补一个。这是 shell 里"文件内容当作裸字符串"的标准范式,跨 GNU/BSD、跨 Linux/macOS、跨 `.p12`/`.jks`/任何 base64 用途都成立。