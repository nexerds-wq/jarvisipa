"""Track a magenta target shown on an iPhone screen using Cozmo's camera.

pip install cozmo opencv-python numpy pillow
Connect Cozmo to the computer through the official Cozmo SDK setup.
Open phone_target.html on the phone, turn up brightness and face its screen
toward Cozmo. Run: python follow_phone.py
Only operate on a clear flat floor, away from edges, pets, and stairs.
"""
import time
import cv2
import numpy as np
import cozmo
from cozmo.util import degrees, distance_mm, speed_mmps

MIN_AREA = 180
TARGET_AREA_FRACTION = 0.12
LOST_LIMIT = 1.0

def run(robot):
    robot.camera.image_stream_enabled = True
    robot.set_head_angle(degrees(10)).wait_for_completed()
    last_seen = time.monotonic()
    print("Show the bright magenta phone target to Cozmo. Ctrl+C to stop.")
    try:
        while True:
            image = robot.world.latest_image
            if image is None:
                robot.stop_all_motors()
                time.sleep(0.15)
                continue
            rgb = np.asarray(image.raw_image.convert("RGB"))
            hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
            # HSV OpenCV hue is 0..179. Magenta falls near 145..170.
            mask = cv2.inRange(hsv, np.array([135, 110, 100]),
                              np.array([175, 255, 255]))
            mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN,
                                    np.ones((3, 3), np.uint8))
            contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL,
                                           cv2.CHAIN_APPROX_SIMPLE)
            if not contours:
                robot.stop_all_motors()
                if time.monotonic() - last_seen > LOST_LIMIT:
                    print("Target lost; stopped")
                time.sleep(0.15)
                continue
            contour = max(contours, key=cv2.contourArea)
            area = cv2.contourArea(contour)
            height, width = mask.shape
            if area < MIN_AREA:
                robot.stop_all_motors()
                time.sleep(0.15)
                continue
            last_seen = time.monotonic()
            x, y, w, h = cv2.boundingRect(contour)
            error = ((x + w / 2) - width / 2) / (width / 2)
            fraction = area / (width * height)
            # Short, bounded actions ensure a new camera observation
            # before each movement. This is not obstacle avoidance.
            if abs(error) > 0.22:
                robot.turn_in_place(degrees(max(-12, min(12, -error * 15)))).wait_for_completed()
            elif fraction < TARGET_AREA_FRACTION:
                robot.drive_straight(distance_mm(35), speed_mmps(30)).wait_for_completed()
            else:
                robot.stop_all_motors()
                time.sleep(0.2)
    finally:
        robot.stop_all_motors()

if __name__ == "__main__":
    cozmo.run_program(run, use_viewer=False)
