// Package queue 提供幂等去重存储与异步任务队列。
package queue

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// Store 是幂等去重存储。
//
// ★ 多副本下**不能**用进程内 Map（副本之间不共享 → 重复处理）。
// 生产用 Redis，本地开发用内存实现。
type Store interface {
	// Seen 判断某个 key 是否见过。
	Seen(ctx context.Context, key string) (bool, error)
	// Remember 记住一个 key（带 TTL）。
	Remember(ctx context.Context, key string, ttl time.Duration) error
}

// ── 内存实现 ────────────────────────────────────────────────

type memEntry struct {
	expires time.Time
}

// MemoryStore 是进程内的去重存储（仅限单副本 / 本地开发）。
type MemoryStore struct {
	mu      sync.Mutex
	entries map[string]memEntry
}

// NewMemoryStore 构造内存存储。
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{entries: map[string]memEntry{}}
}

// Seen 实现 Store。
func (s *MemoryStore) Seen(_ context.Context, key string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.entries[key]
	if !ok {
		return false, nil
	}
	if time.Now().After(e.expires) {
		delete(s.entries, key)
		return false, nil
	}
	return true, nil
}

// Remember 实现 Store。
func (s *MemoryStore) Remember(_ context.Context, key string, ttl time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.entries[key] = memEntry{expires: time.Now().Add(ttl)}
	return nil
}

// ── Redis 实现 ──────────────────────────────────────────────

// RedisStore 用 Redis 做幂等去重。
type RedisStore struct {
	client *redis.Client
	prefix string
}

// NewRedisStore 构造 Redis 存储。
func NewRedisStore(addr, password string, db int, prefix string) *RedisStore {
	if prefix == "" {
		prefix = "cr-check:delivery:"
	}
	return &RedisStore{
		client: redis.NewClient(&redis.Options{
			Addr: addr, Password: password, DB: db,
		}),
		prefix: prefix,
	}
}

// Seen 实现 Store。
func (s *RedisStore) Seen(ctx context.Context, key string) (bool, error) {
	n, err := s.client.Exists(ctx, s.prefix+key).Result()
	if err != nil {
		return false, fmt.Errorf("redis exists: %w", err)
	}
	return n > 0, nil
}

// Remember 实现 Store。
func (s *RedisStore) Remember(ctx context.Context, key string, ttl time.Duration) error {
	if err := s.client.Set(ctx, s.prefix+key, "1", ttl).Err(); err != nil {
		return fmt.Errorf("redis set: %w", err)
	}
	return nil
}

// Close 关闭连接。
func (s *RedisStore) Close() error { return s.client.Close() }

// ─────────────────────────────────────────────────────────────
// 异步任务队列
// ─────────────────────────────────────────────────────────────

// Job 是一次待判定的任务。
type Job struct {
	Event      string
	DeliveryID string
	Payload    []byte
	ReceivedAt time.Time
}

// Queue 是进程内的异步任务队列。
//
// ⚠️ 生产环境应该用 Redis Streams / Cloud Tasks / PubSub 等外部队列，
// 这样 Pod 重启时在途任务不会丢。本实现适合本地与单副本场景。
type Queue struct {
	ch      chan Job
	workers int
}

// NewQueue 构造队列。
func NewQueue(buffer, workers int) *Queue {
	if buffer <= 0 {
		buffer = 256
	}
	if workers <= 0 {
		workers = 4
	}
	return &Queue{ch: make(chan Job, buffer), workers: workers}
}

// Push 投递一个任务（队列满时返回 false）。
func (q *Queue) Push(j Job) bool {
	select {
	case q.ch <- j:
		return true
	default:
		return false
	}
}

// Depth 返回队列积压深度。
func (q *Queue) Depth() int { return len(q.ch) }

// Start 启动 worker，直到 ctx 被取消。
func (q *Queue) Start(ctx context.Context, handler func(Job)) {
	var wg sync.WaitGroup
	for i := 0; i < q.workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				select {
				case <-ctx.Done():
					return
				case j, ok := <-q.ch:
					if !ok {
						return
					}
					handler(j)
				}
			}
		}()
	}
	go func() {
		<-ctx.Done()
		wg.Wait()
	}()
}
