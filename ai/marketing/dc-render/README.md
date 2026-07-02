# dc-render — Claude Design scene → MP4

Renders claude.ai/design animation scenes (Stage/Sprite engine) to video, frame-by-frame.

Setup: `npm i playwright-core` (uses chromium from ~/Library/Caches/ms-playwright).

Usage:
1. Pull scene files from the Design project via DesignSync (animations.jsx, scene.jsx, assets/).
2. `python3 -m http.server 8944` in this dir.
3. `SCENE_URL=http://127.0.0.1:8944/index.html FPS=30 node render.js` → frames/
4. `ffmpeg -framerate 30 -i frames/f-%04d.png -vf scale=1080:1920 -c:v libx264 -pix_fmt yuv420p -crf 18 out.mp4`

Key: engine listens for `data-om-seek-to-time-frame` CustomEvent on the stage svg — deterministic seek per frame. Element screenshots can be 1px off → always scale in ffmpeg (yuv420p needs even dims).
