package main

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/slack-go/slack"
)

func envRequired(key string) string {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		fmt.Fprintf(os.Stderr, "missing %s\n", key)
		os.Exit(1)
	}
	return v
}

func parseDuration(s string) int64 {
	re := regexp.MustCompile(`^(\d+)([smhdw])$`)
	m := re.FindStringSubmatch(strings.TrimSpace(s))
	if m == nil {
		fmt.Fprintf(os.Stderr, "bad SLACK_RANGE %q (use 24h, 7d, 1w)\n", s)
		os.Exit(1)
	}
	n, _ := strconv.ParseInt(m[1], 10, 64)
	mult := map[string]int64{"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}
	return n * mult[m[2]]
}

func resolveChannel(name string) string {
	name = strings.TrimPrefix(strings.TrimSpace(name), "#")
	if matched, _ := regexp.MatchString(`^[CGD][A-Z0-9]+$`, name); matched {
		return name
	}
	fmt.Fprintf(os.Stderr, "SLACK_CHANNEL must be a channel ID (e.g. C03E674JKNH), got %q\n", name)
	fmt.Fprintln(os.Stderr, "Tip: open channel in Slack -> click channel name -> copy Channel ID from the bottom")
	os.Exit(1)
	return ""
}

type userCache struct {
	api   *slack.Client
	cache map[string]string
}

func newUserCache(api *slack.Client) *userCache {
	return &userCache{api: api, cache: make(map[string]string)}
}

// Resolve user ID to display name. users.info is Tier 4 (100+ req/min).
func (uc *userCache) resolve(userID string) string {
	if userID == "" {
		return ""
	}
	if name, ok := uc.cache[userID]; ok {
		return name
	}

	for retries := 0; retries < 5; retries++ {
		user, err := uc.api.GetUserInfo(userID)
		if err != nil {
			if rlErr, ok := err.(*slack.RateLimitedError); ok {
				fmt.Fprintf(os.Stderr, "rate limited on users.info, waiting %v\n", rlErr.RetryAfter)
				time.Sleep(rlErr.RetryAfter)
				continue
			}
			fmt.Fprintf(os.Stderr, "users.info %s: %v\n", userID, err)
			uc.cache[userID] = userID
			return userID
		}
		name := user.RealName
		if name == "" {
			name = user.Profile.DisplayName
		}
		if name == "" {
			name = user.Name
		}
		uc.cache[userID] = name
		return name
	}

	uc.cache[userID] = userID
	return userID
}

type enrichedMessage struct {
	UserName  string          `json:"user_name,omitempty"`
	Timestamp string          `json:"timestamp"`
	Raw       json.RawMessage `json:"raw"`
}

func main() {
	token := envRequired("SLACK_TOKEN")
	api := slack.New(token)
	users := newUserCache(api)

	channel := strings.TrimSpace(os.Getenv("CHANNEL"))
	if channel == "" {
		channel = strings.TrimSpace(os.Getenv("SLACK_CHANNEL"))
	}
	if channel == "" {
		fmt.Fprintln(os.Stderr, "missing CHANNEL or SLACK_CHANNEL")
		os.Exit(1)
	}

	rangeStr := os.Getenv("SLACK_RANGE")
	if rangeStr == "" {
		rangeStr = "7d"
	}

	channelID := resolveChannel(channel)
	now := time.Now()
	oldest := now.Add(-time.Duration(parseDuration(rangeStr)) * time.Second)

	enc := json.NewEncoder(os.Stdout)
	total := 0
	cursor := ""

	for {
		params := &slack.GetConversationHistoryParameters{
			ChannelID: channelID,
			Oldest:    strconv.FormatInt(oldest.Unix(), 10),
			Latest:    strconv.FormatInt(now.Unix(), 10),
			Limit:     200,
			Cursor:    cursor,
		}

		resp, err := api.GetConversationHistory(params)
		if err != nil {
			if rlErr, ok := err.(*slack.RateLimitedError); ok {
				fmt.Fprintf(os.Stderr, "rate limited, waiting %v\n", rlErr.RetryAfter)
				time.Sleep(rlErr.RetryAfter)
				continue
			}
			fmt.Fprintf(os.Stderr, "error fetching history: %v\n", err)
			os.Exit(1)
		}

		for _, msg := range resp.Messages {
			rawBytes, _ := json.Marshal(msg)

			ts, _ := strconv.ParseFloat(msg.Timestamp, 64)
			humanTS := time.Unix(int64(ts), 0).UTC().Format(time.RFC3339)

			enriched := enrichedMessage{
				UserName:  users.resolve(msg.User),
				Timestamp: humanTS,
				Raw:       rawBytes,
			}
			enc.Encode(enriched)
			total++
		}

		if !resp.HasMore {
			break
		}
		cursor = resp.ResponseMetaData.NextCursor
		time.Sleep(2 * time.Second)
	}

	fmt.Fprintf(os.Stderr, "fetched %d messages, resolved %d users\n", total, len(users.cache))
}
