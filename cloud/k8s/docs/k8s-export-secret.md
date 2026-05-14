如果你想直接导出 **JSON**，同时排除掉 default-token，推荐用 jq 来做处理。

---

### **方式一：导出后用** 

### **jq**

###  **过滤**

```
kubectl get secret -n lex -o json \
  | jq 'del(.items[] | select(.metadata.name | test("^default-token")))'
```

这样会返回一个合法的 JSON，其中 default-token-xxx 的 secret 已经被删除。

---

### **方式二：导出资源名再单独 get**

```
kubectl get secret -n lex \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | grep -v '^default-token' \
  | xargs -I{} kubectl get secret -n lex {} -o json
```

这种方式会输出多个 JSON 对象（不是一个 JSON 数组）。

---

### **建议**

- 如果要保留和 kubectl get -o json 一样的整体结构（带 .items 数组），用 **方式一 (jq del)**。
    
- 如果想要逐个 Secret 的 JSON，可以用 **方式二**。
    

---

要不要我帮你写一个完整的脚本，可以对某个 namespace 导出 JSON（排除 default-token），然后保存成 secrets.json 文件？