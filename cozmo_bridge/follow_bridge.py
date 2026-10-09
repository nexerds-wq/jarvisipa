"""Experimental Cozmo color-following bridge.

pip install cozmo opencv-python numpy pillow
Set COZMO_TOKEN to a long random secret, e.g. in PowerShell:
  $env:COZMO_TOKEN="choose-a-long-random-secret"
  python follow_bridge.py
Requires the official Cozmo SDK connection via its companion phone app.
"""
import json
import math
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import cv2
import numpy as np
import cozmo
from cozmo.util import degrees, distance_mm, speed_mmps

TOKEN = os.environ.get("COZMO_TOKEN", "")
if len(TOKEN) < 16:
    raise SystemExit("Set COZMO_TOKEN to at least 16 characters before starting.")
state = {"active": False, "settings": {}, "updated": 0}
lock = threading.Lock()
COLORS = {
    "Red": [(0, 10), (170, 179)], "Orange": [(10, 23)],
    "Yellow": [(23, 38)], "Green": [(38, 85)], "Blue": [(85, 130)],
    "Purple": [(130, 155)], "Pink": [(155, 170)],
}
def get_mask(hsv, names, sensitivity):
    tolerance = max(0, int((sensitivity - 50) / 12))
    result = np.zeros(hsv.shape[:2], np.uint8)
    for name in names:
        if name in COLORS:
            for low, high in COLORS[name]:
                result |= cv2.inRange(hsv, np.array([max(0, low-tolerance), 75, 55]),
                                     np.array([min(179, high+tolerance), 255, 255]))
        elif name in ("White", "Gray", "Black", "Brown"):
            ranges = {"White": ([0, 0, 170], [179, 60, 255]),
                      "Gray": ([0, 0, 55], [179, 60, 170]),
                      "Black": ([0, 0, 0], [179, 255, 55]),
                      "Brown": ([5, 65, 20], [28, 255, 170])}
            a,b = ranges[name]
            result |= cv2.inRange(hsv, np.array(a), np.array(b))
    return cv2.morphologyEx(result, cv2.MORPH_OPEN, np.ones((3,3), np.uint8))

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/command":
            self.send_error(404); return
        if self.headers.get("X-Cozmo-Token") != TOKEN:
            self.send_error(403); return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 1 or length > 8192: raise ValueError("Invalid length")
            payload = json.loads(self.rfile.read(length))
            cmd = payload["command"]
            settings = payload.get("settings", {})
            if cmd not in ("configure", "start", "stop", "keepalive"): raise ValueError("Unknown command")
            if cmd == "start" and settings.get("target") != "Shoes":
                raise ValueError("Only experimental Shoes mode is implemented")
            if cmd == "start" and not settings.get("colors"):
                raise ValueError("Select at least one color")
            with lock:
                if cmd != "stop": state["settings"] = settings
                state["active"] = (cmd == "start") if cmd in ("start", "stop") else state["active"]
                state["updated"] = time.monotonic()
            self.send_response(200); self.end_headers(); self.wfile.write(b'{"ok":true}')
        except (ValueError, KeyError, TypeError) as exc:
            self.send_error(400, str(exc))
    def log_message(self, *args): pass

def robot_loop(robot):
    robot.camera.image_stream_enabled = True
    robot.set_head_angle(degrees(-10)).wait_for_completed()
    last_image = None
    while True:
        with lock:
            active = state["active"]
            settings = dict(state["settings"])
            updated = state["updated"]
        # Fail safe if phone disconnects. Commands must be refreshed within 10s.
        if not active or time.monotonic()-updated > 10:
            robot.stop_all_motors()
            time.sleep(.1)
            continue
        image = robot.world.latest_image
        if image is None or image is last_image:
            robot.stop_all_motors()
            time.sleep(.1)
            continue
        last_image = image
        hsv = cv2.cvtColor(np.asarray(image.raw_image.convert("RGB")), cv2.COLOR_RGB2HSV)
        mask = get_mask(hsv, settings.get("colors", []), float(settings.get("sensitivity", 50)))
        contours,_ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contours = [c for c in contours if cv2.contourArea(c) >= 200]
        if not contours:
            robot.stop_all_motors(); time.sleep(.1); continue
        c = max(contours, key=cv2.contourArea)
        x,y,w,h = cv2.boundingRect(c)
        height,width = mask.shape
        error = ((x+w/2)-width/2)/(width/2)
        area = cv2.contourArea(c)/(width*height)
        if abs(error) > .25:
            robot.turn_in_place(degrees(max(-9,min(9,-error*12)))).wait_for_completed()
        elif area < .12:
            robot.drive_straight(distance_mm(25), speed_mmps(min(50,max(10,float(settings.get("speed",25)))))).wait_for_completed()
        else:
            robot.stop_all_motors()

def main(robot):
    server = ThreadingHTTPServer(("0.0.0.0", 8765), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print("Cozmo controller on port 8765. Keep robot on clear flat floor.")
    try: robot_loop(robot)
    finally:
        robot.stop_all_motors()
        server.shutdown()

if __name__ == "__main__":
    cozmo.run_program(main, use_viewer=False)
