"""Stand-in for the model APIs (Anthropic Messages, OpenAI Responses, Gemini) and for the
app's usage endpoint, used by bin/capture-agent-otlp. Each CLI gets one canned reply with
known token counts; its raw OTLP export is stored under /out/raw, and the JSON
otlp-ingest forwards for it under /out."""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OUT = "/out"
COUNTER = {"n": 0}


def log(*args):
    print(*args, flush=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            return self.rfile.read(length)
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            data = b""
            while True:
                size = int(self.rfile.readline().strip() or b"0", 16)
                if size == 0:
                    self.rfile.readline()
                    break
                data += self.rfile.read(size)
                self.rfile.readline()
            return data
        return b""

    def _json(self, obj, status=200):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _sse(self, events):
        payload = "".join(events).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        log("GET", self.path)
        if "/models" in self.path:
            return self._json({"data": [], "models": [], "object": "list"})
        return self._json({})

    def do_POST(self):
        body = self._body()
        path = self.path
        log("POST", path, len(body))

        if path.split("?")[0] in ("/v1/metrics", "/v1/logs", "/v1/traces"):
            COUNTER["n"] += 1
            kind = path.split("?")[0].rsplit("/", 1)[1]
            ctype = (self.headers.get("Content-Type") or "").split(";")[0].replace("/", "_")
            name = os.path.join(OUT, "raw", f"{COUNTER['n']:03d}-{kind}-{ctype}.bin")
            os.makedirs(os.path.dirname(name), exist_ok=True)
            with open(name, "wb") as f:
                f.write(body)
            return self._json({})

        if path.startswith("/api/v1/internal/usage_statistics"):
            COUNTER["n"] += 1
            name = os.path.join(OUT, f"{int(time.time() * 1000)}-{COUNTER['n']}.json")
            with open(name, "wb") as f:
                f.write(body)
            return self._json({"ok": True})

        if path.startswith("/v1/messages/count_tokens"):
            return self._json({"input_tokens": 12})
        if path.startswith("/v1/messages"):
            return self._anthropic(body)
        if path.startswith("/v1/responses"):
            return self._openai_responses()
        if ":streamGenerateContent" in path:
            return self._gemini_stream()
        if ":generateContent" in path:
            return self._json(self._gemini_chunk(final=True))
        if ":countTokens" in path:
            return self._json({"totalTokens": 12})
        return self._json({})

    def _anthropic(self, body):
        try:
            req = json.loads(body or b"{}")
        except ValueError:
            req = {}
        model = req.get("model", "claude-sonnet-4-5")
        usage = {"input_tokens": 120, "output_tokens": 7, "cache_read_input_tokens": 30,
                 "cache_creation_input_tokens": 5}
        if not req.get("stream"):
            return self._json({"id": "msg_mock", "type": "message", "role": "assistant", "model": model,
                               "content": [{"type": "text", "text": "hi"}], "stop_reason": "end_turn",
                               "stop_sequence": None, "usage": usage})
        ev = lambda t, d: f"event: {t}\ndata: {json.dumps(d)}\n\n"
        self._sse([
            ev("message_start", {"type": "message_start", "message": {
                "id": "msg_mock", "type": "message", "role": "assistant", "model": model, "content": [],
                "stop_reason": None, "stop_sequence": None,
                "usage": {"input_tokens": 120, "output_tokens": 1, "cache_read_input_tokens": 30,
                          "cache_creation_input_tokens": 5}}}),
            ev("content_block_start", {"type": "content_block_start", "index": 0,
                                       "content_block": {"type": "text", "text": ""}}),
            ev("content_block_delta", {"type": "content_block_delta", "index": 0,
                                       "delta": {"type": "text_delta", "text": "hi"}}),
            ev("content_block_stop", {"type": "content_block_stop", "index": 0}),
            ev("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn",
                                                                    "stop_sequence": None},
                                 "usage": {"output_tokens": 7}}),
            ev("message_stop", {"type": "message_stop"}),
        ])

    def _openai_responses(self):
        rid = "resp_mock"
        item = {"id": "msg_mock", "type": "message", "role": "assistant", "status": "completed",
                "content": [{"type": "output_text", "text": "hi", "annotations": []}]}
        usage = {"input_tokens": 120, "input_tokens_details": {"cached_tokens": 30},
                 "output_tokens": 7, "output_tokens_details": {"reasoning_tokens": 2}, "total_tokens": 127}
        ev = lambda d: f"event: {d['type']}\ndata: {json.dumps(d)}\n\n"
        base = {"id": rid, "object": "response", "model": "gpt-5", "output": []}
        self._sse([
            ev({"type": "response.created", "response": {**base, "status": "in_progress"}}),
            ev({"type": "response.output_item.added", "output_index": 0,
                "item": {**item, "status": "in_progress", "content": []}}),
            ev({"type": "response.output_text.delta", "output_index": 0, "content_index": 0,
                "item_id": "msg_mock", "delta": "hi"}),
            ev({"type": "response.output_item.done", "output_index": 0, "item": item}),
            ev({"type": "response.completed", "response": {**base, "status": "completed", "output": [item],
                                                           "usage": usage}}),
        ])

    def _gemini_chunk(self, final):
        chunk = {"candidates": [{"content": {"role": "model", "parts": [{"text": "hi"}]}, "index": 0}],
                 "modelVersion": "gemini-2.5-pro"}
        if final:
            chunk["candidates"][0]["finishReason"] = "STOP"
            chunk["usageMetadata"] = {"promptTokenCount": 120, "candidatesTokenCount": 7,
                                      "cachedContentTokenCount": 30, "thoughtsTokenCount": 2,
                                      "totalTokenCount": 129}
        return chunk

    def _gemini_stream(self):
        self._sse([f"data: {json.dumps(self._gemini_chunk(final=True))}\n\n"])


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    log("mock listening", port)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
