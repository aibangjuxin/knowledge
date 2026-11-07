// Package webhook 实现 GitHub 事件的接收与派发。
package webhook

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
)

// ErrBadSignature 表示验签失败。
var ErrBadSignature = errors.New("webhook 签名校验失败")

// Sign 计算 HMAC-SHA256 签名（GitHub 的 sha256=<hex> 格式）。
// ★ 这是本地构造测试请求用的辅助函数。
func Sign(secret, body []byte) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write(body)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

// VerifySignature 校验 X-Hub-Signature-256。
//
// ★ 必须用 hmac.Equal 而不是 == （防时序攻击）。
// secret 为空时跳过校验（仅限本地调试）。
func VerifySignature(secret, body []byte, header string) error {
	if len(secret) == 0 {
		return nil
	}
	if header == "" {
		return fmt.Errorf("%w: 缺少 X-Hub-Signature-256", ErrBadSignature)
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write(body)
	expected := "sha256=" + hex.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(header)) {
		return ErrBadSignature
	}
	return nil
}
