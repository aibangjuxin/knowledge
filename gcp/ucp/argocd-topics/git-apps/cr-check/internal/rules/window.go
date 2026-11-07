package rules

import (
	"fmt"
	"strings"
	"time"

	"github.com/acme/cr-check/internal/config"
)

// Window 是一个按周重复的维护窗口（Maintenance Window）。
type Window struct {
	Env      string
	Days     map[time.Weekday]bool
	StartMin int
	EndMin   int
	Loc      *time.Location
	Raw      config.WindowConfig
}

// ParseWindow 从配置构造窗口。
func ParseWindow(cfg config.WindowConfig, defaultTZ string) (*Window, error) {
	tz := cfg.TZ
	if tz == "" {
		tz = defaultTZ
	}
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return nil, fmt.Errorf("窗口时区 %q 无效: %w", tz, err)
	}
	start, err := config.ParseHM(cfg.Start)
	if err != nil {
		return nil, fmt.Errorf("窗口 start 无效: %w", err)
	}
	end, err := config.ParseHM(cfg.End)
	if err != nil {
		return nil, fmt.Errorf("窗口 end 无效: %w", err)
	}
	w := &Window{
		Env:      cfg.Env,
		Days:     map[time.Weekday]bool{},
		StartMin: start,
		EndMin:   end,
		Loc:      loc,
		Raw:      cfg,
	}
	for _, d := range cfg.Days {
		wd, ok := parseWeekday(d)
		if !ok {
			return nil, fmt.Errorf("未知的星期: %q", d)
		}
		w.Days[wd] = true
	}
	return w, nil
}

// parseWeekday 解析 "Mon" / "Tuesday" 等写法。
func parseWeekday(s string) (time.Weekday, bool) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "sun", "sunday":
		return time.Sunday, true
	case "mon", "monday":
		return time.Monday, true
	case "tue", "tuesday":
		return time.Tuesday, true
	case "wed", "wednesday":
		return time.Wednesday, true
	case "thu", "thursday":
		return time.Thursday, true
	case "fri", "friday":
		return time.Friday, true
	case "sat", "saturday":
		return time.Saturday, true
	}
	return 0, false
}

// Contains 判断给定时刻是否落在窗口内。
//
// ★ 左闭右开 [start, end)。
// ★ 跨零点（start > end，如 22:00 → 02:00）被正确处理：
// 当天 start 之后算命中，前一天 start 的窗口延续到今天 end 之前算命中。
func (w *Window) Contains(t time.Time) bool {
	n := t.In(w.Loc)
	minute := n.Hour()*60 + n.Minute()

	if w.StartMin < w.EndMin {
		return w.Days[n.Weekday()] && minute >= w.StartMin && minute < w.EndMin
	}
	// 跨零点
	if minute >= w.StartMin && w.Days[n.Weekday()] {
		return true
	}
	if minute < w.EndMin {
		prev := n.AddDate(0, 0, -1).Weekday()
		return w.Days[prev]
	}
	return false
}

// Describe 返回人类可读的窗口描述。
func (w *Window) Describe() string {
	days := make([]string, 0, len(w.Days))
	for _, d := range []time.Weekday{time.Monday, time.Tuesday, time.Wednesday,
		time.Thursday, time.Friday, time.Saturday, time.Sunday} {
		if w.Days[d] {
			days = append(days, d.String()[:3])
		}
	}
	return fmt.Sprintf("%s %s-%s (%s)", strings.Join(days, ","),
		hhmm(w.StartMin), hhmm(w.EndMin), w.Loc)
}

// hhmm 把分钟数格式化成 HH:MM。
func hhmm(min int) string {
	return fmt.Sprintf("%02d:%02d", min/60, min%60)
}
