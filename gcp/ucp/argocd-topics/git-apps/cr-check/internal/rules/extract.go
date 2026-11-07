package rules

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

// Extraction 是"从 PR 里解析变更单号"的结果。
type Extraction struct {
	// Numbers 是解析到的全部候选编号（去重后排序）。
	Numbers []string
	// Sources 记录每个编号来自哪个载体（label / body）。
	Sources map[string]string
	// Conflict 表示不同载体给出了**不同**的编号 —— 这是错误，不能静默取优先级最高的。
	Conflict bool
}

// First 返回第一个候选编号。
func (e Extraction) First() string {
	if len(e.Numbers) == 0 {
		return ""
	}
	return e.Numbers[0]
}

// ExtractCRNumbers 从 PR 的 label 和 body 里解析变更单号。
//
// 支持的载体（按顺序）：
//  1. label：匹配 labelPattern 的 label，去掉 labelPrefix 得到编号
//  2. body / commit trailer：以 bodyMarker 开头的那一行（大小写不敏感）
//
// ★ 规则 R1a：必须且只能解析出**一个**编号。
// 0 个 → 没带；多个 → 歧义（尤其是多个载体冲突）。
func ExtractCRNumbers(labels []string, body, labelPattern, labelPrefix, bodyMarker string) Extraction {
	out := Extraction{Sources: map[string]string{}}

	if labelPattern == "" {
		labelPattern = `^cr/[0-9A-Za-z._-]+$`
	}
	if labelPrefix == "" {
		labelPrefix = "cr/"
	}
	if bodyMarker == "" {
		bodyMarker = "Change-Request:"
	}

	re, err := regexp.Compile(labelPattern)
	if err == nil {
		for _, l := range labels {
			l = strings.TrimSpace(l)
			if !re.MatchString(l) {
				continue
			}
			num := strings.TrimSpace(strings.TrimPrefix(l, labelPrefix))
			if num == "" {
				continue
			}
			out.add(num, "label:"+l)
		}
	}

	// body marker：^(marker)\s*(number)$
	marker := regexp.QuoteMeta(bodyMarker)
	bre := regexp.MustCompile(`(?im)^\s*` + marker + `\s*([0-9A-Za-z][0-9A-Za-z._/-]*)\s*$`)
	for _, m := range bre.FindAllStringSubmatch(body, -1) {
		num := strings.TrimSpace(m[1])
		if num == "" {
			continue
		}
		out.add(num, "body")
	}

	if len(out.Numbers) > 1 {
		out.Conflict = true
	}
	return out
}

// add 记录一个候选编号。
func (e *Extraction) add(num, source string) {
	if _, ok := e.Sources[num]; ok {
		return
	}
	e.Sources[num] = source
	e.Numbers = append(e.Numbers, num)
	sort.Strings(e.Numbers)
}

// Describe 返回人类可读的解析摘要（写进 check 输出）。
func (e Extraction) Describe() string {
	if len(e.Numbers) == 0 {
		return "未找到任何变更单号"
	}
	parts := make([]string, 0, len(e.Numbers))
	for _, n := range e.Numbers {
		parts = append(parts, fmt.Sprintf("%s（来自 %s）", n, e.Sources[n]))
	}
	return strings.Join(parts, ", ")
}
