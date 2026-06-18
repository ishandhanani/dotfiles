# Perfetto Browser Snapshot Recipe

Use this when the user asks for a Perfetto visual snapshot or wants proof that a trace renders correctly in `ui.perfetto.dev`.

## Inputs

- Perfetto/Chrome trace JSON path, usually under `/tmp/*.perfetto.json`.
- Desired screenshot path, usually `/tmp/<trace-name>-perfetto-snapshot.png`.

## Serve The Trace

Serve the directory containing the trace. `ui.perfetto.dev` fetches from the browser, so the local server needs CORS and private-network headers.

```bash
python3 -u - <<'PY'
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import os

os.chdir("/tmp")

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

ThreadingHTTPServer(("127.0.0.1", 9001), Handler).serve_forever()
PY
```

Pick another free port if `9001` is taken.

## Launch Chrome

Use a fresh profile and DevTools. The `url=` import is usually enough, but a plain `--screenshot` can fire too early, while Perfetto still says `Opening trace`.

```bash
TRACE_URL="http://127.0.0.1:9001/name.perfetto.json"
UI_URL="https://ui.perfetto.dev/#!/?url=${TRACE_URL}"

google-chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage \
  --disable-web-security \
  --disable-features=BlockInsecurePrivateNetworkRequests,PrivateNetworkAccessSendPreflights \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/perfetto-chrome-profile \
  --window-size=1800,1000 \
  "$UI_URL"
```

## Wait And Capture With CDP

Poll real content before capture. For Dynamo request traces, useful text includes `Dynamo request trace`, trajectory IDs, `tools`, or expected tool labels.

```bash
python3 - <<'PY'
import asyncio, base64, json, urllib.request
import websockets

OUT = "/tmp/perfetto-snapshot.png"
EXPECTED = ("Dynamo request trace", "tools")

async def main():
    tabs = json.load(urllib.request.urlopen("http://127.0.0.1:9222/json"))
    tab = next(t for t in tabs if t.get("type") == "page")
    async with websockets.connect(tab["webSocketDebuggerUrl"], max_size=20_000_000) as c:
        msg_id = 0

        async def call(method, params=None):
            nonlocal msg_id
            msg_id += 1
            await c.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
            while True:
                msg = json.loads(await c.recv())
                if msg.get("id") == msg_id:
                    return msg

        await call("Runtime.enable")
        await call("Page.enable")

        for _ in range(60):
            result = await call(
                "Runtime.evaluate",
                {"expression": "document.body.innerText", "returnByValue": True},
            )
            text = result.get("result", {}).get("result", {}).get("value") or ""
            if all(s in text for s in EXPECTED):
                break
            await asyncio.sleep(1)

        # Optional cleanup for cleaner screenshots: cookie OK button / left nav.
        for x, y in [(520, 812), (201, 24)]:
            await call("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": 1})
            await call("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x, "y": y, "button": "left", "clickCount": 1})
            await asyncio.sleep(0.5)

        shot = await call("Page.captureScreenshot", {"format": "png", "captureBeyondViewport": False})
        open(OUT, "wb").write(base64.b64decode(shot["result"]["data"]))
        print(OUT)

asyncio.run(main())
PY
```

Then inspect:

```bash
# Use the local image-view tool in the agent runtime.
```

If the screenshot shows the Perfetto home page, `Opening trace`, or an empty timeline, do not hand it back. Check the local HTTP server logs for the trace `GET`, inspect `document.body.innerText`, wait longer, or use the UI's own import path again.

## Cleanup

Stop Chrome and the temporary HTTP server. Verify no transient ports remain:

```bash
ss -ltnp | rg ':(9001|9222)\b' || true
```
