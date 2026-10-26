package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestLimiterBurstThenRefill(t *testing.T) {
	now := time.Unix(1000, 0)
	l := newLimiter(6, 3) // 3 at once, then one every 10 s
	l.now = func() time.Time { return now }
	for i := 0; i < 3; i++ {
		if ok, _ := l.allow("a"); !ok {
			t.Fatalf("request %d inside the burst was refused", i+1)
		}
	}
	ok, wait := l.allow("a")
	if ok || wait < 9*time.Second || wait > 11*time.Second {
		t.Fatalf("4th request: ok=%v wait=%v, want refused with ~10 s wait", ok, wait)
	}
	if ok, _ := l.allow("b"); !ok {
		t.Error("another key must have its own bucket")
	}
	now = now.Add(10 * time.Second)
	if ok, _ := l.allow("a"); !ok {
		t.Error("a token should have refilled after 10 s")
	}
	if ok, _ := l.allow("a"); ok {
		t.Error("only one token should have refilled")
	}
}

func TestLimiterSweepsIdleBuckets(t *testing.T) {
	now := time.Unix(1000, 0)
	l := newLimiter(60, 5)
	l.now = func() time.Time { return now }
	l.allow("gone")
	now = now.Add(20 * time.Minute)
	l.allow("fresh")
	if _, still := l.buckets["gone"]; still {
		t.Error("idle bucket should have been swept")
	}
}

func TestLimitMiddlewareReturns429WithRetryAfter(t *testing.T) {
	h := limit(newLimiter(60, 2), clientIP)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	var codes []int
	var last *httptest.ResponseRecorder
	for i := 0; i < 3; i++ {
		last = httptest.NewRecorder()
		req := httptest.NewRequest("POST", "/auth/login", nil)
		req.RemoteAddr = "203.0.113.9:5555"
		req.Header.Set("X-Forwarded-For", "198.51.100."+string(rune('1'+i))) // must not dodge the limit
		h.ServeHTTP(last, req)
		codes = append(codes, last.Code)
	}
	if codes[0] != 200 || codes[1] != 200 || codes[2] != http.StatusTooManyRequests {
		t.Fatalf("codes = %v, want 200 200 429", codes)
	}
	if last.Header().Get("Retry-After") == "" {
		t.Error("429 needs a Retry-After header")
	}
}

func TestClientIPIgnoresPort(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "203.0.113.9:5555"
	if got := clientIP(r); got != "203.0.113.9" {
		t.Errorf("clientIP = %q", got)
	}
}
