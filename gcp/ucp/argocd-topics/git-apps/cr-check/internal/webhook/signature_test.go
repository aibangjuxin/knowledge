package webhook

import (
	"testing"
)

func TestVerifySignature(t *testing.T) {
	secret := []byte("s3cr3t")
	body := []byte(`{"action":"opened"}`)

	sig := Sign(secret, body)

	t.Run("正确签名通过", func(t *testing.T) {
		if err := VerifySignature(secret, body, sig); err != nil {
			t.Fatalf("期望通过，得到错误: %v", err)
		}
	})
	t.Run("错误签名被拒", func(t *testing.T) {
		if err := VerifySignature(secret, body, "sha256=deadbeef"); err == nil {
			t.Fatal("期望失败，却通过了")
		}
	})
	t.Run("body 被篡改被拒", func(t *testing.T) {
		if err := VerifySignature(secret, []byte(`{"action":"closed"}`), sig); err == nil {
			t.Fatal("期望失败，却通过了")
		}
	})
	t.Run("缺少签名头被拒", func(t *testing.T) {
		if err := VerifySignature(secret, body, ""); err == nil {
			t.Fatal("期望失败，却通过了")
		}
	})
	t.Run("空 secret 跳过校验（仅本地调试）", func(t *testing.T) {
		if err := VerifySignature(nil, body, ""); err != nil {
			t.Fatalf("期望跳过，得到错误: %v", err)
		}
	})
}
