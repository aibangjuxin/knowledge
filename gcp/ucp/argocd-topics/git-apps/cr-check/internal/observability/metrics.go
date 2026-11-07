// Package observability 提供 Prometheus 指标。
package observability

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Metrics 汇总了服务用到的全部指标。
type Metrics struct {
	Registry *prometheus.Registry

	WebhookReceived *prometheus.CounterVec
	WebhookRejected *prometheus.CounterVec
	JobsTotal       *prometheus.CounterVec
	RuleFailed      *prometheus.CounterVec
	EvaluationTime  prometheus.Histogram
	CRPlatformCalls *prometheus.CounterVec
	GitHubAPIErrors *prometheus.CounterVec
	ChecksWritten   prometheus.Counter
	RecheckScanned  prometheus.Counter
	RecheckFlipped  prometheus.Counter
	QueueDepth      prometheus.Gauge
}

// New 构造并注册全部指标。
func New() *Metrics {
	reg := prometheus.NewRegistry()
	m := &Metrics{
		Registry: reg,
		WebhookReceived: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "cr_check_webhook_received_total",
			Help: "收到的 webhook 事件数",
		}, []string{"event", "action"}),
		WebhookRejected: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "cr_check_webhook_rejected_total",
			Help: "被拒绝的 webhook 请求数",
		}, []string{"reason"}),
		JobsTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "cr_check_evaluations_total",
			Help: "判定任务数",
		}, []string{"result"}),
		RuleFailed: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "cr_check_rule_failed_total",
			Help: "各条规则失败次数（★ 哪个规则最常拦人）",
		}, []string{"rule_id"}),
		EvaluationTime: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name:    "cr_check_evaluation_duration_seconds",
			Help:    "判定耗时",
			Buckets: prometheus.DefBuckets,
		}),
		CRPlatformCalls: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "cr_check_crplatform_requests_total",
			Help: "CR 平台调用次数",
		}, []string{"result"}),
		GitHubAPIErrors: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "cr_check_github_api_errors_total",
			Help: "GitHub API 错误数",
		}, []string{"code"}),
		ChecksWritten: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "cr_check_checks_written_total",
			Help: "写入 check run 的次数",
		}),
		RecheckScanned: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "cr_check_recheck_scanned_total",
			Help: "定时重扫检查的 PR 数",
		}),
		RecheckFlipped: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "cr_check_recheck_flipped_total",
			Help: "★ 重扫时结论发生翻转的次数（= 事件丢失的量度）",
		}),
		QueueDepth: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "cr_check_queue_depth",
			Help: "异步队列积压深度",
		}),
	}
	reg.MustRegister(
		m.WebhookReceived, m.WebhookRejected, m.JobsTotal, m.RuleFailed,
		m.EvaluationTime, m.CRPlatformCalls, m.GitHubAPIErrors,
		m.ChecksWritten, m.RecheckScanned, m.RecheckFlipped, m.QueueDepth,
	)
	return m
}

// Handler 返回 /metrics 的 HTTP handler。
func (m *Metrics) Handler() http.Handler {
	return promhttp.HandlerFor(m.Registry, promhttp.HandlerOpts{})
}
