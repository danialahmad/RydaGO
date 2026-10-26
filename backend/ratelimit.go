package main

import (
	"math"
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"
)

// limiter is a token bucket per key: it allows [burst] requests at once and then
// [perMinute] per minute. In memory, so it resets when the API restarts and is
// per instance, which is fine for a single-server deployment.
type limiter struct {
	mu        sync.Mutex
	buckets   map[string]*bucket
	perSecond float64
	burst     float64
	now       func() time.Time
	lastSweep time.Time
}

type bucket struct {
	tokens float64
	last   time.Time
}

func newLimiter(perMinute, burst int) *limiter {
	return &limiter{
		buckets:   map[string]*bucket{},
		perSecond: float64(perMinute) / 60,
		burst:     float64(burst),
		now:       time.Now,
	}
}

// allow takes one token for key. When it refuses, wait says how long until one is free.
func (l *limiter) allow(key string) (ok bool, wait time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	l.sweep(now)
	b := l.buckets[key]
	if b == nil {
		b = &bucket{tokens: l.burst, last: now}
		l.buckets[key] = b
	}
	b.tokens = math.Min(l.burst, b.tokens+now.Sub(b.last).Seconds()*l.perSecond)
	b.last = now
	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}
	return false, time.Duration((1 - b.tokens) / l.perSecond * float64(time.Second))
}

// sweep forgets full, idle buckets now and then so the map cannot grow forever.
func (l *limiter) sweep(now time.Time) {
	if now.Sub(l.lastSweep) < 5*time.Minute {
		return
	}
	l.lastSweep = now
	for k, b := range l.buckets {
		if now.Sub(b.last) > 10*time.Minute {
			delete(l.buckets, k)
		}
	}
}

// limit rejects requests over the limit with 429 and a Retry-After header.
// keyOf picks who is being limited (an IP, or the signed-in user).
func limit(l *limiter, keyOf func(*http.Request) string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if ok, wait := l.allow(keyOf(r)); !ok {
				w.Header().Set("Retry-After", strconv.Itoa(int(math.Ceil(wait.Seconds()))))
				writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": "too many requests, slow down"})
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// clientIP is the peer address. X-Forwarded-For is deliberately ignored: nothing
// trusted sits in front of the API, so the header could be forged to dodge limits.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// userKey limits per signed-in user (the auth middleware has already run).
func userKey(r *http.Request) string {
	uid, _ := r.Context().Value(userCtxKey{}).(int64)
	return "u" + strconv.FormatInt(uid, 10)
}
