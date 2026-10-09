"""Experimental shoe-following mode for Cozmo's official Python SDK.

Requires: pip install cozmo opencv-python numpy pillow
Connect Cozmo through the official app's SDK mode.
Run: python follow_shoes.py

Place one shoe in front of Cozmo during calibration. Click its color in
the camera preview; Cozmo then follows the largest nearby matching patch.
Press q or Ctrl+C to stop. Clear flat floor only, never near stairs.
"""
import time
import cv2
import numpy as np
import cozmo
from cozmo.util import degrees, distance_mm, speed_mmps

selected_hsv = None
STOP_AREA = 0.12
MIN_AREA = 150
MAX_FRAME_AGE = 0.8

def main(robot):
    global selected_hsv
    robot.camera.image_stream_enabled = True
    robot.set_head_angle(degrees(-10)).wait_for_completed()
    cv2.namedWindow("Cozmo shoes - click shoe color, q stops")

    def click(event, x, y, flags, userdata):
        global selected_hsv
        if event == cv2.EVENT_LBUTTONDOWN and userdata is not None:
            frame = userdata["hsv"]
            if 0 <= y < frame.shape[0] and 0 <= x < frame.shape[1]:
                selected_hsv = frame[y, x].astype(int)
                print("Tracking shoe color HSV:", selected_hsv.tolist())

    context = {"hsv": None}
    cv2.setMouseCallback("Cozmo shoes - click shoe color, q stops", click, context)
    previous_image = None
    try:
        while True:
            img = robot.world.latest_image
            if img is None or img is previous_image:
                robot.stop_all_motors()
                if cv2.waitKey(80) & 255 == ord("q"):
                    break
                continue
            previous_image = img
            rgb = np.asarray(img.raw_image.convert("RGB"))
            hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
            context["hsv"] = hsv
            preview = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
            if selected_hsv is not None:
                h, s, v = selected_hsv
                # Reject low-saturation colors: dark/white shoes need a more
                # sophisticated detector and would match floors and shadows.
                if s < 55 or v < 50:
                    robot.stop_all_motors()
                    cv2.putText(preview, "Choose a brighter colored shoe area",
                                (8, 20), cv2.FONT_HERSHEY_SIMPLEX, .4, (0, 0, 255), 1)
                else:
                    dh = 12
                    lo = np.array([max(0, h-dh), max(50, s-85), max(40, v-85)], dtype=np.uint8)
                    hi = np.array([min(179, h+dh), 255, 255], dtype=np.uint8)
                    mask = cv2.inRange(hsv, lo, hi)
                    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3,3), np.uint8))
                    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                    contours = [c for c in contours if cv2.contourArea(c) >= MIN_AREA]
                    if not contours:
                        robot.stop_all_motors()
                    else:
                        c = max(contours, key=cv2.contourArea)
                        x, y, w, hh = cv2.boundingRect(c)
                        cv2.rectangle(preview, (x,y), (x+w,y+hh), (0,255,0), 1)
                        height, width = mask.shape
                        err = ((x+w/2)-(width/2))/(width/2)
                        fraction = cv2.contourArea(c)/(width*height)
                        # Short movements only, re-observe after each one.
                        if abs(err) > .22:
                            robot.turn_in_place(degrees(max(-10, min(10, -err*12)))).wait_for_completed()
                        elif fraction < STOP_AREA:
                            robot.drive_straight(distance_mm(25), speed_mmps(25)).wait_for_completed()
                        else:
                            robot.stop_all_motors()
            else:
                robot.stop_all_motors()
                cv2.putText(preview, "Click your shoe color to calibrate",
                            (8,20), cv2.FONT_HERSHEY_SIMPLEX, .4, (255,255,255), 1)
            cv2.imshow("Cozmo shoes - click shoe color, q stops", preview)
            if cv2.waitKey(1) & 255 == ord("q"):
                break
    finally:
        robot.stop_all_motors()
        cv2.destroyAllWindows()

if __name__ == "__main__":
    cozmo.run_program(main, use_viewer=False)
