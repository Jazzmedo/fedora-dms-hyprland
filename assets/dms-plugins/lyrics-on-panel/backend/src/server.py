import asyncio
import json
from lyrics_manager import LyricsManager
from mpris_player import MprisPlayer
import websockets


def route(*paths):
    """Decorator to mark a method as a WebSocket route handler."""
    def decorator(func):
        func._ws_routes = [p.lstrip("/") for p in paths]
        return func
    return decorator


class LyricsServer:
    """
    WebSocket server for lyrics display clients.

    Endpoints:
        ws://host:port/healthcheck  -> {"status": "ok"}
        ws://host:port/poll         -> {...player state...}
        ws://host:port/control      <- {"action": "play|pause|...", "player": "..."}
    """
    def __init__(self, host="127.0.0.1", port=23560):
        self.host = host
        self.port = port
        self.http_port = 23561
        self.manager = LyricsManager()
        self._routes = self._collect_routes()
        self._connection_paths = {}


    def _collect_routes(self):
        """Collect all methods decorated with @route."""
        routes = {}
        for name in dir(self):
            method = getattr(self, name)
            if callable(method) and hasattr(method, "_ws_routes"):
                for path in method._ws_routes:
                    routes[path] = method
        return routes


    def process_request(self, connection, request):
        """Store the request path for later use in handler."""
        self._connection_paths[id(connection)] = request.path.strip("/")


    async def handler(self, websocket):
        path = self._connection_paths.pop(id(websocket), "")
        handler = self._routes.get(path)
        if handler:
            await handler(websocket)
        else:
            await websocket.close(1008, f"Unknown endpoint: /{path}")


    @route("/healthcheck")
    async def healthcheck(self, websocket):
        await websocket.send(json.dumps({"status": "ok"}))


    @route("/poll")
    async def poll(self, websocket):
        global cnt
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    requested_player = data.get("player")
                    loop = asyncio.get_running_loop()
                    state = await loop.run_in_executor(None, self.manager.poll_status, requested_player)
                    await websocket.send(json.dumps(state))
                except json.JSONDecodeError:
                    await websocket.send(json.dumps({"error": "Invalid JSON"}))
        except websockets.ConnectionClosed:
            pass


    @route("/control")
    async def control(self, websocket):
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    action = data.get("action")
                    player_name = data.get("player")
                    loop = asyncio.get_running_loop()
                    success = await loop.run_in_executor(None, self._execute_control, action, player_name)
                    await websocket.send(json.dumps({"success": success}))
                except json.JSONDecodeError:
                    await websocket.send(json.dumps({"error": "Invalid JSON"}))
        except websockets.ConnectionClosed:
            pass


    def _execute_control(self, action, player_name):
        """Execute playback control. Returns True on success, False on failure."""
        name = player_name or self.manager.playername
        if not name:
            return False
        player = MprisPlayer(name)
        if not player or not player.obj:
            return False
        actions = {
            "play": player.play,
            "pause": player.pause,
            "play_pause": player.play_pause,
            "stop": player.stop,
            "next": player.next,
            "previous": player.previous,
            "raise": player.raise_player,
            "quit": player.quit,
        }
        if action not in actions:
            return False
        try:
            actions[action]()
            return True
        except Exception:
            return False


    def _start_http(self):
        """Serve the same payloads over plain HTTP for QML clients.

        Fedora ships no QtWebSockets QML module, so the DMS widget polls
        these endpoints with XMLHttpRequest instead of a WebSocket:
            GET /poll?player=<name>                  -> player + lyrics state
            GET /control?action=<a>&player=<name>    -> run a playback action
            GET /healthcheck                         -> {"status": "ok"}
        """
        import threading
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        from urllib.parse import urlparse, parse_qs

        server = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                parsed = urlparse(self.path)
                query = parse_qs(parsed.query)
                if parsed.path == "/poll":
                    player = (query.get("player") or [""])[0] or None
                    body = json.dumps(server.manager.poll_status(player))
                elif parsed.path == "/control":
                    action = (query.get("action") or [""])[0]
                    player = (query.get("player") or [""])[0] or None
                    body = json.dumps({"success": server._execute_control(action, player)})
                elif parsed.path == "/healthcheck":
                    body = json.dumps({"status": "ok"})
                else:
                    self.send_response(404)
                    self.end_headers()
                    return
                raw = body.encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def log_message(self, *args):
                pass

        httpd = ThreadingHTTPServer((self.host, self.http_port), Handler)
        threading.Thread(target=httpd.serve_forever, daemon=True, name="http-api").start()

    async def run(self):
        async with websockets.serve(
            self.handler,
            self.host,
            self.port,
            process_request=self.process_request
        ):
            self._start_http()
            await asyncio.Future()

if __name__ == "__main__":
    server = LyricsServer()
    try:
        asyncio.run(server.run())
    except KeyboardInterrupt:
        pass