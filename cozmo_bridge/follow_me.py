"""Cozmo follows a visible face using the official Cozmo Python SDK.

Requirements: pip install cozmo
Connect the Cozmo app in SDK mode to the computer as described by Anki's SDK.
Run: python follow_me.py

Use on a clear, flat floor away from stairs. Ctrl+C stops the program.
"""
import math
import time
import cozmo
from cozmo.util import distance_mm, speed_mmps, degrees

STOP_DISTANCE_MM = 350
MAX_STEP_MM = 90
MAX_TURN_DEGREES = 18
SEARCH_TIMEOUT = 3.0


def follow(robot: cozmo.robot.Robot):
    robot.enable_device_imu(True)
    robot.set_head_angle(degrees(10)).wait_for_completed()
    print("Following visible faces. Press Ctrl+C to stop.")
    try:
        while True:
            try:
                face = robot.world.wait_for_observed_face(timeout=SEARCH_TIMEOUT)
            except cozmo.exceptions.Timeout:
                robot.stop_all_motors()
                print("No face visible; stopped.")
                continue

            # Face pose is relative to Cozmo's current frame. Re-observe after
            # every short movement; never drive continuously without feedback.
            position = face.pose.position
            forward = float(position.x)
            lateral = float(position.y)
            if not (math.isfinite(forward) and math.isfinite(lateral)):
                robot.stop_all_motors()
                continue

            angle = math.degrees(math.atan2(lateral, max(forward, 1.0)))
            if abs(angle) > 8:
                turn = max(-MAX_TURN_DEGREES, min(MAX_TURN_DEGREES, angle))
                robot.turn_in_place(degrees(turn)).wait_for_completed()
                continue

            if forward > STOP_DISTANCE_MM:
                step = min(MAX_STEP_MM, forward - STOP_DISTANCE_MM)
                robot.drive_straight(distance_mm(step), speed_mmps(40)).wait_for_completed()
            else:
                robot.stop_all_motors()
                time.sleep(0.25)
    finally:
        robot.stop_all_motors()


if __name__ == "__main__":
    cozmo.run_program(follow, use_viewer=False, force_viewer_on_top=False)
