from ultralytics import YOLO
import cv2
import time
import csv
import numpy as np
import socket
import http.client
import urllib.request
import urllib.error
import urllib.parse
import gzip
import re
import signal
import requests  # For sending data to the backend
from datetime import datetime
from pathlib import Path
from deep_sort_realtime.deepsort_tracker import DeepSort

# YOLO model load
model = YOLO("yolov8n.pt")

# Deep SORT tracker initialization
tracker = DeepSort(
    max_age=30,
    n_init=3,
    embedder="mobilenet",
    embedder_gpu=False,  # Set to True if GPU available
)

# ESP32 camera base URL
BASE_CAMERA_URL = "http://172.19.198.23"

# Backend configuration
BACKEND_URL = "http://localhost:3000/update-student-count"
CLASSROOM_ID = "CR-01"  # Unique ID for this classroom/camera
UPDATE_INTERVAL_SECONDS = 5  # Send update to backend every 5 seconds

# Stability/performance settings
MAX_CONSECUTIVE_FAILURES = 20  # Auto-exit after 20 failures
RETRY_DELAY_SECONDS = 1
UNAVAILABLE_DELAY_SECONDS = 2
RESIZE_WIDTH = 1280  # Full screen laptop width
INFERENCE_EVERY_N_FRAMES = 1  # Run YOLO every frame (detect all students)
NETWORK_TIMEOUT_SECONDS = 10  # More tolerance for slow ESP32
READ_CHUNK_SIZE = 4096
CONF_THRESHOLD = 0.45  # Balanced threshold to keep true persons and reduce duplicate noise
MIN_BOX_AREA_RATIO = 0.005  # Ignore tiny noisy boxes
MAX_BOX_AREA_RATIO = 0.60  # Ignore oversized false boxes
LOG_INTERVAL_SECONDS = 10
LOG_FILE_PATH = Path(__file__).with_name("attendance.csv")
REID_MAX_DISTANCE = 120  # pixels
REID_MAX_SECONDS = 8.0   # seconds
REID_FALLBACK_DISTANCE = 320  # pixels, used when tracker resets on unstable frames
MIN_TRACK_HITS_FOR_COUNT = 4

# Stream endpoint discovery
DEFAULT_STREAM_PATHS = [
    ":81/stream",
    "/stream",
    "/mjpeg",
    "/cam.mjpeg",
    "/cam-hi.jpg",
    "/capture",
]

# Tracking state
unique_person_ids = set()  # All persons ever detected (persistent)
current_frame_ids = set()  # Current frame PERSON IDs
new_person_ids = set()  # Newly detected in THIS frame
last_log_time = 0.0
last_backend_update_time = 0.0
track_to_person_id = {}  # DeepSort track_id -> stable person_id
person_last_seen = {}  # person_id -> (cx, cy, timestamp)
track_hit_counts = {}  # track_id -> confirmed frame hits
next_person_id = 1


def init_attendance_csv(file_path):
    if not file_path.exists() or file_path.stat().st_size == 0:
        with open(file_path, "a", newline="", encoding="utf-8") as file:
            writer = csv.writer(file)
            writer.writerow(["timestamp", "total_unique_person_count"])


def append_attendance_log(file_path, total_count):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(file_path, "a", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow([timestamp, total_count])


def send_count_to_backend(current_count, unique_count):
    payload = {
        # Keep studentCount mapped to current count for app compatibility.
        "studentCount": current_count,
        "currentCount": current_count,
        "uniqueCount": unique_count,
        "classroomId": CLASSROOM_ID
    }
    try:
        response = requests.post(BACKEND_URL, json=payload, timeout=5)
        if response.status_code == 200:
            print(
                f"✅ Successfully sent current={current_count}, unique={unique_count} to backend."
            )
        else:
            print(f"⚠️ Backend error: {response.status_code} - {response.text}")
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to send count to backend: {e}")


def find_existing_person_id(cx, cy, now_ts):
    best_person_id = None
    best_distance = float("inf")

    for person_id, (px, py, pts) in person_last_seen.items():
        if now_ts - pts > REID_MAX_SECONDS:
            continue

        distance = ((cx - px) ** 2 + (cy - py) ** 2) ** 0.5
        if distance < REID_MAX_DISTANCE and distance < best_distance:
            best_distance = distance
            best_person_id = person_id

    return best_person_id


def find_recent_person_fallback_id(cx, cy, now_ts):
    best_person_id = None
    best_distance = float("inf")

    for person_id, (px, py, pts) in person_last_seen.items():
        if now_ts - pts > REID_MAX_SECONDS:
            continue

        distance = ((cx - px) ** 2 + (cy - py) ** 2) ** 0.5
        if distance < REID_FALLBACK_DISTANCE and distance < best_distance:
            best_distance = distance
            best_person_id = person_id

    return best_person_id


def build_stream_url_candidates(base_url):
    candidates = []

    for path in DEFAULT_STREAM_PATHS:
        if path.startswith(":"):
            parsed = urllib.parse.urlparse(base_url)
            host = parsed.hostname or parsed.netloc
            if host:
                candidates.append(f"{parsed.scheme}://{host}{path}")
        else:
            candidates.append(urllib.parse.urljoin(base_url.rstrip("/") + "/", path.lstrip("/")))

    # Try extracting stream-like paths from root page if available.
    try:
        req = urllib.request.Request(base_url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=NETWORK_TIMEOUT_SECONDS) as response:
            raw = response.read(250_000)
        if raw.startswith(b"\x1f\x8b"):
            raw = gzip.decompress(raw)
        html = raw.decode("utf-8", errors="ignore")

        # Include capture endpoints and exclude JS template artifacts like trailing backticks.
        found_paths = re.findall(r"/(?:stream|mjpeg|video|cam|capture)[^\"'` <>)]*", html, flags=re.IGNORECASE)
        found_full_urls = re.findall(r"https?://[^\"'` <>)]*(?:stream|mjpeg|video|cam|capture)[^\"'` <>)]*", html, flags=re.IGNORECASE)

        for path in found_paths:
            cleaned_path = path.rstrip("`\"'")
            if any(ch in cleaned_path for ch in ("{", "}", "$", "(", ")")):
                continue
            candidates.append(urllib.parse.urljoin(base_url.rstrip("/") + "/", cleaned_path.lstrip("/")))
        for full_url in found_full_urls:
            cleaned_full_url = full_url.rstrip("`\"'")
            if any(ch in cleaned_full_url for ch in ("{", "}", "$", "(", ")")):
                continue
            candidates.append(cleaned_full_url)
    except Exception:
        pass

    # De-duplicate while preserving order.
    seen = set()
    ordered = []
    for item in candidates:
        if item not in seen:
            seen.add(item)
            ordered.append(item)
    return ordered

def connect_stream(stream_url):
    req = urllib.request.Request(stream_url, headers={"User-Agent": "Mozilla/5.0"})
    response = urllib.request.urlopen(req, timeout=NETWORK_TIMEOUT_SECONDS)

    content_type = (response.headers.get("Content-Type") or "").lower()
    initial_buffer = response.read(READ_CHUNK_SIZE * 2)
    if "text/html" in content_type or b"<html" in initial_buffer.lower():
        response.close()
        raise urllib.error.URLError(f"HTML page received instead of stream (content-type={content_type or 'unknown'})")

    return response, initial_buffer


def fetch_capture_frame(capture_url):
    separator = "&" if "?" in capture_url else "?"
    request_url = f"{capture_url}{separator}_cb={int(time.time() * 1000)}"
    req = urllib.request.Request(request_url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=NETWORK_TIMEOUT_SECONDS) as response:
            jpg = response.read()
    except http.client.IncompleteRead as exc:
        # ESP32 can occasionally close early; use received partial bytes when possible.
        jpg = exc.partial

    if not jpg:
        raise urllib.error.URLError("Empty JPEG payload from capture endpoint")

    jpg_array = np.frombuffer(jpg, dtype=np.uint8)
    frame = cv2.imdecode(jpg_array, cv2.IMREAD_COLOR)
    if frame is None:
        raise urllib.error.URLError("Failed to decode JPEG from capture endpoint")
    return frame


def read_mjpeg_frame(stream_response, buffer):
    while True:
        try:
            chunk = stream_response.read(READ_CHUNK_SIZE)
        except (socket.timeout, TimeoutError, urllib.error.URLError,
                http.client.IncompleteRead, ConnectionResetError, OSError):
            return None, buffer

        if not chunk:
            return None, buffer

        buffer += chunk
        start = buffer.find(b"\xff\xd8")
        end = buffer.find(b"\xff\xd9")

        if start != -1 and end != -1 and end > start:
            jpg = buffer[start:end + 2]
            buffer = buffer[end + 2:]
            jpg_array = np.frombuffer(jpg, dtype=np.uint8)
            frame = cv2.imdecode(jpg_array, cv2.IMREAD_COLOR)
            return frame, buffer

        if len(buffer) > 2_000_000:
            # Prevent unbounded memory growth if stream data is malformed.
            buffer = buffer[-200_000:]

stream = None
stream_buffer = b""
consecutive_failures = 0
stream_candidates = build_stream_url_candidates(BASE_CAMERA_URL)
stream_candidate_index = 0
current_endpoint_url = ""
current_endpoint_mode = "mjpeg"
frame_index = 0
person_count = 0  # Current frame detections
unique_person_count = 0  # Total unique persons tracked
stream_status = "CONNECTING"

# Set up fullscreen window
cv2.namedWindow("Detection", cv2.WINDOW_NORMAL)
cv2.resizeWindow("Detection", 1280, 720)
init_attendance_csv(LOG_FILE_PATH)

try:
    while True:
        if stream is None:
            candidate_url = stream_candidates[stream_candidate_index]
            try:
                if "/capture" in candidate_url.lower():
                    current_endpoint_mode = "capture"
                    current_endpoint_url = candidate_url
                    stream = True
                    stream_buffer = b""
                else:
                    current_endpoint_mode = "mjpeg"
                    current_endpoint_url = candidate_url
                    stream, initial_buffer = connect_stream(candidate_url)
                    stream_buffer = initial_buffer
                stream_status = "CONNECTED"
                print(f"Connected to stream endpoint: {candidate_url} [{current_endpoint_mode}]")
                consecutive_failures = 0
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                consecutive_failures += 1
                stream_status = f"RECONNECTING ({consecutive_failures})"
                print(f"Stream unavailable ({consecutive_failures}) [{candidate_url}]: {exc}")
                stream_candidate_index = (stream_candidate_index + 1) % len(stream_candidates)
                if MAX_CONSECUTIVE_FAILURES > 0 and consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                    print("Max failures reached. Exiting stream loop.")
                    break
                time.sleep(UNAVAILABLE_DELAY_SECONDS)
                continue

        try:
            if current_endpoint_mode == "capture":
                frame = fetch_capture_frame(current_endpoint_url)
            else:
                frame, stream_buffer = read_mjpeg_frame(stream, stream_buffer)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            frame = None
            print(f"Stream read error: {exc}")

        if frame is None:
            consecutive_failures += 1
            stream_status = f"RECONNECTING ({consecutive_failures})"
            print(f"Stream read failed ({consecutive_failures}). Reconnecting...")
            stream_candidate_index = (stream_candidate_index + 1) % len(stream_candidates)

            if MAX_CONSECUTIVE_FAILURES > 0 and consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                print("Max failures reached. Exiting stream loop.")
                break

            try:
                if current_endpoint_mode != "capture":
                    stream.close()
            except Exception:
                pass
            stream = None
            stream_buffer = b""
            time.sleep(RETRY_DELAY_SECONDS)
            continue

        consecutive_failures = 0
        stream_status = "CONNECTED"

        if RESIZE_WIDTH > 0 and frame.shape[1] > RESIZE_WIDTH:
            resize_ratio = RESIZE_WIDTH / frame.shape[1]
            frame = cv2.resize(frame, (RESIZE_WIDTH, int(frame.shape[0] * resize_ratio)))

        frame_index += 1
        if frame_index % INFERENCE_EVERY_N_FRAMES == 0:
            # Run detection less frequently to reduce load and improve stream smoothness.
            results = model(frame, verbose=False)
            detections = []
            frame_h, frame_w = frame.shape[:2]
            frame_area = max(1, frame_w * frame_h)

            for r in results:
                for box in r.boxes:
                    if int(box.cls[0]) == 0:  # person class
                        conf = float(box.conf[0])
                        if conf >= CONF_THRESHOLD:  # Only add detections above threshold
                            x1, y1, x2, y2 = map(int, box.xyxy[0])
                            box_w = max(1, x2 - x1)
                            box_h = max(1, y2 - y1)
                            area_ratio = (box_w * box_h) / frame_area
                            if MIN_BOX_AREA_RATIO <= area_ratio <= MAX_BOX_AREA_RATIO:
                                detections.append(([x1, y1, box_w, box_h], conf, 0))

            # Update tracker with detections
            tracks = tracker.update_tracks(detections, frame=frame)
            current_frame_ids.clear()
            new_person_ids.clear()  # Reset new detections for this frame
            person_count = 0

            for track in tracks:
                if track.is_confirmed():
                    track_id = track.track_id

                    ltrb = track.to_ltrb()
                    x1, y1, x2, y2 = map(int, ltrb)
                    cx = (x1 + x2) // 2
                    cy = (y1 + y2) // 2
                    now_ts = time.time()

                    track_hit_counts[track_id] = track_hit_counts.get(track_id, 0) + 1

                    if track_id in track_to_person_id:
                        stable_person_id = track_to_person_id[track_id]
                    elif track_hit_counts[track_id] >= MIN_TRACK_HITS_FOR_COUNT:
                        stable_person_id = find_existing_person_id(cx, cy, now_ts)
                        if stable_person_id is None:
                            # Fallback when DeepSORT track IDs reset because of capture-mode instability.
                            stable_person_id = find_recent_person_fallback_id(cx, cy, now_ts)
                        if stable_person_id is None:
                            stable_person_id = next_person_id
                            next_person_id += 1
                            unique_person_ids.add(stable_person_id)
                            new_person_ids.add(stable_person_id)
                            print(
                                f"[NEW] Person ID {stable_person_id} detected! "
                                f"Total unique: {len(unique_person_ids)}"
                            )
                        track_to_person_id[track_id] = stable_person_id
                    else:
                        stable_person_id = None

                    if stable_person_id is not None:
                        current_frame_ids.add(stable_person_id)
                        person_last_seen[stable_person_id] = (cx, cy, now_ts)
                    
                    # Choose color: red for NEW, green for tracked
                    box_color = (0, 0, 255) if stable_person_id in new_person_ids else (0, 255, 0)
                    
                    # Draw bounding box
                    cv2.rectangle(frame, (x1, y1), (x2, y2), box_color, 2)

                    # Face-focused box (upper body/head area inside person box)
                    box_w = max(1, x2 - x1)
                    box_h = max(1, y2 - y1)
                    fx1 = x1 + int(box_w * 0.2)
                    fx2 = x2 - int(box_w * 0.2)
                    fy1 = y1 + int(box_h * 0.08)
                    fy2 = y1 + int(box_h * 0.42)
                    if fx2 > fx1 and fy2 > fy1:
                        cv2.rectangle(frame, (fx1, fy1), (fx2, fy2), (255, 200, 0), 2)
                    
                    # Draw ID label
                    label = "ID: ..." if stable_person_id is None else f"ID: {stable_person_id}"
                    label_y = max(20, y1 - 8)
                    label_x = max(5, x1)
                    (label_w, label_h), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.48, 1)
                    cv2.rectangle(
                        frame,
                        (label_x, label_y - label_h - 8),
                        (label_x + label_w + 8, label_y + 4),
                        box_color,
                        -1,
                    )
                    cv2.putText(
                        frame,
                        label,
                        (label_x + 4, label_y),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.48,
                        (255, 255, 255),
                        1,
                    )

            unique_person_count = len(unique_person_ids)
            person_count = len(current_frame_ids)

        # Compact translucent HUD (clean, non-overlapping)
        overlay = frame.copy()
        cv2.rectangle(overlay, (10, 10), (335, 100), (20, 20, 20), -1)
        cv2.addWeighted(overlay, 0.55, frame, 0.45, 0, frame)

        cv2.putText(frame, f"Unique: {unique_person_count}", (20, 38),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.82, (0, 255, 255), 2)
        cv2.putText(frame, f"Current: {person_count}", (20, 66),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.72, (0, 255, 0), 2)
        cv2.putText(frame, f"New: {len(new_person_ids)}  {stream_status}", (20, 90),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)

        current_time = time.time()
        if current_time - last_log_time >= LOG_INTERVAL_SECONDS:
            append_attendance_log(LOG_FILE_PATH, unique_person_count)
            last_log_time = current_time
        
        if current_time - last_backend_update_time >= UPDATE_INTERVAL_SECONDS:
            send_count_to_backend(person_count, unique_person_count)
            last_backend_update_time = current_time

        cv2.imshow("Detection", frame)

        if cv2.waitKey(1) == 27:
            break
except KeyboardInterrupt:
    print("Stopped by user (Ctrl+C).")
    try:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
    except Exception:
        pass
finally:
    if stream is not None:
        try:
            stream.close()
        except Exception:
            pass
    try:
        cv2.destroyAllWindows()
    except Exception:
        pass