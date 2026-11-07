package rules

import (
	"testing"
	"time"

	"github.com/acme/cr-check/internal/config"
)

func TestExtractCRNumbers(t *testing.T) {
	cases := []struct {
		name      string
		labels    []string
		body      string
		wantCount int
		wantFirst string
		wantConf  bool
	}{
		{
			name:      "label 载体",
			labels:    []string{"cr/1234", "feature"},
			body:      "",
			wantCount: 1, wantFirst: "1234",
		},
		{
			name:      "body marker 载体",
			labels:    nil,
			body:      "描述\n\nChange-Request: 5678\n",
			wantCount: 1, wantFirst: "5678",
		},
		{
			name:      "label 与 body 一致 → 去重后只有一个",
			labels:    []string{"cr/1234"},
			body:      "Change-Request: 1234",
			wantCount: 1, wantFirst: "1234",
		},
		{
			name:      "label 与 body 冲突 → 必须报冲突",
			labels:    []string{"cr/1234"},
			body:      "Change-Request: 5678",
			wantCount: 2, wantFirst: "1234", wantConf: true,
		},
		{
			name:      "没有任何变更单号",
			labels:    []string{"bug", "feature"},
			body:      "随便写点什么",
			wantCount: 0,
		},
		{
			name:      "非 CR label 被忽略",
			labels:    []string{"cr-not-a-cr", "cr/abc"},
			body:      "",
			wantCount: 1, wantFirst: "abc",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ExtractCRNumbers(tc.labels, tc.body, `^cr/[0-9A-Za-z._-]+$`, "cr/", "Change-Request:")
			if len(got.Numbers) != tc.wantCount {
				t.Fatalf("数量 = %d，期望 %d（结果 %v）", len(got.Numbers), tc.wantCount, got.Numbers)
			}
			if tc.wantCount > 0 && got.First() != tc.wantFirst {
				t.Errorf("首个编号 = %q，期望 %q", got.First(), tc.wantFirst)
			}
			if got.Conflict != tc.wantConf {
				t.Errorf("冲突标记 = %v，期望 %v", got.Conflict, tc.wantConf)
			}
		})
	}
}

func TestWindowContains(t *testing.T) {
	cfg := config.WindowConfig{
		Env:   "prd",
		Days:  []string{"Mon", "Tue", "Wed", "Thu", "Fri"},
		Start: "02:00",
		End:   "04:00",
		TZ:    "Asia/Shanghai",
	}
	w, err := ParseWindow(cfg, "Asia/Shanghai")
	if err != nil {
		t.Fatalf("解析窗口失败: %v", err)
	}
	loc := w.Loc

	// 2025-01-06 是周一
	cases := []struct {
		name string
		when time.Time
		want bool
	}{
		{"窗口开始（闭区间）", time.Date(2025, 1, 6, 2, 0, 0, 0, loc), true},
		{"窗口内", time.Date(2025, 1, 6, 3, 0, 0, 0, loc), true},
		{"窗口结束（开区间）", time.Date(2025, 1, 6, 4, 0, 0, 0, loc), false},
		{"窗口之前", time.Date(2025, 1, 6, 1, 59, 0, 0, loc), false},
		{"窗口之后", time.Date(2025, 1, 6, 10, 0, 0, 0, loc), false},
		{"周末", time.Date(2025, 1, 11, 3, 0, 0, 0, loc), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := w.Contains(tc.when); got != tc.want {
				t.Errorf("Contains(%s) = %v，期望 %v", tc.when, got, tc.want)
			}
		})
	}
}

func TestWindowCrossMidnight(t *testing.T) {
	cfg := config.WindowConfig{
		Env:   "prod",
		Days:  []string{"Mon"},
		Start: "22:00",
		End:   "02:00",
		TZ:    "Asia/Shanghai",
	}
	w, err := ParseWindow(cfg, "Asia/Shanghai")
	if err != nil {
		t.Fatalf("解析窗口失败: %v", err)
	}
	loc := w.Loc
	cases := []struct {
		name string
		when time.Time
		want bool
	}{
		{"周一 23:00", time.Date(2025, 1, 6, 23, 0, 0, 0, loc), true},
		{"周一 21:00", time.Date(2025, 1, 6, 21, 0, 0, 0, loc), false},
		{"周二 01:00（跨零点延续）", time.Date(2025, 1, 7, 1, 0, 0, 0, loc), true},
		{"周二 03:00", time.Date(2025, 1, 7, 3, 0, 0, 0, loc), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := w.Contains(tc.when); got != tc.want {
				t.Errorf("Contains(%s) = %v，期望 %v", tc.when, got, tc.want)
			}
		})
	}
}
