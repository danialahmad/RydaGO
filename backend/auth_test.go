package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func testServer() *server {
	return &server{jwtSecret: []byte(strings.Repeat("k", 32))}
}

func TestIssueTokenRoundTrip(t *testing.T) {
	s := testServer()
	tok, err := s.issueToken(42)
	if err != nil {
		t.Fatal(err)
	}
	var claims jwt.RegisteredClaims
	_, err = jwt.ParseWithClaims(tok, &claims, func(*jwt.Token) (any, error) { return s.jwtSecret, nil },
		jwt.WithValidMethods([]string{"HS256"}))
	if err != nil {
		t.Fatal(err)
	}
	if claims.Subject != "42" {
		t.Errorf("subject %q, want 42", claims.Subject)
	}
	if ttl := time.Until(claims.ExpiresAt.Time); ttl < 6*24*time.Hour || ttl > 7*24*time.Hour+time.Minute {
		t.Errorf("token lifetime %v, want about 7 days", ttl)
	}
}

func signWith(t *testing.T, method jwt.SigningMethod, key any, claims jwt.RegisteredClaims) string {
	t.Helper()
	tok, err := jwt.NewWithClaims(method, claims).SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	return tok
}

func TestRequireAuth(t *testing.T) {
	s := testServer()
	future := jwt.NewNumericDate(time.Now().Add(time.Hour))
	past := jwt.NewNumericDate(time.Now().Add(-time.Hour))
	otherKey := []byte(strings.Repeat("z", 32))

	valid := signWith(t, jwt.SigningMethodHS256, s.jwtSecret, jwt.RegisteredClaims{Subject: "7", ExpiresAt: future})
	cases := []struct {
		name   string
		header string
		want   int
	}{
		{"valid token", "Bearer " + valid, 200},
		{"no header", "", 401},
		{"missing Bearer prefix", valid, 401},
		{"garbage", "Bearer abc.def.ghi", 401},
		{"expired", "Bearer " + signWith(t, jwt.SigningMethodHS256, s.jwtSecret, jwt.RegisteredClaims{Subject: "7", ExpiresAt: past}), 401},
		{"no expiry", "Bearer " + signWith(t, jwt.SigningMethodHS256, s.jwtSecret, jwt.RegisteredClaims{Subject: "7"}), 401},
		{"wrong key", "Bearer " + signWith(t, jwt.SigningMethodHS256, otherKey, jwt.RegisteredClaims{Subject: "7", ExpiresAt: future}), 401},
		{"non-numeric subject", "Bearer " + signWith(t, jwt.SigningMethodHS256, s.jwtSecret, jwt.RegisteredClaims{Subject: "admin", ExpiresAt: future}), 401},
		{"alg none", "Bearer " + signWith(t, jwt.SigningMethodNone, jwt.UnsafeAllowNoneSignatureType, jwt.RegisteredClaims{Subject: "7", ExpiresAt: future}), 401},
		{"tampered signature", "Bearer " + valid[:len(valid)-3] + "xyz", 401},
	}
	for _, c := range cases {
		var gotUser int64
		next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			gotUser, _ = r.Context().Value(userCtxKey{}).(int64)
			w.WriteHeader(http.StatusOK)
		})
		rec := httptest.NewRecorder()
		req := httptest.NewRequest("POST", "/reports", nil)
		if c.header != "" {
			req.Header.Set("Authorization", c.header)
		}
		s.requireAuth(next).ServeHTTP(rec, req)
		if rec.Code != c.want {
			t.Errorf("%s: status %d, want %d", c.name, rec.Code, c.want)
		}
		if c.want == 200 && gotUser != 7 {
			t.Errorf("%s: user id in context = %d, want 7", c.name, gotUser)
		}
	}
}

func TestRegisterValidatesBeforeTouchingTheDatabase(t *testing.T) {
	s := testServer() // no DB: any request that reached it would panic
	cases := []struct {
		name, body string
	}{
		{"bad json", `{`},
		{"bad email", `{"email":"not-an-email","password":"password123"}`},
		{"password too short", `{"email":"a@b.my","password":"1234567"}`},
		{"password too long for bcrypt", `{"email":"a@b.my","password":"` + strings.Repeat("p", 73) + `"}`},
	}
	for _, c := range cases {
		rec := httptest.NewRecorder()
		s.register(rec, httptest.NewRequest("POST", "/auth/register", strings.NewReader(c.body)))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: status %d, want 400 (%s)", c.name, rec.Code, rec.Body)
		}
	}
	rec := httptest.NewRecorder()
	s.login(rec, httptest.NewRequest("POST", "/auth/login", strings.NewReader(`{`)))
	if rec.Code != http.StatusBadRequest {
		t.Errorf("login bad json: status %d, want 400", rec.Code)
	}
}

func TestReadCredentialsNormalisesEmail(t *testing.T) {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("POST", "/", strings.NewReader(`{"email":"  Test@Example.MY ","password":"x"}`))
	c, ok := readCredentials(rec, req)
	if !ok || c.Email != "test@example.my" {
		t.Errorf("got %+v ok=%v", c, ok)
	}
}
