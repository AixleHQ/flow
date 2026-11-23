package rails

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func serve(t *testing.T, handler http.HandlerFunc) *Client {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	return New(srv.URL, "internal-token")
}

func TestHoldersAnswersTheSessionAndItsPorts(t *testing.T) {
	var path, auth string
	c := serve(t, func(w http.ResponseWriter, r *http.Request) {
		path, auth = r.URL.Path, r.Header.Get("Authorization")
		io.WriteString(w, `{"session_id":123,"environment_id":7,"state":"ready","ports":{"tty":7681},"future":true}`)
	})
	h, err := c.Holders(context.Background(), "abc")
	if err != nil {
		t.Fatal(err)
	}
	if path != "/api/v1/internal/runner_relay/holders/abc" || auth != "Bearer internal-token" {
		t.Fatalf("%s %s", path, auth)
	}
	if h.SessionID != 123 || h.EnvironmentID == nil || *h.EnvironmentID != 7 || h.Ports["tty"] != 7681 {
		t.Fatalf("%+v", h)
	}
}

func TestHoldersWithNoMachineHasNoEnvironment(t *testing.T) {
	c := serve(t, func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, `{"session_id":123,"environment_id":null,"state":"ready","ports":{}}`)
	})
	h, err := c.Holders(context.Background(), "abc")
	if err != nil || h.EnvironmentID != nil {
		t.Fatalf("%+v %v", h, err)
	}
}

func TestHoldersRefusalsAndWrongTypes(t *testing.T) {
	for name, tc := range map[string]struct {
		status int
		body   string
		is     error
	}{
		"unknown token": {404, ``, ErrNotFound},
		"server error":  {500, `oops`, nil},
		"wrong type":    {200, `{"session_id":"123","environment_id":7}`, nil},
		"no session":    {200, `{"environment_id":7}`, nil},
	} {
		c := serve(t, func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(tc.status); io.WriteString(w, tc.body) })
		_, err := c.Holders(context.Background(), "abc")
		if err == nil || (tc.is != nil && !errors.Is(err, tc.is)) {
			t.Errorf("%s: %v", name, err)
		}
	}
}

func TestChecksSendsTheBodyOfTheSchemaAndReadsTheAnswersInOrder(t *testing.T) {
	var body map[string]any
	c := serve(t, func(w http.ResponseWriter, r *http.Request) {
		json.NewDecoder(r.Body).Decode(&body)
		io.WriteString(w, `{"machines":[true,false]}`)
	})
	one := int64(5)
	got, err := c.Checks(context.Background(), []Machine{{EnvironmentID: 1, SessionID: &one}, {EnvironmentID: 2}})
	if err != nil || len(got) != 2 || !got[0] || got[1] {
		t.Fatalf("%v %v", got, err)
	}
	machines := body["machines"].([]any)
	first := machines[0].(map[string]any)
	second := machines[1].(map[string]any)
	if first["environment_id"] != float64(1) || first["session_id"] != float64(5) || second["session_id"] != nil {
		t.Fatalf("%v", body)
	}
}

func TestChecksRefusals(t *testing.T) {
	for name, tc := range map[string]struct {
		status int
		body   string
		is     error
	}{
		"invalid":       {422, `{"error":"x"}`, ErrInvalid},
		"unavailable":   {503, ``, nil},
		"wrong count":   {200, `{"machines":[true,true]}`, nil},
		"wrong type":    {200, `{"machines":["yes"]}`, nil},
		"not an answer": {200, `[]`, nil},
	} {
		c := serve(t, func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(tc.status); io.WriteString(w, tc.body) })
		_, err := c.Checks(context.Background(), []Machine{{EnvironmentID: 1}})
		if err == nil || (tc.is != nil && !errors.Is(err, tc.is)) {
			t.Errorf("%s: %v", name, err)
		}
	}
}

func TestTheObserverSeesEveryCallAndAnErrorDoesNotNameTheToken(t *testing.T) {
	var seen []string
	c := serve(t, func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(404) })
	c.Observe = func(endpoint, status string, _ time.Duration) { seen = append(seen, endpoint+" "+status) }
	c.Holders(context.Background(), "secret-route-token")
	c.BaseURL = "http://127.0.0.1:1"
	_, err := c.Holders(context.Background(), "secret-route-token")
	if err == nil || strings.Contains(err.Error(), "secret-route-token") {
		t.Fatalf("the error names the token: %v", err)
	}
	if len(seen) != 2 || seen[0] != "holders 404" || seen[1] != "holders error" {
		t.Fatalf("%v", seen)
	}
}
