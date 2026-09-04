import sys
import math
import logging
import time
import ctypes
import csv
import hashlib
import subprocess
import shutil
from bisect import bisect_right
from pathlib import Path

import pywavefront
logging.getLogger("pywavefront").setLevel(logging.ERROR)

from PySide6.QtCore import Qt, QTimer, QElapsedTimer, QPoint, QRect, QSize
from PySide6.QtGui import QPainter, QPen, QBrush, QFont, QPainterPath, QPixmap, QColor
from PySide6.QtWidgets import (
    QApplication,
    QMainWindow,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QPushButton,
    QSlider,
    QProgressBar,
    QLabel,
    QFrame,
    QSizePolicy,
    QStyleFactory,
)
from PySide6.QtOpenGLWidgets import QOpenGLWidget

try:
    from PySide6.QtMultimedia import QMediaPlayer, QAudioOutput
    QT_MULTIMEDIA_AVAILABLE = True
except Exception:
    QMediaPlayer = None
    QAudioOutput = None
    QT_MULTIMEDIA_AVAILABLE = False

from OpenGL import GL, GLU

from rfdr import load_rfdr, MAX_ATTITUDE_RATE


# ============================================================
# PATHS / SETTINGS
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

RFDR_FILE = BASE_DIR / "test.RFDR"
RFDR_CSV_FALLBACK = BASE_DIR / "test.csv"

AIRCRAFT_MODEL_OBJ_PATH = BASE_DIR / "737.obj"
PLANE_ICON_PATH = BASE_DIR / "plane.png"
YOKE_PATH = BASE_DIR / "yoke.png"
YOKE_BLACK_PATH = BASE_DIR / "yoke1.png"

WINDOW_WIDTH = 1280
WINDOW_HEIGHT = 900
UNDERBAR_HEIGHT = 220
PLAYBACK_INTERVAL = 16


# ============================================================
# CVR AUDIO VOLUME
# ============================================================

LOUDEN_CVR_AUDIO = True
CVR_VOLUME_MULTIPLIER = 1.5
CVR_AUDIO_CACHE_DIR = BASE_DIR / "rfdr_audio_cache"

GROUND_LEVEL = 0.0


# ============================================================
# CAMERA
# ============================================================

CAMERA_DISTANCE = 55.0
CAMERA_MIN_DISTANCE = 5.0
CAMERA_MAX_DISTANCE = 2000.0
CAMERA_ELEVATION = 18.0
CAMERA_AZIMUTH = 0.0
CAMERA_MIN_ELEVATION = -85.0
CAMERA_MAX_ELEVATION = 85.0
CAMERA_ROTATE_SENSITIVITY = 0.35
CAMERA_ZOOM_SENSITIVITY = 5.0


# ============================================================
# AIRCRAFT MODEL
#
# IMPORTANT:
#
# The supplied 737.obj is treated as having its nose along LOCAL -Z.
#
# Therefore:
#   RFDR HDG 000 -> model must face world -Z
#   RFDR HDG 090 -> model must face world +X
#   RFDR HDG 180 -> model must face world +Z
#   RFDR HDG 270 -> model must face world -X
#
# For a model whose forward axis is -Z, rotating by -HDG around Y
# produces exactly that mapping.
# ============================================================

AIRCRAFT_MODEL_SCALE = 1.0

# No arbitrary 180-degree heading offset anymore.
AIRCRAFT_MODEL_YAW_OFFSET = 0.0

# RFDR pitch convention:
#   negative = nose UP
#   positive = nose DOWN
AIRCRAFT_MODEL_PITCH_OFFSET = 0.0
AIRCRAFT_MODEL_ROLL_OFFSET = 0.0


# Fine-tune the 737.obj position relative to the RFDR flight path.
AIRCRAFT_MODEL_OFFSET_X = -27.0
AIRCRAFT_MODEL_OFFSET_Y = -12.0
AIRCRAFT_MODEL_OFFSET_Z = -17.0


USE_PROCEDURAL_AIRCRAFT_FALLBACK = True
FORCE_PROCEDURAL_AIRCRAFT = False
PROCEDURAL_AIRCRAFT_SCALE = 1.0

AIRCRAFT_DEBUG_RENDER = True


# ============================================================
# UI CONSTANTS
# ============================================================

YOKE_FOREGROUND_SIZE = (260, 195)
YOKE_BLACK_SIZE = (285, 214)
PLANE_ICON_SIZE = (28, 28)

SPEED_MAX_DISPLAY = 700.0
SPEED_MINOR_TICK = 10
SPEED_MAJOR_TICK = 100

CVR_MAX_LINES = 6


# ============================================================
# YOKE
# ============================================================

YOKE_MAX_X = 90.0
YOKE_MAX_Y = 45.0
YOKE_MIN_DEFLECTION = 0.20
YOKE_ACCELERATION = 300.0
YOKE_DAMPING = 12.0
YOKE_RETURN_ACCELERATION = 420.0
YOKE_RETURN_DAMPING = 14.0

YOKE_PITCH_MAX_RATE = MAX_ATTITUDE_RATE.get("pitch", 30.0)
YOKE_ROLL_MAX_RATE = MAX_ATTITUDE_RATE.get("roll", 45.0)


# ============================================================
# MATH / SAFE DATA HELPERS
# ============================================================

def clamp(value, minimum, maximum):
    return max(minimum, min(maximum, value))


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_angle(a, b, t):
    d = ((b - a + 180.0) % 360.0) - 180.0
    return a + d * t


def get_number(obj, *names, default=0.0):
    for name in names:
        value = getattr(obj, name, None)

        if value is None:
            continue

        try:
            return float(value)
        except (TypeError, ValueError):
            continue

    return float(default)


def get_bool(obj, name):
    return bool(getattr(obj, name, False))


def get_text(obj, name, default=""):
    value = getattr(obj, name, default)
    return default if value is None else str(value)


def normalize_hex_color(value, default="#FFFFFF"):
    value = str(value or "").strip()

    if not value:
        return default

    if not value.startswith("#"):
        value = "#" + value

    if len(value) != 7:
        return default

    try:
        int(value[1:], 16)
    except ValueError:
        return default

    return value.upper()


def qcolor(value, default="#FFFFFF"):
    c = QColor(normalize_hex_color(value, default))
    return c if c.isValid() else QColor(default)


# ============================================================
# BUILDVERSE WORLD AXES
#
# X- = LEFT
# X+ = RIGHT
# Z- = NORTH / 000
# Z+ = SOUTH / 180
# Y  = ALTITUDE
# ============================================================

def frame_position(frame):
    return (
        get_number(frame, "x", default=0.0),
        get_number(frame, "altitude", "y", default=0.0),
        get_number(frame, "z", default=0.0),
    )


def vec_sub(a, b):
    return (
        a[0] - b[0],
        a[1] - b[1],
        a[2] - b[2],
    )


def vec_mul(v, s):
    return (
        v[0] * s,
        v[1] * s,
        v[2] * s,
    )


# ============================================================
# POSITION CALCULATION
#
# If X/Z are recorded:
#     use them exactly.
#
# If X/Z are absent:
#     reconstruct the flight path from SPD + HDG + SEC.
#
# BuildVerse:
#     000 = north = Z-
#     090 = east  = X+
#     180 = south = Z+
#     270 = west  = X-
#
# Therefore:
#     dx = sin(heading) * speed * dt
#     dz = -cos(heading) * speed * dt
# ============================================================

def recording_has_xz(frames):
    if not frames:
        return False

    return all(
        hasattr(f, "x") and hasattr(f, "z")
        for f in frames
    ) and any(
        abs(get_number(f, "x", default=0.0)) > 0.0 or
        abs(get_number(f, "z", default=0.0)) > 0.0
        for f in frames
    )


def calculate_missing_xz(frames, has_recorded_x=None, has_recorded_z=None):
    """
    Build a missing X/Z trajectory using the SAME direction that the
    737.obj uses.

    In this viewer the aircraft model's forward direction is:

        HDG 000 -> +Z
        HDG 090 -> -X
        HDG 180 -> -Z
        HDG 270 -> +X

    This is intentionally the opposite of the original BuildVerse
    world-axis assumption, because it must match the actual 737.obj
    orientation currently used by the viewer.
    """
    if not frames:
        return

    if has_recorded_x is None:
        has_recorded_x = bool(
            getattr(
                frames[0],
                "_recorded_x_present",
                False,
            )
        )

    if has_recorded_z is None:
        has_recorded_z = bool(
            getattr(
                frames[0],
                "_recorded_z_present",
                False,
            )
        )

    if not has_recorded_x:
        frames[0].x = 0.0

    if not has_recorded_z:
        frames[0].z = 0.0

    for i in range(1, len(frames)):
        a = frames[i - 1]
        b = frames[i]

        t0 = get_number(a, "time", default=0.0)
        t1 = get_number(b, "time", default=0.0)

        dt = max(0.0, t1 - t0)

        if dt <= 0.0:
            if not has_recorded_x:
                b.x = a.x

            if not has_recorded_z:
                b.z = a.z

            continue

        speed_a = max(
            0.0,
            get_number(
                a,
                "airspeed",
                "spd",
                default=0.0,
            ),
        )

        speed_b = max(
            0.0,
            get_number(
                b,
                "airspeed",
                "spd",
                default=0.0,
            ),
        )

        speed = (
            speed_a
            + speed_b
        ) * 0.5

        heading_a = get_number(
            a,
            "heading",
            "hdg",
            default=0.0,
        )

        heading_b = get_number(
            b,
            "heading",
            "hdg",
            default=heading_a,
        )

        heading = lerp_angle(
            heading_a,
            heading_b,
            0.5,
        )

        heading_rad = math.radians(
            heading
        )

        # ====================================================
        # MATCH THE ACTUAL 737.OBJ FORWARD DIRECTION
        #
        # 000 -> +Z
        # 090 -> -X
        # 180 -> -Z
        # 270 -> +X
        # ====================================================

        dx = -math.sin(
            heading_rad
        ) * speed * dt

        dz = math.cos(
            heading_rad
        ) * speed * dt

        if not has_recorded_x:
            b.x = a.x + dx

        if not has_recorded_z:
            b.z = a.z + dz

    for f in frames:
        f.y = get_number(
            f,
            "altitude",
            "y",
            default=0.0,
        )

        if has_recorded_x:
            f._recorded_x_present = True

        if has_recorded_z:
            f._recorded_z_present = True


# ============================================================
# OPTIONAL CSV FIELDS
# ============================================================

def attach_optional_csv_fields(source_path, frames):
    """
    Attach optional CSV-only fields that older rfdr.py versions may ignore.

    Supported optional columns:
      CVR_AUDIO / CVR_AUDIO_ACTION / AUDIO
      VSI / VERTICAL_SPEED / VERT_SPEED / VS
    """
    path = Path(source_path)

    if not path.exists() or not frames:
        return

    try:
        with path.open(
            "r",
            encoding="utf-8-sig",
            newline="",
        ) as file:

            reader = csv.DictReader(
                file,
                skipinitialspace=True,
            )

            fields = reader.fieldnames or []

            audio_key = next(
                (
                    k for k in (
                        "CVR_AUDIO",
                        "CVR_AUDIO_ACTION",
                        "AUDIO",
                    )
                    if k in fields
                ),
                None,
            )

            vsi_key = next(
                (
                    k for k in (
                        "VSI",
                        "VERTICAL_SPEED",
                        "VERT_SPEED",
                        "VS",
                    )
                    if k in fields
                ),
                None,
            )

            if audio_key is None and vsi_key is None:
                return

            rows = []

            for row in reader:
                try:
                    t = float(
                        str(
                            row.get("SEC", "0")
                        ).strip() or 0.0
                    )
                except ValueError:
                    continue

                rows.append((t, row))

            if not rows:
                return

            rows.sort(key=lambda x: x[0])

            for frame in frames:
                ft = get_number(
                    frame,
                    "time",
                    default=0.0,
                )

                best = min(
                    rows,
                    key=lambda item:
                    abs(item[0] - ft)
                )

                if abs(best[0] - ft) > 1e-4:
                    continue

                row = best[1]

                if audio_key is not None:
                    frame.cvr_audio = str(
                        row.get(audio_key) or ""
                    ).strip()

                if vsi_key is not None:
                    raw = str(
                        row.get(vsi_key) or ""
                    ).strip()

                    if raw:
                        try:
                            frame.provided_vsi = float(raw)
                        except ValueError:
                            pass

    except (OSError, UnicodeError):
        return


# ============================================================
# SMOOTH CUBIC BEZIER FLIGHT PATH
# ============================================================

def bezier_point(
    p0,
    p1,
    p2,
    p3,
    t,
):
    t = clamp(t, 0.0, 1.0)

    u = 1.0 - t

    b0 = u * u * u
    b1 = 3.0 * u * u * t
    b2 = 3.0 * u * t * t
    b3 = t * t * t

    return (
        b0 * p0[0]
        + b1 * p1[0]
        + b2 * p2[0]
        + b3 * p3[0],

        b0 * p0[1]
        + b1 * p1[1]
        + b2 * p2[1]
        + b3 * p3[1],

        b0 * p0[2]
        + b1 * p1[2]
        + b2 * p2[2]
        + b3 * p3[2],
    )


def bezier_tangent(
    p0,
    p1,
    p2,
    p3,
    t,
):
    t = clamp(t, 0.0, 1.0)

    u = 1.0 - t

    return (
        3.0 * u * u * (p1[0] - p0[0])
        + 6.0 * u * t * (p2[0] - p1[0])
        + 3.0 * t * t * (p3[0] - p2[0]),

        3.0 * u * u * (p1[1] - p0[1])
        + 6.0 * u * t * (p2[1] - p1[1])
        + 3.0 * t * t * (p3[1] - p2[1]),

        3.0 * u * u * (p1[2] - p0[2])
        + 6.0 * u * t * (p2[2] - p1[2])
        + 3.0 * t * t * (p3[2] - p2[2]),
    )


def build_bezier_segments(frames):
    """
    Build one continuous smooth cubic-Bézier spline through
    every RFDR position.
    """

    if len(frames) < 2:
        return []

    points = [
        frame_position(f)
        for f in frames
    ]

    segments = []

    for i in range(len(points) - 1):

        p0 = points[
            max(0, i - 1)
        ]

        p1 = points[i]

        p2 = points[i + 1]

        p3 = points[
            min(
                len(points) - 1,
                i + 2,
            )
        ]

        # ----------------------------------------------------
        # Tangent at first point.
        # ----------------------------------------------------

        tangent1 = (
            (p2[0] - p0[0]) / 6.0,
            (p2[1] - p0[1]) / 6.0,
            (p2[2] - p0[2]) / 6.0,
        )

        # ----------------------------------------------------
        # Tangent at second point.
        # ----------------------------------------------------

        tangent2 = (
            (p3[0] - p1[0]) / 6.0,
            (p3[1] - p1[1]) / 6.0,
            (p3[2] - p1[2]) / 6.0,
        )

        control1 = (
            p1[0] + tangent1[0],
            p1[1] + tangent1[1],
            p1[2] + tangent1[2],
        )

        control2 = (
            p2[0] - tangent2[0],
            p2[1] - tangent2[1],
            p2[2] - tangent2[2],
        )

        segments.append(
            (
                p1,
                control1,
                control2,
                p2,
            )
        )

    return segments
def attitude_rate_at_time(
    frames,
    frame_times,
    playback_time,
    attribute,
):
    if len(frames) < 2:
        return 0.0

    if playback_time <= frame_times[0]:
        a, b = frames[0], frames[1]

    elif playback_time >= frame_times[-1]:
        a, b = frames[-2], frames[-1]

    else:
        right = bisect_right(
            frame_times,
            playback_time,
        )

        i1 = max(0, right - 1)
        i2 = min(
            len(frames) - 1,
            right,
        )

        a = frames[i1]
        b = frames[i2]

    dt = (
        get_number(b, "time")
        - get_number(a, "time")
    )

    if dt <= 0.0:
        return 0.0

    return (
        get_number(b, attribute)
        - get_number(a, attribute)
    ) / dt


# ============================================================
# IMAGE HELPERS
# ============================================================

def load_pixmap(path):
    path = Path(path)

    if not path.exists():
        return None

    pixmap = QPixmap(str(path))

    return None if pixmap.isNull() else pixmap


def display_value(obj, *names, default=0.0):
    return get_number(
        obj,
        *names,
        default=default,
    )


def engine_display_value(frame):
    for name in (
        "engine",
        "eng",
        "engine_value",
        "eng_value",
        "engine_state",
    ):
        value = getattr(
            frame,
            name,
            None,
        )

        if value is None:
            continue

        try:
            return float(value)

        except (TypeError, ValueError):
            text = str(value).strip().upper()
            tail = (
                text.split()[-1]
                if text.split()
                else ""
            )

            try:
                return float(tail)

            except ValueError:
                digits = "".join(
                    ch for ch in tail
                    if ch.isdigit() or ch in ".-"
                )

                try:
                    return float(digits)
                except ValueError:
                    continue

    return 0.0


def power_display_value(frame):
    return display_value(
        frame,
        "power",
        "pwr",
        default=0.0,
    )


# ============================================================
# MECHANICAL INSTRUMENT PANEL
# ============================================================

class InstrumentPanel(QWidget):

    def __init__(self, parent=None):
        super().__init__(parent)

        self.frame = None

        self.plane_icon = load_pixmap(
            PLANE_ICON_PATH
        )

        self.plane_icon_scaled = (
            self.plane_icon.scaled(
                PLANE_ICON_SIZE[0],
                PLANE_ICON_SIZE[1],
                Qt.KeepAspectRatio,
                Qt.SmoothTransformation,
            )
            if self.plane_icon is not None
            else None
        )

        self.setMinimumWidth(410)

        self.setSizePolicy(
            QSizePolicy.Fixed,
            QSizePolicy.Expanding,
        )

        self.setStyleSheet(
            "background:#C0C0C0;color:#000000;"
        )

    def set_frame(self, frame):
        self.frame = frame
        self.update()

    def text_center(
        self,
        painter,
        x,
        y,
        text,
        size=9,
        color=Qt.white,
        bold=True,
    ):
        painter.setPen(QPen(color))

        painter.setFont(
            QFont(
                "Arial",
                size,
                QFont.Bold if bold else QFont.Normal,
            )
        )

        width = (
            painter.fontMetrics()
            .horizontalAdvance(str(text))
        )

        painter.drawText(
            int(x - width / 2),
            int(y),
            str(text),
        )

    def draw_bezel(
        self,
        painter,
        cx,
        cy,
        r,
    ):
        painter.setPen(
            QPen(
                QColor("#808080"),
                3,
            )
        )

        painter.setBrush(
            QBrush(
                QColor("#050505")
            )
        )

        painter.drawEllipse(
            cx - r,
            cy - r,
            2 * r,
            2 * r,
        )

        painter.setPen(
            QPen(
                QColor("#D0D0D0"),
                1,
            )
        )

        painter.drawEllipse(
            cx - r + 5,
            cy - r + 5,
            2 * (r - 5),
            2 * (r - 5),
        )

    def draw_needle(
        self,
        painter,
        cx,
        cy,
        length,
        angle_deg,
        width=3,
    ):
        a = math.radians(angle_deg)

        x = cx + math.cos(a) * length
        y = cy + math.sin(a) * length

        painter.setPen(
            QPen(
                QColor("#FFD900"),
                width,
            )
        )

        painter.drawLine(
            int(cx),
            int(cy),
            int(x),
            int(y),
        )

        painter.setBrush(
            QBrush(
                QColor("#FFD900")
            )
        )

        painter.setPen(
            QPen(
                QColor("#FFD900")
            )
        )

        painter.drawEllipse(
            cx - 4,
            cy - 4,
            8,
            8,
        )

    def draw_speed(
        self,
        painter,
        cx,
        cy,
        r,
        speed,
    ):
        self.draw_bezel(
            painter,
            cx,
            cy,
            r,
        )

        self.text_center(
            painter,
            cx,
            cy + 9,
            "IAS",
            9,
            QColor("#1787FF"),
        )

        self.text_center(
            painter,
            cx,
            cy + 23,
            "SPS",
            9,
            QColor("#1787FF"),
        )

        def angle_for(v):
            return (
                -90.0
                + (v / SPEED_MAX_DISPLAY)
                * 300.0
            )

        painter.setPen(
            QPen(
                QColor("#D8D8D8"),
                1,
            )
        )

        for value in range(
            0,
            701,
            SPEED_MINOR_TICK,
        ):
            a = math.radians(
                angle_for(value)
            )

            outer = r - 7

            inner = r - (
                25
                if value % SPEED_MAJOR_TICK == 0
                else 15
            )

            painter.drawLine(
                int(
                    cx
                    + math.cos(a)
                    * inner
                ),
                int(
                    cy
                    + math.sin(a)
                    * inner
                ),
                int(
                    cx
                    + math.cos(a)
                    * outer
                ),
                int(
                    cy
                    + math.sin(a)
                    * outer
                ),
            )

        for value in range(
            0,
            701,
            SPEED_MAJOR_TICK,
        ):
            a = math.radians(
                angle_for(value)
            )

            rr = r - 41

            self.text_center(
                painter,
                cx + math.cos(a) * rr,
                cy + math.sin(a) * rr + 3,
                value,
                9,
                Qt.white,
            )

        self.text_center(
            painter,
            cx,
            cy - 7,
            f"{speed:.1f}",
            14,
            Qt.white,
        )

        self.draw_needle(
            painter,
            cx,
            cy,
            r - 25,
            angle_for(
                clamp(
                    speed,
                    0.0,
                    SPEED_MAX_DISPLAY,
                )
            ),
            2,
        )

    def draw_altitude(
        self,
        painter,
        cx,
        cy,
        r,
        altitude,
    ):
        self.draw_bezel(
            painter,
            cx,
            cy,
            r,
        )

        self.text_center(
            painter,
            cx,
            cy + 9,
            "ALTITUDE",
            8,
            QColor("#1787FF"),
        )

        self.text_center(
            painter,
            cx,
            cy + 23,
            "STD",
            8,
            QColor("#1787FF"),
        )

        painter.setPen(
            QPen(
                QColor("#D8D8D8"),
                1,
            )
        )

        for value in range(
            0,
            1000,
            10,
        ):
            a = math.radians(
                -90.0
                + (value / 1000.0)
                * 360.0
            )

            outer = r - 7
            inner = r - (
                22
                if value % 100 == 0
                else 14
            )

            painter.drawLine(
                int(
                    cx
                    + math.cos(a)
                    * inner
                ),
                int(
                    cy
                    + math.sin(a)
                    * inner
                ),
                int(
                    cx
                    + math.cos(a)
                    * outer
                ),
                int(
                    cy
                    + math.sin(a)
                    * outer
                ),
            )

        for digit in range(10):
            a = math.radians(
                -90.0
                + digit * 36.0
            )

            rr = r - 41

            self.text_center(
                painter,
                cx + math.cos(a) * rr,
                cy + math.sin(a) * rr + 3,
                digit,
                10,
                Qt.white,
            )

        self.text_center(
            painter,
            cx,
            cy - 7,
            f"{altitude:.1f}",
            14,
            Qt.white,
        )

        hundreds_position = (
            float(altitude) / 100.0
        ) % 10.0

        angle = (
            -90.0
            + hundreds_position * 36.0
        )

        self.draw_needle(
            painter,
            cx,
            cy,
            r - 25,
            angle,
            2,
        )

    def draw_heading(
        self,
        painter,
        cx,
        cy,
        r,
        heading,
    ):
        self.draw_bezel(
            painter,
            cx,
            cy,
            r,
        )

        heading %= 360.0

        painter.setPen(
            QPen(
                QColor("#D8D8D8"),
                1,
            )
        )

        for value in range(
            0,
            360,
            5,
        ):
            a = math.radians(
                value
                - heading
                - 90.0
            )

            outer = r - 7

            inner = r - (
                22
                if value % 30 == 0
                else 14
                if value % 10 == 0
                else 10
            )

            painter.drawLine(
                int(
                    cx
                    + math.cos(a)
                    * inner
                ),
                int(
                    cy
                    + math.sin(a)
                    * inner
                ),
                int(
                    cx
                    + math.cos(a)
                    * outer
                ),
                int(
                    cy
                    + math.sin(a)
                    * outer
                ),
            )

        for value in range(
            0,
            360,
            30,
        ):
            a = math.radians(
                value
                - heading
                - 90.0
            )

            rr = r - 36

            self.text_center(
                painter,
                cx + math.cos(a) * rr,
                cy + math.sin(a) * rr + 3,
                f"{value:03d}",
                7,
                Qt.white,
            )

        for text, value in (
            [("N", 0), ("E", 90),
             ("S", 180), ("W", 270)]
        ):
            a = math.radians(
                value
                - heading
                - 90.0
            )

            rr = r - 22

            self.text_center(
                painter,
                cx + math.cos(a) * rr,
                cy + math.sin(a) * rr + 3,
                text,
                9,
                Qt.white,
            )

        self.text_center(
            painter,
            cx,
            cy - r + 30,
            f"{heading:03.0f}°",
            9,
            QColor("#00FF40"),
        )

        if self.plane_icon_scaled is not None:
            p = self.plane_icon_scaled

            painter.drawPixmap(
                cx - p.width() // 2,
                cy - p.height() // 2,
                p,
            )

        else:
            painter.setPen(
                QPen(
                    Qt.white,
                    2,
                )
            )

            painter.drawLine(
                cx,
                cy - 16,
                cx,
                cy + 16,
            )

            painter.drawLine(
                cx - 22,
                cy,
                cx + 22,
                cy,
            )

    def draw_adi(
        self,
        painter,
        cx,
        cy,
        r,
        pitch,
        roll,
    ):
        painter.save()

        clip = QPainterPath()

        clip.addEllipse(
            cx - r,
            cy - r,
            2 * r,
            2 * r,
        )

        painter.setClipPath(clip)

        painter.translate(
            cx,
            cy,
        )

        painter.rotate(-roll)

        pitch_pixels = -pitch * 3.0

        painter.setPen(Qt.NoPen)

        painter.setBrush(
            QBrush(
                QColor("#4B8FB1")
            )
        )

        painter.drawRect(
            -r * 3,
            -r * 3,
            r * 6,
            r * 3 + int(pitch_pixels),
        )

        painter.setBrush(
            QBrush(
                QColor("#9B7136")
            )
        )

        painter.drawRect(
            -r * 3,
            int(pitch_pixels),
            r * 6,
            r * 3,
        )

        painter.setPen(
            QPen(
                Qt.white,
                2,
            )
        )

        painter.drawLine(
            -r * 3,
            int(pitch_pixels),
            r * 3,
            int(pitch_pixels),
        )

        painter.setFont(
            QFont(
                "Arial",
                8,
            )
        )

        for p in range(
            -40,
            41,
            5,
        ):
            if p == 0:
                continue

            y = (
                -p * 3.0
                + pitch_pixels
            )

            half = (
                52
                if p % 10 == 0
                else 32
            )

            painter.drawLine(
                -half,
                int(y),
                half,
                int(y),
            )

            painter.drawText(
                -half - 27,
                int(y + 3),
                str(abs(p)),
            )

            painter.drawText(
                half + 8,
                int(y + 3),
                str(abs(p)),
            )

        painter.restore()

        painter.save()

        painter.setPen(
            QPen(
                Qt.white,
                2,
            )
        )

        for a_deg in range(
            -60,
            61,
            10,
        ):
            a = math.radians(a_deg)

            inner = r + 5

            outer = (
                r + 23
                if a_deg % 30 == 0
                else r + 17
            )

            painter.drawLine(
                int(
                    cx
                    + math.sin(a)
                    * inner
                ),
                int(
                    cy
                    - math.cos(a)
                    * inner
                ),
                int(
                    cx
                    + math.sin(a)
                    * outer
                ),
                int(
                    cy
                    - math.cos(a)
                    * outer
                ),
            )

        from PySide6.QtGui import QPolygonF
        from PySide6.QtCore import QPointF

        painter.setBrush(
            QBrush(Qt.white)
        )

        painter.setPen(
            QPen(
                Qt.white,
                1,
            )
        )

        boundary_r = r + 14

        painter.drawPolygon(
            QPolygonF([
                QPointF(
                    cx - 8,
                    cy - boundary_r - 1,
                ),
                QPointF(
                    cx + 8,
                    cy - boundary_r - 1,
                ),
                QPointF(
                    cx,
                    cy - boundary_r + 9,
                ),
            ])
        )

        roll_angle = clamp(
            -roll,
            -60.0,
            60.0,
        )

        a = math.radians(
            roll_angle
        )

        ring_r = r - 1.0

        px = (
            cx
            + math.sin(a)
            * ring_r
        )

        py = (
            cy
            - math.cos(a)
            * ring_r
        )

        painter.save()

        painter.translate(
            px,
            py,
        )

        painter.rotate(
            roll_angle
        )

        painter.drawPolygon(
            QPolygonF([
                QPointF(-8, 8),
                QPointF(8, 8),
                QPointF(0, -9),
            ])
        )

        painter.restore()

        painter.setPen(
            QPen(
                QColor("#FFD900"),
                4,
            )
        )

        painter.drawLine(
            cx - 48,
            cy,
            cx - 12,
            cy,
        )

        painter.drawLine(
            cx + 12,
            cy,
            cx + 48,
            cy,
        )

        painter.drawLine(
            cx - 12,
            cy,
            cx,
            cy + 8,
        )

        painter.drawLine(
            cx + 12,
            cy,
            cx,
            cy + 8,
        )

        painter.restore()

    def paintEvent(self, event):
        painter = QPainter(self)

        painter.setRenderHint(
            QPainter.Antialiasing
        )

        painter.fillRect(
            self.rect(),
            QColor("#C0C0C0"),
        )

        painter.setPen(
            QPen(
                QColor("#808080"),
                2,
            )
        )

        painter.drawRect(
            1,
            1,
            self.width() - 2,
            self.height() - 2,
        )

        painter.setPen(
            QPen(
                QColor("#FFFFFF"),
                1,
            )
        )

        painter.drawLine(
            2,
            2,
            self.width() - 3,
            2,
        )

        title_font = QFont(
            "MS Sans Serif",
            9,
            QFont.Bold,
        )

        painter.setFont(title_font)

        painter.setPen(
            QPen(Qt.black)
        )

        painter.drawText(
            10,
            16,
            "FLIGHT INSTRUMENTS",
        )

        if self.frame is None:
            return

        w = self.width()
        h = self.height()
        cx = w // 2

        top_margin = 42
        bottom_margin = 14

        usable = max(
            360,
            h - top_margin - bottom_margin,
        )

        slot = usable / 3.0

        gauge_r = int(
            max(
                82,
                min(104, slot * 0.34),
            )
        )

        centers = [
            int(
                top_margin
                + slot * 0.43
            ),
            int(
                top_margin
                + slot * 1.43
            ),
            int(
                top_margin
                + slot * 2.55
            ),
        ]

        self.draw_speed(
            painter,
            cx,
            centers[0],
            gauge_r,
            get_number(
                self.frame,
                "airspeed",
                "spd",
            ),
        )

        self.draw_altitude(
            painter,
            cx,
            centers[1],
            gauge_r,
            get_number(
                self.frame,
                "altitude",
                "alt",
            ),
        )

        self.draw_adi(
            painter,
            cx,
            centers[2],
            min(gauge_r, 104),
            get_number(
                self.frame,
                "pitch",
                "pch",
            ),
            get_number(
                self.frame,
                "roll",
                "rll",
            ),
        )


# ============================================================
# BOTTOM-RIGHT HEADING INDICATOR
# ============================================================

def raw_rfdr_heading(frame):
    if frame is None:
        return 0.0

    value = getattr(
        frame,
        "heading",
        None,
    )

    if value is None:
        value = getattr(
            frame,
            "hdg",
            0.0,
        )

    try:
        return float(value) % 360.0
    except (TypeError, ValueError):
        return 0.0


class HeadingPanel(QWidget):

    def __init__(self, parent=None):
        super().__init__(parent)

        self.frame = None

        self.plane_icon = load_pixmap(
            PLANE_ICON_PATH
        )

        self.plane_icon_scaled = (
            self.plane_icon.scaled(
                24,
                24,
                Qt.KeepAspectRatio,
                Qt.SmoothTransformation,
            )
            if self.plane_icon is not None
            else None
        )

        self.setMinimumWidth(235)
        self.setMinimumHeight(180)

        self.setSizePolicy(
            QSizePolicy.Expanding,
            QSizePolicy.Fixed,
        )

        self.setStyleSheet(
            "background:#C0C0C0;"
            "color:#000000;"
            "border:2px solid #808080;"
        )

    def set_frame(self, frame):
        self.frame = frame
        self.update()

    def text_center(
        self,
        painter,
        x,
        y,
        text,
        size=9,
        color=Qt.white,
        bold=True,
    ):
        painter.setPen(QPen(color))

        painter.setFont(
            QFont(
                "Arial",
                size,
                QFont.Bold if bold else QFont.Normal,
            )
        )

        text = str(text)

        width = (
            painter.fontMetrics()
            .horizontalAdvance(text)
        )

        painter.drawText(
            int(x - width / 2),
            int(y),
            text,
        )

    def draw_heading(
        self,
        painter,
        cx,
        cy,
        r,
        heading,
    ):
        painter.setPen(
            QPen(
                QColor("#808080"),
                3,
            )
        )

        painter.setBrush(
            QBrush(
                QColor("#050505")
            )
        )

        painter.drawEllipse(
            cx - r,
            cy - r,
            2 * r,
            2 * r,
        )

        painter.setPen(
            QPen(
                QColor("#D0D0D0"),
                1,
            )
        )

        painter.drawEllipse(
            cx - r + 5,
            cy - r + 5,
            2 * (r - 5),
            2 * (r - 5),
        )

        heading %= 360.0

        painter.setPen(
            QPen(
                QColor("#D8D8D8"),
                1,
            )
        )

        for value in range(
            0,
            360,
            5,
        ):
            a = math.radians(
                value
                - heading
                - 90.0
            )

            outer = r - 7

            inner = (
                r - 22
                if value % 30 == 0
                else r - 14
                if value % 10 == 0
                else r - 10
            )

            painter.drawLine(
                int(
                    cx
                    + math.cos(a)
                    * inner
                ),
                int(
                    cy
                    + math.sin(a)
                    * inner
                ),
                int(
                    cx
                    + math.cos(a)
                    * outer
                ),
                int(
                    cy
                    + math.sin(a)
                    * outer
                ),
            )

        for value in range(
            0,
            360,
            30,
        ):
            a = math.radians(
                value
                - heading
                - 90.0
            )

            rr = r - 35

            self.text_center(
                painter,
                cx + math.cos(a) * rr,
                cy + math.sin(a) * rr + 3,
                f"{value:03d}",
                9,
                Qt.white,
            )

        for text, value in (
            [("N", 0), ("E", 90),
             ("S", 180), ("W", 270)]
        ):
            a = math.radians(
                value
                - heading
                - 90.0
            )

            rr = r - 21

            self.text_center(
                painter,
                cx + math.cos(a) * rr,
                cy + math.sin(a) * rr + 3,
                text,
                10,
                Qt.white,
            )

        self.text_center(
            painter,
            cx,
            cy + r - 48,
            f"{heading:03.0f}°",
            9,
            QColor("#00FF40"),
        )

        if self.plane_icon_scaled is not None:
            p = self.plane_icon_scaled

            painter.drawPixmap(
                int(cx - p.width() / 2),
                int(
                    cy
                    + r
                    + 8
                    - p.height() / 2
                ),
                p,
            )

        else:
            painter.setPen(
                QPen(
                    Qt.white,
                    2,
                )
            )

            painter.drawLine(
                cx,
                cy - 15,
                cx,
                cy + 15,
            )

            painter.drawLine(
                cx - 22,
                cy,
                cx + 22,
                cy,
            )

    def paintEvent(self, event):
        painter = QPainter(self)

        painter.setRenderHint(
            QPainter.Antialiasing
        )

        painter.fillRect(
            self.rect(),
            QColor("#C0C0C0"),
        )

        painter.setPen(
            QPen(
                QColor("#808080"),
                2,
            )
        )

        painter.drawRect(
            1,
            1,
            self.width() - 2,
            self.height() - 2,
        )

        if self.frame is not None:
            r = min(
                82,
                (self.height() - 8) // 2,
            )

            self.draw_heading(
                painter,
                self.width() // 2,
                self.height() // 2 + 4,
                r,
                raw_rfdr_heading(
                    self.frame
                ),
            )


# ============================================================
# YOKE
# ============================================================

class YokeWidget(QWidget):

    def __init__(self, parent=None):
        super().__init__(parent)

        self.setMinimumHeight(200)

        self.setSizePolicy(
            QSizePolicy.Expanding,
            QSizePolicy.Fixed,
        )

        fg = load_pixmap(
            YOKE_PATH
        )

        bg = load_pixmap(
            YOKE_BLACK_PATH
        )

        self.yoke = (
            fg.scaled(
                255,
                191,
                Qt.KeepAspectRatio,
                Qt.SmoothTransformation,
            )
            if fg
            else None
        )

        self.yoke_black = (
            bg.scaled(
                275,
                206,
                Qt.KeepAspectRatio,
                Qt.SmoothTransformation,
            )
            if bg
            else None
        )

        self.target_x = 0.0
        self.target_y = 0.0

        self.current_x = 0.0
        self.current_y = 0.0

        self.vx = 0.0
        self.vy = 0.0

        self.W = False
        self.A = False
        self.S = False
        self.D = False

        self.setStyleSheet(
            "background:#C0C0C0;"
            "border:1px solid #808080;"
        )

    def reset(self):
        self.target_x = 0.0
        self.target_y = 0.0

        self.current_x = 0.0
        self.current_y = 0.0

        self.vx = 0.0
        self.vy = 0.0

        self.W = False
        self.A = False
        self.S = False
        self.D = False

        self.update()

    def deflection_from_rate(
        self,
        rate,
        maximum_rate,
        maximum,
    ):
        return (
            max(
                YOKE_MIN_DEFLECTION,
                clamp(
                    abs(rate)
                    / max(
                        0.001,
                        maximum_rate,
                    ),
                    0.0,
                    1.0,
                ),
            )
            * maximum
        )

    def set_recorded_input(
        self,
        W,
        A,
        S,
        D,
        pitch_rate,
        roll_rate,
    ):
        self.W = bool(W)
        self.A = bool(A)
        self.S = bool(S)
        self.D = bool(D)

        if self.S and not self.W:
            self.target_y = self.deflection_from_rate(
                pitch_rate,
                YOKE_PITCH_MAX_RATE,
                YOKE_MAX_Y,
            )

        elif self.W and not self.S:
            self.target_y = (
                -self.deflection_from_rate(
                    pitch_rate,
                    YOKE_PITCH_MAX_RATE,
                    YOKE_MAX_Y,
                )
            )

        else:
            self.target_y = 0.0

        if self.D and not self.A:
            self.target_x = self.deflection_from_rate(
                roll_rate,
                YOKE_ROLL_MAX_RATE,
                YOKE_MAX_X,
            )

        elif self.A and not self.D:
            self.target_x = (
                -self.deflection_from_rate(
                    roll_rate,
                    YOKE_ROLL_MAX_RATE,
                    YOKE_MAX_X,
                )
            )

        else:
            self.target_x = 0.0

    def update_motion(self, dt):
        dt = clamp(
            float(dt),
            0.0,
            0.1,
        )

        ex = (
            self.target_x
            - self.current_x
        )

        ey = (
            self.target_y
            - self.current_y
        )

        ax = (
            YOKE_ACCELERATION
            if abs(self.target_x) > 0.001
            else YOKE_RETURN_ACCELERATION
        )

        ay = (
            YOKE_ACCELERATION
            if abs(self.target_y) > 0.001
            else YOKE_RETURN_ACCELERATION
        )

        dx = (
            YOKE_DAMPING
            if abs(self.target_x) > 0.001
            else YOKE_RETURN_DAMPING
        )

        dy = (
            YOKE_DAMPING
            if abs(self.target_y) > 0.001
            else YOKE_RETURN_DAMPING
        )

        self.vx = (
            self.vx
            + ex * ax * dt
        ) * math.exp(-dx * dt)

        self.vy = (
            self.vy
            + ey * ay * dt
        ) * math.exp(-dy * dt)

        self.current_x = clamp(
            self.current_x
            + self.vx * dt,
            -YOKE_MAX_X,
            YOKE_MAX_X,
        )

        self.current_y = clamp(
            self.current_y
            + self.vy * dt,
            -YOKE_MAX_Y,
            YOKE_MAX_Y,
        )

        self.update()

    def draw_pixmap(
        self,
        painter,
        pixmap,
        cx,
        cy,
        ox,
        oy,
        rotation,
    ):
        if pixmap is None:
            return

        painter.save()

        painter.translate(
            cx + ox,
            cy + oy,
        )

        painter.rotate(rotation)

        painter.drawPixmap(
            -pixmap.width() // 2,
            -pixmap.height() // 2,
            pixmap,
        )

        painter.restore()

    def paintEvent(self, event):
        painter = QPainter(self)

        painter.setRenderHint(
            QPainter.Antialiasing
        )

        painter.fillRect(
            self.rect(),
            QColor("#C0C0C0"),
        )

        cx = self.width() // 2
        cy = self.height() // 2 + 4

        self.draw_pixmap(
            painter,
            self.yoke_black,
            cx,
            cy,
            0,
            0,
            0.0,
        )

        rotation = clamp(
            (
                self.current_x
                / max(
                    1.0,
                    YOKE_MAX_X,
                )
            )
            * 28.0,
            -28.0,
            28.0,
        )

        self.draw_pixmap(
            painter,
            self.yoke,
            cx,
            cy,
            self.current_x,
            self.current_y,
            rotation,
        )

        if self.yoke_black is None:
            painter.setPen(
                QPen(
                    Qt.black,
                    1,
                )
            )

            painter.setBrush(
                QBrush(Qt.black)
            )

            painter.drawRoundedRect(
                cx - 105,
                cy - 45,
                210,
                90,
                18,
                18,
            )

        if self.yoke is None:
            painter.setPen(
                QPen(
                    QColor("#DDDDDD"),
                    6,
                )
            )

            painter.drawLine(
                cx - 75
                + int(self.current_x),
                cy
                + int(self.current_y),
                cx + 75
                + int(self.current_x),
                cy
                + int(self.current_y),
            )

        painter.setPen(
            QPen(Qt.white)
        )

        painter.setFont(
            QFont(
                "MS Sans Serif",
                8,
                QFont.Bold,
            )
        )

        painter.drawText(
            9,
            16,
            "YOKE",
        )

        state = (
            f'W {"ON" if self.W else "--"}   '
            f'A {"ON" if self.A else "--"}   '
            f'S {"ON" if self.S else "--"}   '
            f'D {"ON" if self.D else "--"}'
        )

        painter.drawText(
            9,
            self.height() - 7,
            state,
        )


# ============================================================
# ENGINE STATUS
# ============================================================

class EngineStatusWidget(QWidget):

    def __init__(self, parent=None):
        super().__init__(parent)

        self.engine_on = False

        self.setFixedWidth(82)
        self.setFixedHeight(
            UNDERBAR_HEIGHT
        )

        self.setStyleSheet(
            "background:#C0C0C0;"
            "border:1px solid #808080;"
        )

    def set_engine(self, value):
        try:
            numeric = float(value)

        except (TypeError, ValueError):
            text = str(
                value or ""
            ).strip().upper()

            tail = (
                text.split()[-1]
                if text.split()
                else ""
            )

            try:
                numeric = float(tail)

            except ValueError:
                numeric = 0.0

        self.engine_on = (
            numeric >= 0.5
        )

        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)

        painter.fillRect(
            self.rect(),
            QColor("#C0C0C0"),
        )

        painter.setPen(
            QPen(Qt.black)
        )

        painter.setFont(
            QFont(
                "MS Sans Serif",
                8,
                QFont.Bold,
            )
        )

        painter.drawText(
            6,
            18,
            "ENGINE",
        )

        box_w = self.width() - 12
        box_h = 62

        state_color = (
            "#00A000"
            if self.engine_on
            else "#D00000"
        )

        for y, label in (
            (28, "ENG 1"),
            (100, "ENG 0"),
        ):
            painter.setPen(
                QPen(
                    Qt.black,
                    1,
                )
            )

            painter.setBrush(
                QBrush(
                    QColor(state_color)
                )
            )

            painter.drawRect(
                6,
                y,
                box_w,
                box_h,
            )

            painter.setPen(
                QPen(Qt.white)
            )

            painter.drawText(
                6,
                y,
                box_w,
                box_h,
                Qt.AlignCenter,
                label,
            )


# ============================================================
# EVENT / CVR PANEL
# ============================================================

def vertical_speed_display_value(frame):
    calculated = (
        get_number(
            frame,
            "vertical_speed",
            default=0.0,
        )
        * 60.0
    )

    supplied = getattr(
        frame,
        "provided_vsi",
        None,
    )

    if supplied is None:
        return calculated

    supplied_display = (
        float(supplied)
        * 1000.0
    )

    tolerance = max(
        150.0,
        abs(calculated) * 0.20,
    )

    return (
        supplied_display
        if abs(
            supplied_display
            - calculated
        ) <= tolerance
        else calculated
    )


def lateral_movement_value(frame):
    if frame is None:
        return 0.0

    return float(
        get_number(
            frame,
            "velocity_x",
            default=0.0,
        )
    )


class EventCVRPanel(QWidget):

    VSI_SCALE = [
        (0.0, 180.0),
        (0.5, 150.0),
        (1.0, 112.5),
        (2.0, 75.0),
        (4.0, 37.5),
        (6.0, 0.0),
        (4.0, -37.5),
        (2.0, -75.0),
        (1.0, -112.5),
        (0.5, -150.0),
    ]

    def __init__(
        self,
        recording=None,
        parent=None,
    ):
        super().__init__(parent)

        self.recording = recording
        self.frame_index = 0

        self.event_text = ""
        self.event_color = "#000000"

        self.frame = None

        self.vsi = 0.0
        self.lateral = 0.0

        self.setFixedHeight(
            UNDERBAR_HEIGHT
        )

        self.setSizePolicy(
            QSizePolicy.Expanding,
            QSizePolicy.Fixed,
        )

        self.setStyleSheet(
            "background:#C0C0C0;"
            "color:#000000;"
            "border:2px solid #808080;"
        )

    def set_recording(self, recording):
        self.recording = recording

    def update_frame(
        self,
        index,
        frame=None,
    ):
        self.frame_index = max(
            0,
            index,
        )

        frames = (
            getattr(
                self.recording,
                "frames",
                [],
            )
            if self.recording
            else []
        )

        if not frames:
            self.event_text = ""
            self.event_color = "#000000"
            self.frame = frame

            self.vsi = (
                vertical_speed_display_value(
                    frame
                )
                if frame is not None
                else 0.0
            )

            self.lateral = (
                lateral_movement_value(
                    frame
                )
                if frame is not None
                else 0.0
            )

            self.update()
            return

        i = min(
            self.frame_index,
            len(frames) - 1,
        )

        source = (
            frame
            if frame is not None
            else frames[i]
        )

        self.frame = source

        self.event_text = get_text(
            frames[i],
            "event",
        ).strip()

        self.event_color = normalize_hex_color(
            get_text(
                frames[i],
                "event_color",
                "#000000",
            ),
            "#000000",
        )

        self.vsi = (
            vertical_speed_display_value(
                source
            )
        )

        self.lateral = (
            lateral_movement_value(
                source
            )
        )

        self.update()

    def text_center(
        self,
        painter,
        x,
        y,
        text,
        size=8,
        color=Qt.white,
        bold=True,
    ):
        painter.setPen(
            QPen(color)
        )

        painter.setFont(
            QFont(
                "MS Sans Serif",
                size,
                QFont.Bold
                if bold
                else QFont.Normal,
            )
        )

        text = str(text)

        painter.drawText(
            int(
                x
                - painter.fontMetrics()
                .horizontalAdvance(text)
                / 2
            ),
            int(y),
            text,
        )

    def draw_vsi(
        self,
        painter,
        cx,
        cy,
        r,
        vertical_speed,
    ):
        painter.setPen(
            QPen(
                QColor("#808080"),
                3,
            )
        )

        painter.setBrush(
            QBrush(
                QColor("#050505")
            )
        )

        painter.drawEllipse(
            cx - r,
            cy - r,
            2 * r,
            2 * r,
        )

        painter.setPen(
            QPen(
                QColor("#D0D0D0"),
                1,
            )
        )

        painter.drawEllipse(
            cx - r + 5,
            cy - r + 5,
            2 * (r - 5),
            2 * (r - 5),
        )

        painter.setPen(
            QPen(
                QColor("#D8D8D8"),
                1,
            )
        )

        for value, angle_deg in self.VSI_SCALE:
            a = math.radians(
                angle_deg
            )

            outer = r - 7

            inner = r - (
                31
                if value in (
                    0.0,
                    2.0,
                    4.0,
                    6.0,
                )
                else 20
            )

            painter.drawLine(
                int(
                    cx
                    + math.cos(a)
                    * inner
                ),
                int(
                    cy
                    + math.sin(a)
                    * inner
                ),
                int(
                    cx
                    + math.cos(a)
                    * outer
                ),
                int(
                    cy
                    + math.sin(a)
                    * outer
                ),
            )

            rr = r - 34

            self.text_center(
                painter,
                cx
                + math.cos(a)
                * rr,
                cy
                + math.sin(a)
                * rr
                + 3,
                f"{value:g}",
                8,
                Qt.white,
            )

        scaled = clamp(
            vertical_speed / 1000.0,
            -6.0,
            6.0,
        )

        if scaled >= 0.0:
            points = [
                (0.0, 180.0),
                (0.5, 150.0),
                (1.0, 112.5),
                (2.0, 75.0),
                (4.0, 37.5),
                (6.0, 0.0),
            ]

            if scaled <= 0.5:
                p0, p1 = points[0], points[1]
            elif scaled <= 1.0:
                p0, p1 = points[1], points[2]
            elif scaled <= 2.0:
                p0, p1 = points[2], points[3]
            elif scaled <= 4.0:
                p0, p1 = points[3], points[4]
            else:
                p0, p1 = points[4], points[5]

        else:
            magnitude = -scaled

            points = [
                (0.0, 180.0),
                (0.5, -150.0),
                (1.0, -112.5),
                (2.0, -75.0),
                (4.0, -37.5),
                (6.0, 0.0),
            ]

            if magnitude <= 0.5:
                p0, p1 = points[0], points[1]
            elif magnitude <= 1.0:
                p0, p1 = points[1], points[2]
            elif magnitude <= 2.0:
                p0, p1 = points[2], points[3]
            elif magnitude <= 4.0:
                p0, p1 = points[3], points[4]
            else:
                p0, p1 = points[4], points[5]

            scaled = magnitude

        angle_deg = (
            p0[1]
            + (
                (scaled - p0[0])
                / max(
                    1e-9,
                    p1[0] - p0[0],
                )
            )
            * (
                p1[1] - p0[1]
            )
        )

        a = math.radians(
            angle_deg
        )

        tip_r = r - 25

        tip_x = int(
            cx
            + math.cos(a)
            * tip_r
        )

        tip_y = int(
            cy
            + math.sin(a)
            * tip_r
        )

        painter.setPen(
            QPen(
                QColor("#FFD900"),
                3,
            )
        )

        painter.drawLine(
            cx,
            cy,
            tip_x,
            tip_y,
        )

        painter.setBrush(
            QBrush(
                QColor("#FFD900")
            )
        )

        painter.setPen(
            QPen(
                QColor("#FFD900")
            )
        )

        painter.drawEllipse(
            cx - 4,
            cy - 4,
            8,
            8,
        )

        self.text_center(
            painter,
            cx,
            cy + 23,
            f"{vertical_speed:+.0f}",
            8,
            QColor("#FFD900"),
        )

    def draw_lateral(
        self,
        painter,
        x,
        y,
        w,
        h,
        lateral,
    ):
        painter.setPen(
            QPen(
                QColor("#FFFFFF"),
                2,
            )
        )

        painter.setBrush(
            QBrush(
                QColor("#000000")
            )
        )

        painter.drawRect(
            int(x),
            int(y),
            int(w),
            int(h),
        )

        inner_x = x + 7
        inner_y = y + 8

        inner_w = max(
            30,
            w - 14,
        )

        inner_h = max(
            14,
            h - 16,
        )

        painter.setPen(
            QPen(
                Qt.black,
                1,
            )
        )

        painter.setBrush(
            QBrush(Qt.black)
        )

        painter.drawRect(
            int(inner_x),
            int(inner_y),
            int(inner_w),
            int(inner_h),
        )

        center = (
            inner_x
            + inner_w * 0.5
        )

        max_speed = max(
            1.0,
            float(
                getattr(
                    self,
                    "lateral_scale",
                    50.0,
                )
            ),
        )

        ratio = clamp(
            float(lateral)
            / max_speed,
            -1.0,
            1.0,
        )

        travel = max(
            2.0,
            inner_w * 0.5 - 7.0,
        )

        pos = (
            center
            + ratio * travel
        )

        painter.setPen(
            QPen(
                QColor("#FFFFFF"),
                1,
            )
        )

        painter.drawLine(
            int(center),
            int(inner_y - 3),
            int(center),
            int(inner_y + inner_h + 3),
        )

        painter.setPen(
            QPen(
                QColor("#FF0000"),
                1,
            )
        )

        painter.setBrush(
            QBrush(
                QColor("#FF0000")
            )
        )

        painter.drawRect(
            int(pos - 5),
            int(inner_y - 5),
            10,
            int(inner_h + 10),
        )

        painter.setPen(
            QPen(Qt.black)
        )

        painter.setFont(
            QFont(
                "MS Sans Serif",
                7,
                QFont.Bold,
            )
        )

        painter.drawText(
            int(x),
            int(y + h + 14),
            "LEFT",
        )

        painter.drawText(
            int(x + w - 36),
            int(y + h + 14),
            "RIGHT",
        )

        self.text_center(
            painter,
            center,
            y + h + 14,
            "0",
            7,
            Qt.black,
        )

        self.text_center(
            painter,
            center,
            y - 5,
            f"{lateral:+.1f} STD/S",
            7,
            Qt.black,
        )

    def paintEvent(self, event):
        painter = QPainter(self)

        painter.fillRect(
            self.rect(),
            QColor("#C0C0C0"),
        )

        painter.setRenderHint(
            QPainter.Antialiasing
        )

        painter.setPen(
            QPen(
                QColor("#FFFFFF"),
                1,
            )
        )

        painter.drawLine(
            1,
            1,
            self.width() - 2,
            1,
        )

        painter.drawLine(
            1,
            1,
            1,
            self.height() - 2,
        )

        painter.setPen(
            QPen(
                QColor("#808080"),
                2,
            )
        )

        painter.drawLine(
            self.width() - 2,
            1,
            self.width() - 2,
            self.height() - 2,
        )

        painter.drawLine(
            1,
            self.height() - 2,
            self.width() - 2,
            self.height() - 2,
        )

        painter.setPen(
            QPen(Qt.black)
        )

        painter.setFont(
            QFont(
                "MS Sans Serif",
                9,
                QFont.Bold,
            )
        )

        painter.drawText(
            10,
            22,
            "EVENT",
        )

        painter.setPen(
            QPen(
                qcolor(
                    self.event_color,
                    "#000000",
                )
            )
        )

        painter.setFont(
            QFont(
                "MS Sans Serif",
                10,
                QFont.Bold,
            )
        )

        event_rect = QRect(
            70,
            7,
            max(
                100,
                int(
                    self.width() * 0.30
                ) - 70,
            ),
            55,
        )

        painter.drawText(
            event_rect,
            Qt.TextWordWrap,
            self.event_text,
        )

        available_left = int(
            self.width() * 0.28
        )

        gauge_space = max(
            300,
            self.width()
            - available_left
            - 8,
        )

        vsi_cx = (
            available_left
            + int(
                gauge_space * 0.25
            )
        )

        vsi_cy = (
            self.height() // 2
            + 8
        )

        vsi_r = min(
            94,
            max(
                72,
                int(
                    min(
                        gauge_space * 0.17,
                        (
                            self.height()
                            - 20
                        )
                        * 0.47,
                    )
                ),
            ),
        )

        self.draw_vsi(
            painter,
            vsi_cx,
            vsi_cy,
            vsi_r,
            self.vsi,
        )

        slider_x = (
            available_left
            + int(
                gauge_space * 0.46
            )
        )

        slider_w = max(
            180,
            int(
                gauge_space * 0.40
            ),
        )

        slider_y = (
            self.height() // 2
            - 14
        )

        self.draw_lateral(
            painter,
            slider_x,
            slider_y,
            slider_w,
            46,
            self.lateral,
        )

        painter.setPen(
            QPen(Qt.black)
        )

        painter.setFont(
            QFont(
                "MS Sans Serif",
                8,
                QFont.Bold,
            )
        )

        painter.drawText(
            slider_x,
            slider_y - 28,
            "LATERAL MOVEMENT",
        )


# ============================================================
# OPENGL AIRCRAFT MODEL
# ============================================================

class AircraftModel:

    def __init__(self, obj_path):
        self.obj_path = Path(obj_path)

        self.scene = None
        self.display_list = None

        self.center = (
            0.0,
            0.0,
            0.0,
        )

        self.scale = 1.0
        self.loaded = False

        self.material_count = 0
        self.renderable_material_count = 0
        self.vertex_count = 0

        self.bounds = None
        self.load_error = ""

    @staticmethod
    def _layout(vertex_format):
        sizes = {
            "T2F": 2,
            "C3F": 3,
            "C4F": 4,
            "N3F": 3,
            "V3F": 3,
        }

        out = []

        for token in (
            vertex_format or ""
        ).split("_"):
            if token in sizes:
                out.append(
                    (
                        token,
                        sizes[token],
                    )
                )

        return out

    def load(self):
        if self.loaded:
            print(
                "RFDR OBJ DEBUG: "
                f"load() called again; "
                f"already loaded="
                f"{self.scene is not None}"
            )

            return

        self.loaded = True

        print(
            "RFDR OBJ DEBUG: "
            "--------------------------------------------------"
        )

        print(
            f"RFDR OBJ DEBUG: "
            f"path = {self.obj_path}"
        )

        print(
            f"RFDR OBJ DEBUG: "
            f"exists = {self.obj_path.exists()}"
        )

        if not self.obj_path.exists():
            self.load_error = (
                "OBJ file does not exist"
            )

            print(
                "RFDR OBJ DEBUG: ERROR: "
                f"{self.load_error}"
            )

            return

        try:
            print(
                "RFDR OBJ DEBUG: "
                f"size = {self.obj_path.stat().st_size} bytes"
            )

        except OSError as exc:
            print(
                "RFDR OBJ DEBUG: "
                f"could not stat OBJ: {exc}"
            )

        try:
            self.scene = pywavefront.Wavefront(
                str(self.obj_path),
                create_materials=True,
                collect_faces=False,
                parse=True,
                cache=True,
            )

            print(
                "RFDR OBJ DEBUG: "
                "Wavefront parse completed"
            )

        except Exception as exc:
            self.load_error = (
                "Wavefront parse failed: "
                f"{exc!r}"
            )

            print(
                "RFDR OBJ DEBUG: ERROR: "
                f"{self.load_error}"
            )

            self.scene = None
            return

        materials = list(
            getattr(
                self.scene,
                "materials",
                {},
            ).values()
        )

        self.material_count = len(
            materials
        )

        print(
            "RFDR OBJ DEBUG: "
            f"materials = {self.material_count}"
        )

        if not materials:
            self.load_error = (
                "OBJ parsed but has zero materials"
            )

            print(
                "RFDR OBJ DEBUG: ERROR: "
                f"{self.load_error}"
            )

            self.scene = None
            return

        positions = []

        for mi, material in enumerate(materials):
            fmt = (
                getattr(
                    material,
                    "vertex_format",
                    "",
                )
                or ""
            )

            vertices = (
                getattr(
                    material,
                    "vertices",
                    None,
                )
                or []
            )

            vertex_size = int(
                getattr(
                    material,
                    "vertex_size",
                    0,
                )
                or 0
            )

            print(
                "RFDR OBJ DEBUG: "
                f"material[{mi}] "
                f"name={getattr(material, 'name', '<unnamed>')!r} "
                f"format={fmt!r} "
                f"floats={len(vertices)} "
                f"vertex_size={vertex_size} "
                f"diffuse={getattr(material, 'diffuse', None)!r}"
            )

            layout = self._layout(fmt)

            stride = sum(
                size
                for _, size in layout
            )

            v3_offset = None
            offset = 0

            for token, size in layout:
                if token == "V3F":
                    v3_offset = offset
                    break

                offset += size

            if (
                not vertices
                or stride <= 0
                or v3_offset is None
            ):
                print(
                    "RFDR OBJ DEBUG: "
                    f"material[{mi}] "
                    "SKIP: no usable V3F layout"
                )

                continue

            count = (
                len(vertices)
                // stride
            )

            self.vertex_count += count
            self.renderable_material_count += 1

            for base in range(count):
                j = (
                    base * stride
                    + v3_offset
                )

                positions.append(
                    (
                        float(vertices[j]),
                        float(vertices[j + 1]),
                        float(vertices[j + 2]),
                    )
                )

            print(
                "RFDR OBJ DEBUG: "
                f"material[{mi}] "
                f"usable triangle vertices={count}"
            )

        if not positions:
            self.load_error = (
                "No usable V3F positions found "
                "in any material"
            )

            print(
                "RFDR OBJ DEBUG: ERROR: "
                f"{self.load_error}"
            )

            self.scene = None
            return

        min_x = min(
            v[0]
            for v in positions
        )

        max_x = max(
            v[0]
            for v in positions
        )

        min_y = min(
            v[1]
            for v in positions
        )

        max_y = max(
            v[1]
            for v in positions
        )

        min_z = min(
            v[2]
            for v in positions
        )

        max_z = max(
            v[2]
            for v in positions
        )

        self.bounds = (
            min_x,
            max_x,
            min_y,
            max_y,
            min_z,
            max_z,
        )

        self.center = (
            (min_x + max_x) * 0.5,
            (min_y + max_y) * 0.5,
            (min_z + max_z) * 0.5,
        )

        extent = max(
            max_x - min_x,
            max_y - min_y,
            max_z - min_z,
        )

        self.scale = (
            18.0 / extent
            if extent > 0.0
            else 1.0
        )

        print(
            "RFDR OBJ DEBUG: "
            f"renderable materials = "
            f"{self.renderable_material_count}/"
            f"{self.material_count}"
        )

        print(
            "RFDR OBJ DEBUG: "
            f"triangle vertices = "
            f"{self.vertex_count}"
        )

        print(
            "RFDR OBJ DEBUG: "
            f"bounds = {self.bounds}"
        )

        print(
            "RFDR OBJ DEBUG: "
            f"center = {self.center}"
        )

        print(
            "RFDR OBJ DEBUG: "
            f"normalization scale = {self.scale}"
        )

        print(
            "RFDR: loaded 737.obj successfully"
        )

        print(
            "RFDR OBJ DEBUG: "
            "--------------------------------------------------"
        )

    def build_display_list(self):
        if (
            self.scene is None
            or self.display_list is not None
        ):
            return

        print(
            "RFDR OBJ DEBUG: "
            "building OpenGL display list..."
        )

        list_id = GL.glGenLists(1)

        if not list_id:
            print(
                "RFDR OBJ DEBUG: ERROR: "
                "glGenLists returned 0"
            )

            return

        GL.glNewList(
            list_id,
            GL.GL_COMPILE,
        )

        old_lighting = GL.glIsEnabled(
            GL.GL_LIGHTING
        )

        old_cull = GL.glIsEnabled(
            GL.GL_CULL_FACE
        )

        try:
            GL.glDisable(
                GL.GL_LIGHTING
            )

            GL.glDisable(
                GL.GL_CULL_FACE
            )

            GL.glColor3f(
                0.86,
                0.86,
                0.88,
            )

            for mi, material in enumerate(
                self.scene.materials.values()
            ):
                fmt = (
                    getattr(
                        material,
                        "vertex_format",
                        "",
                    )
                    or ""
                )

                vertices = (
                    getattr(
                        material,
                        "vertices",
                        None,
                    )
                    or []
                )

                layout = self._layout(fmt)

                stride = sum(
                    size
                    for _, size in layout
                )

                if (
                    not vertices
                    or stride <= 0
                ):
                    continue

                diffuse = getattr(
                    material,
                    "diffuse",
                    None,
                )

                if (
                    diffuse
                    and len(diffuse) >= 3
                ):
                    GL.glColor3f(
                        float(diffuse[0]),
                        float(diffuse[1]),
                        float(diffuse[2]),
                    )

                else:
                    GL.glColor3f(
                        0.86,
                        0.86,
                        0.88,
                    )

                print(
                    "RFDR OBJ DEBUG: "
                    f"emitting material[{mi}] "
                    f"format={fmt!r} "
                    f"vertices="
                    f"{len(vertices) // stride}"
                )

                GL.glBegin(
                    GL.GL_TRIANGLES
                )

                for base in range(
                    0,
                    len(vertices)
                    - stride
                    + 1,
                    stride,
                ):
                    offset = base

                    position = None
                    normal = None
                    color = None

                    for token, size in layout:
                        data = vertices[
                            offset:
                            offset + size
                        ]

                        offset += size

                        if token == "V3F":
                            position = data

                        elif token == "N3F":
                            normal = data

                        elif token in (
                            "C3F",
                            "C4F",
                        ):
                            color = data

                    if (
                        color is not None
                        and len(color) >= 3
                    ):
                        GL.glColor3f(
                            float(color[0]),
                            float(color[1]),
                            float(color[2]),
                        )

                    if (
                        normal is not None
                        and len(normal) >= 3
                    ):
                        GL.glNormal3f(
                            float(normal[0]),
                            float(normal[1]),
                            float(normal[2]),
                        )

                    if (
                        position is not None
                        and len(position) >= 3
                    ):
                        GL.glVertex3f(
                            float(position[0]),
                            float(position[1]),
                            float(position[2]),
                        )

                GL.glEnd()

            err = GL.glGetError()

            if err != GL.GL_NO_ERROR:
                print(
                    "RFDR OBJ DEBUG: "
                    "OpenGL error while "
                    f"compiling list: "
                    f"0x{int(err):04X}"
                )

        except Exception as exc:
            print(
                "RFDR OBJ DEBUG: "
                "ERROR while emitting display list: "
                f"{exc!r}"
            )

            self.display_list = None

            GL.glEndList()

            GL.glDeleteLists(
                list_id,
                1,
            )

            return

        finally:
            if old_cull:
                GL.glEnable(
                    GL.GL_CULL_FACE
                )

            if old_lighting:
                GL.glEnable(
                    GL.GL_LIGHTING
                )

        GL.glEndList()

        self.display_list = list_id

        err = GL.glGetError()

        if err != GL.GL_NO_ERROR:
            print(
                "RFDR OBJ DEBUG: "
                "OpenGL error after "
                f"display-list build: "
                f"0x{int(err):04X}"
            )

        else:
            print(
                "RFDR OBJ DEBUG: "
                f"display list "
                f"{self.display_list} "
                "built successfully"
            )

    def draw(self):
        if self.scene is None:
            return False

        if self.display_list is None:
            self.build_display_list()

        if self.display_list is None:
            return False

        GL.glPushMatrix()

        GL.glTranslatef(
            -self.center[0],
            -self.center[1],
            -self.center[2],
        )

        final_scale = (
            self.scale
            * AIRCRAFT_MODEL_SCALE
        )

        GL.glScalef(
            final_scale,
            final_scale,
            final_scale,
        )

        GL.glCallList(
            self.display_list
        )

        err = GL.glGetError()

        if err != GL.GL_NO_ERROR:
            print(
                "RFDR OBJ DEBUG: "
                f"OpenGL draw error: "
                f"0x{int(err):04X}"
            )

        GL.glPopMatrix()

        return True


# ============================================================
# OPENGL CHASE VIEW
# ============================================================

class ChaseView(QOpenGLWidget):

    def __init__(self, parent=None):
        super().__init__(parent)

        self.frames = []
        self.current_frame = None
        self.bezier_segments = []

        self.camera_distance = (
            CAMERA_DISTANCE
        )

        self.camera_azimuth = (
            CAMERA_AZIMUTH
        )

        self.camera_elevation = (
            CAMERA_ELEVATION
        )

        self.dragging = False
        self.last_mouse = QPoint()

        self.aircraft = AircraftModel(
            AIRCRAFT_MODEL_OBJ_PATH
        )

        self.model_status = ""
        self.static_path_points = []

        self._effect_clock = (
            time.monotonic()
        )

        self._effect_event_key = None

        self._effect_event_start_clock = (
            self._effect_clock
        )

        self._effect_timer = QTimer(self)

        self._effect_timer.setInterval(
            33
        )

        self._effect_timer.timeout.connect(
            self._tick_event_effects
        )

        self._effect_timer.start()

        self.static_drop_lines = []

        self.times = []

        self.path_list = None
        self.drop_list = None

        self.setMinimumSize(
            600,
            420,
        )

        self.setFocusPolicy(
            Qt.StrongFocus
        )

    def set_frames(self, frames):
        self.frames = list(frames)

        self.current_frame = (
            self.frames[0]
            if self.frames
            else None
        )

        self.times = [
            get_number(
                f,
                "time",
            )
            for f in self.frames
        ]

        self.bezier_segments = (
            build_bezier_segments(
                self.frames
            )
        )

        self.static_path_points = []
        self.static_drop_lines = []

        self.path_list = None
        self.drop_list = None

    def set_frame(self, frame):
        self.current_frame = frame

        self._refresh_event_effect_clock(
            frame
        )

        self.update()

    def _refresh_event_effect_clock(
        self,
        frame,
    ):
        now = time.monotonic()

        event_text = (
            get_text(
                frame,
                "event",
            ).strip().upper()
            if frame is not None
            else ""
        )

        event_start = (
            self._current_event_start_time(
                frame
            )
            if frame is not None
            and event_text
            else None
        )

        key = (
            event_text,
            event_start,
        )

        if key != self._effect_event_key:
            self._effect_event_key = key

            self._effect_event_start_clock = (
                now
            )

        self._effect_clock = now

    def _tick_event_effects(self):
        if self.current_frame is not None:
            self._effect_clock = (
                time.monotonic()
            )

            self.update()

    def initializeGL(self):
        GL.glClearColor(
            0.35,
            0.62,
            0.88,
            1.0,
        )

        GL.glEnable(
            GL.GL_DEPTH_TEST
        )

        GL.glEnable(
            GL.GL_CULL_FACE
        )

        GL.glCullFace(
            GL.GL_BACK
        )

        GL.glEnable(
            GL.GL_LIGHTING
        )

        GL.glEnable(
            GL.GL_LIGHT0
        )

        GL.glEnable(
            GL.GL_COLOR_MATERIAL
        )

        GL.glColorMaterial(
            GL.GL_FRONT_AND_BACK,
            GL.GL_AMBIENT_AND_DIFFUSE,
        )

        GL.glLightfv(
            GL.GL_LIGHT0,
            GL.GL_POSITION,
            [
                50.0,
                100.0,
                50.0,
                1.0,
            ],
        )

        GL.glLightfv(
            GL.GL_LIGHT0,
            GL.GL_AMBIENT,
            [
                0.35,
                0.35,
                0.35,
                1.0,
            ],
        )

        GL.glLightfv(
            GL.GL_LIGHT0,
            GL.GL_DIFFUSE,
            [
                0.9,
                0.9,
                0.9,
                1.0,
            ],
        )

        self.aircraft.load()

        if self.aircraft.scene is None:
            self.model_status = (
                "737.obj NOT LOADED: "
                f"{self.aircraft.load_error}"
            )

        else:
            self.aircraft.build_display_list()

            if self.aircraft.display_list:
                self.model_status = (
                    "737.obj READY: "
                    f"{self.aircraft.vertex_count:,} "
                    "triangle vertices"
                )

            else:
                self.model_status = (
                    "737.obj loaded but "
                    "OpenGL display-list "
                    "build failed."
                )

        self.build_static_path()

    def resizeGL(
        self,
        width,
        height,
    ):
        height = max(
            1,
            height,
        )

        GL.glViewport(
            0,
            0,
            width,
            height,
        )

        GL.glMatrixMode(
            GL.GL_PROJECTION
        )

        GL.glLoadIdentity()

        GLU.gluPerspective(
            60.0,
            width / float(height),
            0.1,
            100000.0,
        )

        GL.glMatrixMode(
            GL.GL_MODELVIEW
        )

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.dragging = True

            self.last_mouse = (
                event.position().toPoint()
            )

            self.setFocus()

            event.accept()
            return

        super().mousePressEvent(
            event
        )

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.dragging = False

            event.accept()
            return

        super().mouseReleaseEvent(
            event
        )

    def mouseMoveEvent(self, event):
        if self.dragging:
            p = (
                event.position()
                .toPoint()
            )

            d = (
                p
                - self.last_mouse
            )

            self.last_mouse = p

            self.camera_azimuth += (
                d.x()
                * CAMERA_ROTATE_SENSITIVITY
            )

            self.camera_elevation = clamp(
                self.camera_elevation
                - d.y()
                * CAMERA_ROTATE_SENSITIVITY,
                CAMERA_MIN_ELEVATION,
                CAMERA_MAX_ELEVATION,
            )

            self.update()

            event.accept()
            return

        super().mouseMoveEvent(
            event
        )

    def wheelEvent(self, event):
        self.camera_distance = clamp(
            self.camera_distance
            - (
                event.angleDelta().y()
                / 120.0
            )
            * CAMERA_ZOOM_SENSITIVITY,
            CAMERA_MIN_DISTANCE,
            CAMERA_MAX_DISTANCE,
        )

        self.update()

        event.accept()

    def build_static_path(self):
        if len(self.frames) < 2:
            self.static_path_points = []
            self.static_drop_lines = []

            self.path_list = None
            self.drop_list = None

            return

        sample_step = max(
            1,
            len(self.frames) // 2500,
        )

        self.static_path_points = [
            frame_position(
                self.frames[i]
            )
            for i in range(
                0,
                len(self.frames),
                sample_step,
            )
        ]

        if (
            self.static_path_points[-1]
            != frame_position(
                self.frames[-1]
            )
        ):
            self.static_path_points.append(
                frame_position(
                    self.frames[-1]
                )
            )

        self.static_drop_lines = []

        for x, y, z in (
            self.static_path_points
        ):
            if abs(
                y - GROUND_LEVEL
            ) > 1.0:
                self.static_drop_lines.append(
                    (
                        x,
                        y,
                        z,
                        x,
                        GROUND_LEVEL,
                        z,
                    )
                )

        self.path_list = GL.glGenLists(1)

        GL.glNewList(
            self.path_list,
            GL.GL_COMPILE,
        )

        GL.glBegin(
            GL.GL_LINE_STRIP
        )

        for x, y, z in (
            self.static_path_points
        ):
            GL.glVertex3f(
                x,
                y,
                z,
            )

        GL.glEnd()

        GL.glEndList()

        self.drop_list = GL.glGenLists(1)

        GL.glNewList(
            self.drop_list,
            GL.GL_COMPILE,
        )

        GL.glBegin(
            GL.GL_LINES
        )

        for (
            x1,
            y1,
            z1,
            x2,
            y2,
            z2,
        ) in self.static_drop_lines:

            GL.glVertex3f(
                x1,
                y1,
                z1,
            )

            GL.glVertex3f(
                x2,
                y2,
                z2,
            )

        GL.glEnd()

        GL.glEndList()

    def interpolated_position(
        self,
        playback_time,
    ):
        if not self.frames:
            return (
                0.0,
                0.0,
                0.0,
            )

        if len(self.frames) == 1:
            return frame_position(
                self.frames[0]
            )

        if playback_time <= self.times[0]:
            return frame_position(
                self.frames[0]
            )

        if playback_time >= self.times[-1]:
            return frame_position(
                self.frames[-1]
            )

        right = bisect_right(
            self.times,
            playback_time,
        )

        index = max(
            0,
            min(
                right - 1,
                len(self.bezier_segments) - 1,
            ),
        )

        t0 = self.times[index]
        t1 = self.times[index + 1]

        if t1 <= t0:
            t = 0.0
        else:
            t = (
                playback_time - t0
            ) / (
                t1 - t0
            )

        p0, p1, p2, p3 = (
            self.bezier_segments[index]
        )

        return bezier_point(
            p0,
            p1,
            p2,
            p3,
            t,
        )

    def set_camera(self, frame):
        playback_time = get_number(
            frame,
            "time",
            default=0.0,
        )

        x, y, z = self.interpolated_position(
            playback_time
        )

        az = math.radians(
            self.camera_azimuth
        )

        el = math.radians(
            self.camera_elevation
        )

        horizontal = (
            self.camera_distance
            * math.cos(el)
        )

        render_x = x

        eye_x = (
            render_x
            + math.sin(az)
            * horizontal
        )

        eye_y = (
            y
            + math.sin(el)
            * self.camera_distance
        )

        eye_z = (
            z
            + math.cos(az)
            * horizontal
        )

        GLU.gluLookAt(
            eye_x,
            eye_y,
            eye_z,
            render_x,
            y,
            z,
            0.0,
            1.0,
            0.0,
        )
        
    def draw_grid(self, frame):
        x, _, z = frame_position(
            frame
        )

        spacing = 100.0
        count = 40
        size = count * spacing

        render_x = x

        ox = (
            math.floor(
                render_x / spacing
            )
            * spacing
        )

        oz = (
            math.floor(
                z / spacing
            )
            * spacing
        )

        GL.glDisable(
            GL.GL_LIGHTING
        )

        GL.glColor3f(
            0.055,
            0.22,
            0.08,
        )

        GL.glBegin(
            GL.GL_QUADS
        )

        GL.glVertex3f(
            ox - size,
            GROUND_LEVEL - 0.05,
            oz - size,
        )

        GL.glVertex3f(
            ox + size,
            GROUND_LEVEL - 0.05,
            oz - size,
        )

        GL.glVertex3f(
            ox + size,
            GROUND_LEVEL - 0.05,
            oz + size,
        )

        GL.glVertex3f(
            ox - size,
            GROUND_LEVEL - 0.05,
            oz + size,
        )

        GL.glEnd()

        GL.glColor3f(
            0.12,
            0.55,
            0.18,
        )

        GL.glBegin(
            GL.GL_LINES
        )

        for i in range(
            -count,
            count + 1,
        ):
            p = i * spacing

            GL.glVertex3f(
                ox + p,
                GROUND_LEVEL,
                oz - size,
            )

            GL.glVertex3f(
                ox + p,
                GROUND_LEVEL,
                oz + size,
            )

            GL.glVertex3f(
                ox - size,
                GROUND_LEVEL,
                oz + p,
            )

            GL.glVertex3f(
                ox + size,
                GROUND_LEVEL,
                oz + p,
            )

        GL.glEnd()

        GL.glEnable(
            GL.GL_LIGHTING
        )

    def draw_paths(self):
        if not self.static_path_points:
            return

        GL.glDisable(
            GL.GL_LIGHTING
        )

        GL.glLineWidth(2.0)

        if self.path_list is not None:
            GL.glColor3f(
                1.0,
                0.85,
                0.0,
            )

            GL.glCallList(
                self.path_list
            )

        if self.drop_list is not None:
            GL.glColor3f(
                0.72,
                0.58,
                0.0,
            )

            GL.glCallList(
                self.drop_list
            )

        GL.glEnable(
            GL.GL_LIGHTING
        )

        GL.glLineWidth(1.0)

    def draw_aircraft(self, frame):
        playback_time = get_number(
            frame,
            "time",
            default=0.0,
        )

        x, y, z = self.interpolated_position(
            playback_time
        )

        if (
            FORCE_PROCEDURAL_AIRCRAFT
            and USE_PROCEDURAL_AIRCRAFT_FALLBACK
        ):
            self.draw_procedural_aircraft(
                frame
            )

            return

        # ====================================================
        # REAL 737.OBJ
        #
        # The OBJ's nose is LOCAL -Z.
        #
        # Therefore yaw = -HDG.
        #
        # Examples:
        #
        # HDG 000:
        #     local -Z -> world -Z
        #
        # HDG 090:
        #     local -Z -> world +X
        #
        # HDG 180:
        #     local -Z -> world +Z
        #
        # HDG 270:
        #     local -Z -> world -X
        #
        # This now matches the calculated RFDR trajectory exactly.
        # ====================================================

        if self.aircraft.display_list is not None:
            GL.glPushMatrix()

            GL.glTranslatef(
                x,
                y,
                z,
            )

            heading = raw_rfdr_heading(
                frame
            )

            pitch = get_number(
                frame,
                "pitch",
                "pch",
                default=0.0,
            )

            roll = get_number(
                frame,
                "roll",
                "rll",
                default=0.0,
            )

            # OBJ forward = local -Z.
            GL.glRotatef(
                -heading
                + AIRCRAFT_MODEL_YAW_OFFSET,
                0.0,
                1.0,
                0.0,
            )

            # RFDR:
            # negative = nose UP
            # positive = nose DOWN
            GL.glRotatef(
                pitch
                + AIRCRAFT_MODEL_PITCH_OFFSET,
                1.0,
                0.0,
                0.0,
            )

            GL.glRotatef(
                roll
                + AIRCRAFT_MODEL_ROLL_OFFSET,
                0.0,
                0.0,
                1.0,
            )

            # Local model-pivot correction.
            GL.glTranslatef(
                AIRCRAFT_MODEL_OFFSET_X,
                AIRCRAFT_MODEL_OFFSET_Y,
                AIRCRAFT_MODEL_OFFSET_Z,
            )

            GL.glColor3f(
                0.90,
                0.90,
                0.90,
            )

            if self.aircraft.draw():
                GL.glPopMatrix()
                return

            GL.glPopMatrix()

        if USE_PROCEDURAL_AIRCRAFT_FALLBACK:
            self.draw_procedural_aircraft(
                frame
            )

        else:
            GL.glPushMatrix()

            GL.glTranslatef(
                x,
                y,
                z,
            )

            GL.glDisable(
                GL.GL_LIGHTING
            )

            GL.glColor3f(
                1.0,
                0.25,
                0.1,
            )

            GL.glLineWidth(3.0)

            GL.glBegin(
                GL.GL_LINES
            )

            GL.glVertex3f(
                -4,
                0,
                -8,
            )

            GL.glVertex3f(
                4,
                0,
                8,
            )

            GL.glVertex3f(
                -10,
                0,
                0,
            )

            GL.glVertex3f(
                10,
                0,
                0,
            )

            GL.glEnd()

            GL.glLineWidth(1.0)

            GL.glEnable(
                GL.GL_LIGHTING
            )

            GL.glPopMatrix()

    def draw_procedural_aircraft(
        self,
        frame,
    ):
        """
        Procedural fallback.

        Unlike 737.obj, this fallback's nose is LOCAL +Z.

        Therefore its correct yaw is +HDG.
        """

        x, y, z = frame_position(
            frame
        )

        scale = (
            PROCEDURAL_AIRCRAFT_SCALE
        )

        def box(
            minx,
            maxx,
            miny,
            maxy,
            minz,
            maxz,
            color,
        ):
            GL.glColor3f(
                *color
            )

            v = [
                (
                    minx,
                    miny,
                    minz,
                ),
                (
                    maxx,
                    miny,
                    minz,
                ),
                (
                    maxx,
                    maxy,
                    minz,
                ),
                (
                    minx,
                    maxy,
                    minz,
                ),
                (
                    minx,
                    miny,
                    maxz,
                ),
                (
                    maxx,
                    miny,
                    maxz,
                ),
                (
                    maxx,
                    maxy,
                    maxz,
                ),
                (
                    minx,
                    maxy,
                    maxz,
                ),
            ]

            faces = [
                (0, 1, 2, 3),
                (4, 7, 6, 5),
                (0, 4, 5, 1),
                (3, 2, 6, 7),
                (1, 5, 6, 2),
                (0, 3, 7, 4),
            ]

            GL.glBegin(
                GL.GL_QUADS
            )

            for a, b, c, d in faces:
                GL.glVertex3fv(
                    v[a]
                )

                GL.glVertex3fv(
                    v[b]
                )

                GL.glVertex3fv(
                    v[c]
                )

                GL.glVertex3fv(
                    v[d]
                )

            GL.glEnd()

        def prism(
            points,
            color,
        ):
            GL.glColor3f(
                *color
            )

            GL.glBegin(
                GL.GL_TRIANGLES
            )

            for i in range(
                1,
                len(points) - 1,
            ):
                GL.glVertex3fv(
                    points[0]
                )

                GL.glVertex3fv(
                    points[i]
                )

                GL.glVertex3fv(
                    points[i + 1]
                )

            GL.glEnd()

        GL.glPushMatrix()

        GL.glTranslatef(
            x,
            y,
            z,
        )

        heading = raw_rfdr_heading(
            frame
        )

        pitch = get_number(
            frame,
            "pitch",
            "pch",
            default=0.0,
        )

        roll = get_number(
            frame,
            "roll",
            "rll",
            default=0.0,
        )

        # Procedural model nose = local +Z.
        # Therefore +HDG gives the correct BuildVerse compass direction.
        GL.glRotatef(
            heading
            + AIRCRAFT_MODEL_YAW_OFFSET,
            0,
            1,
            0,
        )

        GL.glRotatef(
            pitch
            + AIRCRAFT_MODEL_PITCH_OFFSET,
            1,
            0,
            0,
        )

        GL.glRotatef(
            roll
            + AIRCRAFT_MODEL_ROLL_OFFSET,
            0,
            0,
            1,
        )

        GL.glScalef(
            scale,
            scale,
            scale,
        )

        GL.glDisable(
            GL.GL_CULL_FACE
        )

        GL.glEnable(
            GL.GL_LIGHTING
        )

        # Fuselage.
        box(
            -1.35,
            1.35,
            -1.15,
            1.15,
            -6.5,
            6.0,
            (
                0.82,
                0.84,
                0.88,
            ),
        )

        # Nose/cockpit upper block.
        box(
            -1.15,
            1.15,
            -0.85,
            0.95,
            5.4,
            7.0,
            (
                0.78,
                0.80,
                0.84,
            ),
        )

        # Cockpit windows.
        box(
            -0.95,
            -0.10,
            0.50,
            1.02,
            6.55,
            6.95,
            (
                0.02,
                0.02,
                0.025,
            ),
        )

        box(
            0.10,
            0.95,
            0.50,
            1.02,
            6.55,
            6.95,
            (
                0.02,
                0.02,
                0.025,
            ),
        )

        # Main wings.
        left = [
            (
                -1.15,
                0.0,
                2.8,
            ),
            (
                -8.4,
                0.0,
                0.7,
            ),
            (
                -7.5,
                0.0,
                2.2,
            ),
            (
                -1.15,
                0.0,
                4.1,
            ),
        ]

        right = [
            (
                -p[0],
                p[1],
                p[2],
            )
            for p in left
        ]

        prism(
            left,
            (
                0.74,
                0.76,
                0.80,
            ),
        )

        prism(
            right,
            (
                0.74,
                0.76,
                0.80,
            ),
        )

        # Tail fin.
        fin = [
            (
                -0.10,
                0.0,
                -4.7,
            ),
            (
                0.10,
                0.0,
                -4.7,
            ),
            (
                0.10,
                4.0,
                -5.8,
            ),
            (
                -0.10,
                2.2,
                -1.8,
            ),
        ]

        prism(
            fin,
            (
                0.72,
                0.74,
                0.78,
            ),
        )

        # Horizontal stabilizers.
        stab_l = [
            (
                -0.75,
                0.3,
                -4.2,
            ),
            (
                -4.0,
                0.3,
                -5.4,
            ),
            (
                -3.6,
                0.3,
                -4.1,
            ),
            (
                -0.75,
                0.3,
                -3.7,
            ),
        ]

        stab_r = [
            (
                -p[0],
                p[1],
                p[2],
            )
            for p in stab_l
        ]

        prism(
            stab_l,
            (
                0.72,
                0.74,
                0.78,
            ),
        )

        prism(
            stab_r,
            (
                0.72,
                0.74,
                0.78,
            ),
        )

        # Engines.
        for ex in (
            -3.7,
            3.7,
        ):
            GL.glColor3f(
                0.28,
                0.29,
                0.31,
            )

            quad = GLU.gluNewQuadric()

            GL.glPushMatrix()

            GL.glTranslatef(
                ex,
                -1.05,
                1.0,
            )

            GL.glRotatef(
                90,
                1,
                0,
                0,
            )

            GLU.gluCylinder(
                quad,
                0.75,
                0.72,
                2.6,
                16,
                4,
            )

            GLU.gluDisk(
                quad,
                0.0,
                0.75,
                16,
                1,
            )

            GL.glTranslatef(
                0,
                0,
                2.6,
            )

            GLU.gluDisk(
                quad,
                0.0,
                0.72,
                16,
                1,
            )

            GL.glPopMatrix()

            GLU.gluDeleteQuadric(
                quad
            )

        GL.glEnable(
            GL.GL_CULL_FACE
        )

        GL.glPopMatrix()

    def _current_event_start_time(
        self,
        frame,
    ):
        if frame is None:
            return 0.0

        frames = self.frames

        if not frames:
            return get_number(
                frame,
                "time",
            )

        try:
            index = min(
                range(len(frames)),
                key=lambda i:
                abs(
                    get_number(
                        frames[i],
                        "time",
                    )
                    - get_number(
                        frame,
                        "time",
                    )
                ),
            )

        except ValueError:
            return get_number(
                frame,
                "time",
            )

        current_text = (
            get_text(
                frames[index],
                "event",
            )
            .strip()
            .upper()
        )

        start = get_number(
            frames[index],
            "time",
        )

        i = index - 1

        while (
            i >= 0
            and
            get_text(
                frames[i],
                "event",
            )
            .strip()
            .upper()
            == current_text
        ):
            start = get_number(
                frames[i],
                "time",
            )

            i -= 1

        return start

    def draw_event_effects(
        self,
        frame,
    ):
        if frame is None:
            return

        event = (
            get_text(
                frame,
                "event",
            )
            .strip()
            .upper()
        )

        if not event:
            return

        self._refresh_event_effect_clock(
            frame
        )

        age = max(
            0.0,
            time.monotonic()
            - self._effect_event_start_clock,
        )

        px, py, pz = frame_position(
            frame
        )

        GL.glDisable(
            GL.GL_LIGHTING
        )

        GL.glDisable(
            GL.GL_DEPTH_TEST
        )

        GL.glLineWidth(
            2.0
        )

        if "TERRAIN IMPACT" in event:
            base_seed = (
                int(age * 18.0)
                + int(
                    get_number(
                        frame,
                        "time",
                    )
                    * 1000.0
                )
            )

            count = 20

            GL.glColor3f(
                1.0,
                0.12,
                0.08,
            )

            GL.glBegin(
                GL.GL_LINES
            )

            for i in range(count):
                n = (
                    base_seed
                    * 1103515245
                    + i * 12345
                ) & 0x7FFFFFFF

                theta = (
                    (
                        n % 3600
                    )
                    / 3600.0
                ) * math.tau

                n2 = (
                    n
                    * 1664525
                    + 1013904223
                ) & 0x7FFFFFFF

                length = (
                    3.0
                    + (
                        n2 % 900
                    ) / 100.0
                )

                vertical = (
                    0.15
                    + (
                        (
                            n2 // 1000
                        )
                        % 700
                    ) / 1000.0
                )

                sx = (
                    px
                    + math.cos(theta)
                    * 0.8
                )

                sy = py + 0.5

                sz = (
                    pz
                    + math.sin(theta)
                    * 0.8
                )

                ex = (
                    px
                    + math.cos(theta)
                    * length
                )

                ey = (
                    py
                    + vertical
                    * length
                )

                ez = (
                    pz
                    + math.sin(theta)
                    * length
                )

                GL.glVertex3f(
                    sx,
                    sy,
                    sz,
                )

                GL.glVertex3f(
                    ex,
                    ey,
                    ez,
                )

            GL.glEnd()

        elif "GROUND SLIDE" in event:
            base_seed = (
                int(age * 18.0)
                + int(
                    get_number(
                        frame,
                        "time",
                    )
                    * 1000.0
                )
                + 0x5A17
            )

            count = 20

            GL.glColor3f(
                1.0,
                0.50,
                0.05,
            )

            GL.glBegin(
                GL.GL_LINES
            )

            for i in range(count):
                n = (
                    base_seed
                    * 1103515245
                    + i * 12345
                ) & 0x7FFFFFFF

                theta = (
                    (
                        n % 3600
                    )
                    / 3600.0
                ) * math.tau

                n2 = (
                    n
                    * 1664525
                    + 1013904223
                ) & 0x7FFFFFFF

                length = (
                    3.0
                    + (
                        n2 % 900
                    ) / 100.0
                )

                vertical = (
                    0.15
                    + (
                        (
                            n2 // 1000
                        )
                        % 700
                    ) / 1000.0
                )

                sx = (
                    px
                    + math.cos(theta)
                    * 0.8
                )

                sy = py + 0.5

                sz = (
                    pz
                    + math.sin(theta)
                    * 0.8
                )

                ex = (
                    px
                    + math.cos(theta)
                    * length
                )

                ey = (
                    py
                    + vertical
                    * length
                )

                ez = (
                    pz
                    + math.sin(theta)
                    * length
                )

                GL.glVertex3f(
                    sx,
                    sy,
                    sz,
                )

                GL.glVertex3f(
                    ex,
                    ey,
                    ez,
                )

            GL.glEnd()

        GL.glEnable(
            GL.GL_DEPTH_TEST
        )

        GL.glEnable(
            GL.GL_LIGHTING
        )

    def paintGL(self):
        GL.glClear(
            GL.GL_COLOR_BUFFER_BIT
            | GL.GL_DEPTH_BUFFER_BIT
        )

        if self.current_frame is None:
            return

        GL.glMatrixMode(
            GL.GL_MODELVIEW
        )

        GL.glLoadIdentity()

        self.set_camera(
            self.current_frame
        )

        self.draw_grid(
            self.current_frame
        )

        self.draw_paths()

        self.draw_aircraft(
            self.current_frame
        )

        self.draw_event_effects(
            self.current_frame
        )

        if (
            AIRCRAFT_DEBUG_RENDER
            and self.aircraft.scene is not None
        ):
            GL.glDisable(
                GL.GL_LIGHTING
            )

            GL.glColor3f(
                1.0,
                1.0,
                1.0,
            )

            GL.glPointSize(
                5.0
            )

            GL.glBegin(
                GL.GL_POINTS
            )

            px, py, pz = frame_position(
                self.current_frame
            )

            GL.glVertex3f(
                px,
                py,
                pz,
            )

            GL.glEnd()

            GL.glPointSize(
                1.0
            )

            GL.glEnable(
                GL.GL_LIGHTING
            )


# ============================================================
# CVR AUDIO
# ============================================================

def prepare_cvr_audio(path):
    path = Path(path)

    if not LOUDEN_CVR_AUDIO:
        return path

    ffmpeg = shutil.which(
        "ffmpeg"
    )

    if not ffmpeg:
        return path

    try:
        CVR_AUDIO_CACHE_DIR.mkdir(
            parents=True,
            exist_ok=True,
        )

        key = hashlib.sha1(
            str(
                path.resolve()
            ).encode(
                "utf-8",
                "ignore",
            )
        ).hexdigest()[:16]

        output = (
            CVR_AUDIO_CACHE_DIR
            / f"{path.stem}_{key}_150.wav"
        )

        if (
            output.exists()
            and output.stat().st_size > 44
        ):
            return output

        command = [
            ffmpeg,
            "-y",
            "-i",
            str(path),
            "-filter:a",
            f"volume={CVR_VOLUME_MULTIPLIER}",
            "-vn",
            str(output),
        ]

        result = subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=60,
        )

        if (
            result.returncode == 0
            and output.exists()
            and output.stat().st_size > 44
        ):
            return output

    except Exception:
        pass

    return path


# ============================================================
# MAIN WINDOW
# ============================================================

class RFDRWindow(QMainWindow):

    def __init__(self):
        super().__init__()

        self.setWindowTitle(
            "RFDR - Roblox Flight Data Recorder"
        )

        self.resize(
            WINDOW_WIDTH,
            WINDOW_HEIGHT,
        )

        self.setStyle(
            QStyleFactory.create(
                "Windows"
            )
        )

        source = (
            RFDR_FILE
            if RFDR_FILE.exists()
            else RFDR_CSV_FALLBACK
        )

        self.recording = load_rfdr(
            str(source)
        )

        self.frames = list(
            getattr(
                self.recording,
                "frames",
                [],
            )
        )

        calculate_missing_xz(
            self.frames,
            getattr(
                self.recording,
                "has_recorded_x",
                None,
            ),
            getattr(
                self.recording,
                "has_recorded_z",
                None,
            ),
        )

        attach_optional_csv_fields(
            source,
            self.frames,
        )

        self.lateral_scale = max(
            50.0,
            max(
                (
                    abs(
                        get_number(
                            f,
                            "velocity_x",
                            default=0.0,
                        )
                    )
                    for f in self.frames
                ),
                default=50.0,
            )
            * 1.10,
        )

        self.frame_times = [
            get_number(
                f,
                "time",
            )
            for f in self.frames
        ]

        self.frame_index = 0

        self.playback_time = (
            self.frame_times[0]
            if self.frame_times
            else 0.0
        )

        self.playing = False

        self.instrument_panel = (
            InstrumentPanel()
        )

        self.chase_view = (
            ChaseView()
        )

        self.chase_view.set_frames(
            self.frames
        )

        self.yoke = (
            YokeWidget()
        )

        self.engine_indicator = (
            EngineStatusWidget()
        )

        self.yoke.setFixedHeight(
            UNDERBAR_HEIGHT
        )

        self.event_panel = (
            EventCVRPanel(
                self.recording
            )
        )

        self.event_panel.setFixedHeight(
            UNDERBAR_HEIGHT
        )

        self.event_panel.setSizePolicy(
            QSizePolicy.Expanding,
            QSizePolicy.Fixed,
        )

        self.heading_panel = (
            HeadingPanel()
        )

        self.heading_panel.setFixedHeight(
            UNDERBAR_HEIGHT
        )

        self.heading_panel.setSizePolicy(
            QSizePolicy.Expanding,
            QSizePolicy.Fixed,
        )

        # ====================================================
        # CVR OVERLAY
        # ====================================================

        self.cvr_overlay = QLabel(
            self.chase_view
        )

        self.cvr_overlay.setGeometry(
            10,
            10,
            520,
            170,
        )

        self.cvr_overlay.setWordWrap(
            True
        )

        self.cvr_overlay.setAttribute(
            Qt.WA_TransparentForMouseEvents,
            True,
        )

        self.cvr_overlay.setStyleSheet(
            'QLabel { '
            'color:#FFFFFF; '
            'background:rgba(192,192,192,175); '
            'padding:8px; '
            'border:1px solid rgba(128,128,128,220); '
            'font-family:"MS Sans Serif"; '
            'font-size:14pt; '
            'font-weight:bold; '
            '}'
        )

        self.cvr_overlay.hide()

        # ====================================================
        # PROGRESS
        # ====================================================

        self.progress = QProgressBar()

        self.progress.setRange(
            0,
            100000,
        )

        self.progress.setTextVisible(
            False
        )

        self.progress.setFixedHeight(
            20
        )

        self.progress.mousePressEvent = (
            self.progress_mouse_press
        )

        self.progress.mouseMoveEvent = (
            self.progress_mouse_move
        )

        self.progress.mouseReleaseEvent = (
            self.progress_mouse_release
        )

        self.scrubbing = False

        # ====================================================
        # TIMELINE
        # ====================================================

        self.timeline = QSlider(
            Qt.Horizontal
        )

        self.timeline.setRange(
            0,
            max(
                0,
                len(self.frames) - 1,
            ),
        )

        self.timeline.valueChanged.connect(
            self.timeline_changed
        )

        # ====================================================
        # CONTROLS
        # ====================================================

        self.play_button = QPushButton(
            "▶ PLAY"
        )

        self.play_button.clicked.connect(
            self.toggle_play
        )

        self.restart_button = QPushButton(
            "RESTART"
        )

        self.restart_button.clicked.connect(
            self.restart
        )

        self.status = QLabel(
            "READY"
        )

        self.status.setAlignment(
            Qt.AlignCenter
        )

        self.sec_label = QLabel(
            "SEC 0.000"
        )

        self.sec_label.setAlignment(
            Qt.AlignCenter
        )

        self.info = QLabel(
            "NO DATA"
            if not self.frames
            else "READY"
        )

        self.info.setWordWrap(
            True
        )

        # ====================================================
        # LAYOUT
        # ====================================================

        central = QWidget()

        self.setCentralWidget(
            central
        )

        root = QVBoxLayout(
            central
        )

        root.setContentsMargins(
            4,
            4,
            4,
            4,
        )

        root.setSpacing(4)

        top = QHBoxLayout()

        top.setSpacing(4)

        top.addWidget(
            self.chase_view,
            1,
        )

        top.addWidget(
            self.instrument_panel,
            0,
        )

        root.addLayout(
            top,
            1,
        )

        under = QHBoxLayout()

        under.setSpacing(4)

        under.setContentsMargins(
            0,
            0,
            0,
            0,
        )

        under_widget = QWidget()

        under_widget.setFixedHeight(
            UNDERBAR_HEIGHT
        )

        under_widget.setStyleSheet(
            "background:#C0C0C0;"
        )

        under_widget.setLayout(
            under
        )

        under.addWidget(
            self.yoke,
            3,
        )

        under.addWidget(
            self.engine_indicator,
            0,
        )

        under.addWidget(
            self.event_panel,
            3,
        )

        under.addWidget(
            self.heading_panel,
            2,
        )

        root.addWidget(
            under_widget,
            0,
        )

        bottom = QHBoxLayout()

        bottom.setSpacing(4)

        bottom.addWidget(
            self.play_button
        )

        bottom.addWidget(
            self.restart_button
        )

        bottom.addWidget(
            self.sec_label
        )

        bottom.addWidget(
            self.progress,
            2,
        )

        bottom.addWidget(
            self.timeline,
            3,
        )

        bottom.addWidget(
            self.status,
            0,
        )

        root.addLayout(
            bottom
        )

        # ====================================================
        # PLAYBACK TIMER
        # ====================================================

        self.timer = QTimer(self)

        self.timer.setInterval(
            PLAYBACK_INTERVAL
        )

        self.timer.timeout.connect(
            self.advance_playback
        )

        self.elapsed = QElapsedTimer()

        # ====================================================
        # CVR AUDIO
        # ====================================================

        self.cvr_audio_player = None
        self.cvr_audio_output = None

        self.cvr_audio_events = (
            self.build_cvr_audio_events()
        )

        self.cvr_audio_state = None
        self.cvr_audio_start_time = None
        self.cvr_audio_start_path = None

        self.cvr_audio_event_index = -1

        self.cvr_audio_pending_offset = 0.0
        self.cvr_audio_pending_path = None

        if QT_MULTIMEDIA_AVAILABLE:
            try:
                self.cvr_audio_player = (
                    QMediaPlayer(self)
                )

                self.cvr_audio_output = (
                    QAudioOutput(self)
                )

                self.cvr_audio_player.setAudioOutput(
                    self.cvr_audio_output
                )

                self.cvr_audio_output.setVolume(
                    1.0
                )

            except Exception:
                self.cvr_audio_player = None
                self.cvr_audio_output = None

        self.apply_win98_style()

        if self.frames:
            self.set_frame(0)

        else:
            self.status.setText(
                "FAILED TO LOAD RFDR"
            )

    def build_cvr_audio_events(self):
        events = []

        for i, frame in enumerate(
            self.frames
        ):
            raw = get_text(
                frame,
                "cvr_audio",
                "",
            ).strip()

            if not raw:
                continue

            upper = raw.upper()

            if upper.startswith(
                "START_"
            ):
                events.append(
                    (
                        get_number(
                            frame,
                            "time",
                        ),
                        "START",
                        raw[6:].strip(),
                        i,
                    )
                )

            elif upper.startswith(
                "END_"
            ):
                events.append(
                    (
                        get_number(
                            frame,
                            "time",
                        ),
                        "END",
                        raw[4:].strip(),
                        i,
                    )
                )

        events.sort(
            key=lambda e:
            (
                e[0],
                e[3],
            )
        )

        return events

    def _resolve_audio_path(
        self,
        value,
    ):
        p = Path(
            value
            .strip()
            .strip('"')
        )

        if not p.is_absolute():
            p = BASE_DIR / p

        return p.resolve()

    def _stop_cvr_audio(self):
        if self.cvr_audio_player is not None:
            try:
                self.cvr_audio_player.stop()
            except Exception:
                pass

        self.cvr_audio_state = None

        self.cvr_audio_pending_path = None

        self.cvr_audio_pending_offset = 0.0

    def _start_cvr_audio(
        self,
        path_text,
        offset_seconds=0.0,
    ):
        if self.cvr_audio_player is None:
            return

        path = self._resolve_audio_path(
            path_text
        )

        if not path.exists():
            self.status.setText(
                f"CVR AUDIO NOT FOUND: {path}"
            )

            return

        try:
            from PySide6.QtCore import (
                QUrl,
                QTimer as _QTimer,
            )

            offset_ms = max(
                0,
                int(
                    round(
                        float(
                            offset_seconds
                        )
                        * 1000.0
                    )
                ),
            )

            playback_path = (
                prepare_cvr_audio(
                    path
                )
            )

            self.cvr_audio_pending_offset = (
                offset_ms
            )

            self.cvr_audio_pending_path = (
                str(playback_path)
            )

            self.cvr_audio_player.setSource(
                QUrl.fromLocalFile(
                    str(playback_path)
                )
            )

            self.cvr_audio_state = (
                str(playback_path)
            )

            def finish_load():
                if self.cvr_audio_player is None:
                    return

                if (
                    self.cvr_audio_pending_path
                    != str(playback_path)
                ):
                    return

                try:
                    self.cvr_audio_player.setPosition(
                        self.cvr_audio_pending_offset
                    )

                    if self.playing:
                        self.cvr_audio_player.play()

                except Exception:
                    pass

            _QTimer.singleShot(
                80,
                finish_load,
            )

        except Exception as exc:
            self.status.setText(
                f"CVR AUDIO ERROR: {exc}"
            )

    def sync_cvr_audio(
        self,
        playback_time,
        force=False,
    ):
        if not self.playing:
            self._stop_cvr_audio()
            self.cvr_audio_event_index = -1
            return

        if not self.cvr_audio_events:
            self._stop_cvr_audio()
            self.cvr_audio_event_index = -1
            return

        active_path = None
        active_start_time = None
        active_index = -1

        for idx, (
            event_time,
            action,
            path_text,
            frame_idx,
        ) in enumerate(
            self.cvr_audio_events
        ):
            if (
                event_time
                <= playback_time
                + 1e-6
            ):
                if action == "START":
                    active_path = path_text
                    active_start_time = (
                        event_time
                    )

                else:
                    active_path = None
                    active_start_time = None

                active_index = idx

            else:
                break

        if active_path is None:
            if (
                self.cvr_audio_event_index
                != active_index
                or force
            ):
                self._stop_cvr_audio()
                self.cvr_audio_event_index = (
                    active_index
                )

            return

        offset_seconds = max(
            0.0,
            float(playback_time)
            - float(active_start_time),
        )

        resolved_source = (
            self._resolve_audio_path(
                active_path
            )
        )

        resolved = str(
            prepare_cvr_audio(
                resolved_source
            )
        )

        if (
            force
            or active_index
            != self.cvr_audio_event_index
            or self.cvr_audio_state
            != resolved
        ):
            self.cvr_audio_event_index = (
                active_index
            )

            self._start_cvr_audio(
                active_path,
                offset_seconds,
            )

    def update_cvr_overlay(
        self,
        frame_index,
    ):
        frames = self.frames

        if not frames:
            self.cvr_overlay.hide()
            return

        i = max(
            0,
            min(
                frame_index,
                len(frames) - 1,
            ),
        )

        entries = []
        last = None

        start = max(
            0,
            i - CVR_MAX_LINES * 2,
        )

        for frame in frames[
            start:i + 1
        ]:
            text = get_text(
                frame,
                "cvr",
            ).strip()

            if (
                not text
                or text == last
            ):
                continue

            last = text

            color = normalize_hex_color(
                get_text(
                    frame,
                    "cvr_color",
                    "#FFFFFF",
                ),
                "#FFFFFF",
            )

            entries.append(
                (
                    text,
                    color,
                )
            )

        if not entries:
            self.cvr_overlay.hide()
            return

        html = (
            '<div style="line-height:135%;">'
        )

        for text, color in entries[
            -CVR_MAX_LINES:
        ]:
            safe = (
                text
                .replace(
                    "&",
                    "&amp;",
                )
                .replace(
                    "<",
                    "&lt;",
                )
                .replace(
                    ">",
                    "&gt;",
                )
            )

            html += (
                f'<div style="color:{color};">'
                f"{safe}"
                "</div>"
            )

        html += "</div>"

        self.cvr_overlay.setText(
            html
        )

        self.cvr_overlay.show()

    # ========================================================
    # WIN98 STYLE
    # ========================================================

    def apply_win98_style(self):
        self.setStyleSheet(
            """
            QMainWindow, QWidget {
                background-color: #C0C0C0;
                color: #000000;
                font-family: 'MS Sans Serif';
                font-size: 9pt;
            }

            QPushButton {
                background-color: #C0C0C0;
                border-top: 2px solid #FFFFFF;
                border-left: 2px solid #FFFFFF;
                border-right: 2px solid #808080;
                border-bottom: 2px solid #808080;
                padding: 3px 10px;
                min-height: 24px;
            }

            QPushButton:pressed {
                border-top: 2px solid #808080;
                border-left: 2px solid #808080;
                border-right: 2px solid #FFFFFF;
                border-bottom: 2px solid #FFFFFF;
            }

            QSlider::groove:horizontal {
                height: 8px;
                background: #808080;
            }

            QSlider::handle:horizontal {
                width: 12px;
                margin: -3px 0;
                background: #C0C0C0;
                border-top: 2px solid #FFFFFF;
                border-left: 2px solid #FFFFFF;
                border-right: 2px solid #808080;
                border-bottom: 2px solid #808080;
            }

            QProgressBar {
                background: #FFFFFF;
                border-top: 2px solid #808080;
                border-left: 2px solid #808080;
                border-right: 2px solid #FFFFFF;
                border-bottom: 2px solid #FFFFFF;
            }

            QProgressBar::chunk {
                background: #000080;
            }
            """
        )

    # ========================================================
    # FRAME INTERPOLATION
    # ========================================================

    def interpolated_frame(
        self,
        playback_time,
    ):
        if not self.frames:
            return None

        if len(self.frames) == 1:
            a = b = self.frames[0]
            t = 0.0
            index = 0

        elif playback_time <= self.frame_times[0]:
            a = b = self.frames[0]
            t = 0.0
            index = 0

        elif playback_time >= self.frame_times[-1]:
            index = len(self.frames) - 1
            a = b = self.frames[index]
            t = 0.0

        else:
            right = bisect_right(
                self.frame_times,
                playback_time,
            )

            index = max(
                0,
                right - 1,
            )

            i2 = min(
                len(self.frames) - 1,
                right,
            )

            a = self.frames[index]
            b = self.frames[i2]

            dt = (
                get_number(
                    b,
                    "time",
                )
                - get_number(
                    a,
                    "time",
                )
            )

            t = (
                clamp(
                    (
                        playback_time
                        - get_number(
                            a,
                            "time",
                        )
                    )
                    / dt,
                    0.0,
                    1.0,
                )
                if dt > 0
                else 0.0
            )

        class F:
            pass

        out = F()

        out.time = playback_time

        out.airspeed = lerp(
            get_number(
                a,
                "airspeed",
                "spd",
            ),
            get_number(
                b,
                "airspeed",
                "spd",
            ),
            t,
        )

        out.altitude = lerp(
            get_number(
                a,
                "altitude",
                "alt",
            ),
            get_number(
                b,
                "altitude",
                "alt",
            ),
            t,
        )

        out.pitch = lerp(
            get_number(
                a,
                "pitch",
                "pch",
            ),
            get_number(
                b,
                "pitch",
                "pch",
            ),
            t,
        )

        out.roll = lerp(
            get_number(
                a,
                "roll",
                "rll",
            ),
            get_number(
                b,
                "roll",
                "rll",
            ),
            t,
        )

        source = (
            a if t < 0.5 else b
        )

        out.heading = raw_rfdr_heading(
            source
        )

        out.power = lerp(
            get_number(
                a,
                "power",
                "pwr",
            ),
            get_number(
                b,
                "power",
                "pwr",
            ),
            t,
        )

        out.engine = get_text(
            source,
            "engine",
            "",
        )

        out.engine_state = get_text(
            source,
            "engine_state",
            out.engine,
        )

        out.x = lerp(
            get_number(
                a,
                "x",
            ),
            get_number(
                b,
                "x",
            ),
            t,
        )

        out.z = lerp(
            get_number(
                a,
                "z",
            ),
            get_number(
                b,
                "z",
            ),
            t,
        )

        out.y = out.altitude

        out.velocity_x = lerp(
            get_number(
                a,
                "velocity_x",
                default=0.0,
            ),
            get_number(
                b,
                "velocity_x",
                default=0.0,
            ),
            t,
        )

        out.velocity_z = lerp(
            get_number(
                a,
                "velocity_z",
                default=0.0,
            ),
            get_number(
                b,
                "velocity_z",
                default=0.0,
            ),
            t,
        )

        if (
            abs(out.velocity_x)
            < 1e-12
            and
            abs(
                get_number(
                    b,
                    "x",
                )
                - get_number(
                    a,
                    "x",
                )
            )
            > 1e-12
        ):
            dt_pos = (
                get_number(
                    b,
                    "time",
                )
                - get_number(
                    a,
                    "time",
                )
            )

            if dt_pos > 0.0:
                out.velocity_x = (
                    get_number(
                        b,
                        "x",
                    )
                    - get_number(
                        a,
                        "x",
                    )
                ) / dt_pos

        supplied_a = getattr(
            a,
            "provided_vsi",
            None,
        )

        supplied_b = getattr(
            b,
            "provided_vsi",
            None,
        )

        if (
            supplied_a is not None
            or supplied_b is not None
        ):
            out.provided_vsi = lerp(
                float(
                    supplied_a
                    if supplied_a is not None
                    else supplied_b
                ),
                float(
                    supplied_b
                    if supplied_b is not None
                    else supplied_a
                ),
                t,
            )

        else:
            out.provided_vsi = None

        out.vertical_speed = lerp(
            get_number(
                a,
                "vertical_speed",
            ),
            get_number(
                b,
                "vertical_speed",
            ),
            t,
        )

        out.acceleration = lerp(
            get_number(
                a,
                "acceleration",
            ),
            get_number(
                b,
                "acceleration",
            ),
            t,
        )

        out.distance = lerp(
            get_number(
                a,
                "distance",
            ),
            get_number(
                b,
                "distance",
            ),
            t,
        )

        source = (
            a if t < 0.5 else b
        )

        out.W = get_bool(
            source,
            "W",
        )

        out.A = get_bool(
            source,
            "A",
        )

        out.S = get_bool(
            source,
            "S",
        )

        out.D = get_bool(
            source,
            "D",
        )

        out.event = get_text(
            source,
            "event",
        )

        out.event_color = normalize_hex_color(
            get_text(
                source,
                "event_color",
                "#FFFFFF",
            )
        )

        out.cvr = get_text(
            source,
            "cvr",
        )

        out.cvr_color = normalize_hex_color(
            get_text(
                source,
                "cvr_color",
                "#FFFFFF",
            )
        )

        out.cvr_audio = get_text(
            source,
            "cvr_audio",
        )

        pa = getattr(
            a,
            "provided_vsi",
            None,
        )

        pb = getattr(
            b,
            "provided_vsi",
            None,
        )

        if (
            pa is not None
            or pb is not None
        ):
            if pa is None:
                pa = pb

            if pb is None:
                pb = pa

            out.provided_vsi = lerp(
                float(pa),
                float(pb),
                t,
            )

        else:
            out.provided_vsi = None

        return out

    # ========================================================
    # FRAME UPDATE
    # ========================================================

    def set_frame(self, index):
        if not self.frames:
            return

        index = max(
            0,
            min(
                index,
                len(self.frames) - 1,
            ),
        )

        self.frame_index = index

        self.playback_time = (
            self.frame_times[index]
        )

        self.timeline.blockSignals(
            True
        )

        self.timeline.setValue(
            index
        )

        self.timeline.blockSignals(
            False
        )

        frame = self.interpolated_frame(
            self.playback_time
        )

        self.update_everything(
            frame,
            snap_yoke=True,
        )

    def update_everything(
        self,
        frame,
        snap_yoke=False,
    ):
        self.instrument_panel.set_frame(
            frame
        )

        self.chase_view.set_frame(
            frame
        )

        self.heading_panel.set_frame(
            frame
        )

        self.event_panel.update_frame(
            self.frame_index,
            frame,
        )

        self.engine_indicator.set_engine(
            engine_display_value(
                frame
            )
        )

        self.update_cvr_overlay(
            self.frame_index
        )

        if self.playing:
            self.sync_cvr_audio(
                self.playback_time
            )

        else:
            self._stop_cvr_audio()
            self.cvr_audio_event_index = -1

        pitch_rate = (
            attitude_rate_at_time(
                self.frames,
                self.frame_times,
                get_number(
                    frame,
                    "time",
                ),
                "pitch",
            )
        )

        roll_rate = (
            attitude_rate_at_time(
                self.frames,
                self.frame_times,
                get_number(
                    frame,
                    "time",
                ),
                "roll",
            )
        )

        self.yoke.set_recorded_input(
            get_bool(
                frame,
                "W",
            ),
            get_bool(
                frame,
                "A",
            ),
            get_bool(
                frame,
                "S",
            ),
            get_bool(
                frame,
                "D",
            ),
            pitch_rate,
            roll_rate,
        )

        if snap_yoke:
            self.yoke.current_x = (
                self.yoke.target_x
            )

            self.yoke.current_y = (
                self.yoke.target_y
            )

            self.yoke.vx = 0.0
            self.yoke.vy = 0.0

        x = get_number(
            frame,
            "x",
        )

        z = get_number(
            frame,
            "z",
        )

        self.sec_label.setText(
            f"SEC "
            f"{get_number(frame, 'time'):.3f}"
        )

        self.info.setText(
            f"SPD "
            f"{get_number(frame, 'airspeed'):.2f}\n"
            f"ALT "
            f"{get_number(frame, 'altitude'):.2f}\n"
            f"HDG "
            f"{get_number(frame, 'heading'):03.0f}\n"
            f"PWR "
            f"{power_display_value(frame):.2f}"
            f"    ENG "
            f"{engine_display_value(frame):.2f}\n"
            f"X {x:.2f}\n"
            f"Z {z:.2f}\n"
            f"W {int(get_bool(frame, 'W'))}  "
            f"A {int(get_bool(frame, 'A'))}  "
            f"S {int(get_bool(frame, 'S'))}  "
            f"D {int(get_bool(frame, 'D'))}"
        )

        self.update_progress()

    def advance_playback(self):
        if (
            not self.playing
            or not self.frames
        ):
            return

        elapsed_ms = (
            self.elapsed.restart()
        )

        dt = clamp(
            elapsed_ms / 1000.0,
            0.0,
            0.1,
        )

        if dt <= 0.0:
            return

        self.playback_time += dt

        if (
            self.playback_time
            >= self.frame_times[-1]
        ):
            self.playback_time = (
                self.frame_times[-1]
            )

            self.frame_index = (
                len(self.frames) - 1
            )

            self.playing = False

            self.timer.stop()

            self.play_button.setText(
                "▶ PLAY"
            )

        else:
            self.frame_index = max(
                0,
                bisect_right(
                    self.frame_times,
                    self.playback_time,
                ) - 1,
            )

        frame = self.interpolated_frame(
            self.playback_time
        )

        if frame is not None:
            self.instrument_panel.set_frame(
                frame
            )

            self.chase_view.set_frame(
                frame
            )

            self.heading_panel.set_frame(
                frame
            )

            self.event_panel.update_frame(
                self.frame_index,
                frame,
            )

            self.engine_indicator.set_engine(
                engine_display_value(frame)
            )

            self.update_cvr_overlay(
                self.frame_index
            )

            if self.playing:
                self.sync_cvr_audio(
                    self.playback_time
                )

            else:
                self._stop_cvr_audio()
                self.cvr_audio_event_index = -1

            pitch_rate = (
                attitude_rate_at_time(
                    self.frames,
                    self.frame_times,
                    self.playback_time,
                    "pitch",
                )
            )

            roll_rate = (
                attitude_rate_at_time(
                    self.frames,
                    self.frame_times,
                    self.playback_time,
                    "roll",
                )
            )

            self.yoke.set_recorded_input(
                get_bool(
                    frame,
                    "W",
                ),
                get_bool(
                    frame,
                    "A",
                ),
                get_bool(
                    frame,
                    "S",
                ),
                get_bool(
                    frame,
                    "D",
                ),
                pitch_rate,
                roll_rate,
            )

            self.yoke.update_motion(
                dt
            )

            x = get_number(
                frame,
                "x",
            )

            z = get_number(
                frame,
                "z",
            )

            self.info.setText(
                f"SPD "
                f"{get_number(frame, 'airspeed'):.2f}\n"
                f"ALT "
                f"{get_number(frame, 'altitude'):.2f}\n"
                f"HDG "
                f"{get_number(frame, 'heading'):03.0f}\n"
                f"PWR "
                f"{power_display_value(frame):.2f}"
                f"    ENG "
                f"{engine_display_value(frame):.2f}\n"
                f"X {x:.2f}    "
                f"Z {z:.2f}"
            )

        self.timeline.blockSignals(
            True
        )

        self.timeline.setValue(
            self.frame_index
        )

        self.timeline.blockSignals(
            False
        )

        self.update_progress()

    # ========================================================
    # KEYBOARD
    # ========================================================

    def keyPressEvent(self, event):
        key = event.key()

        if key == Qt.Key_Space:
            self.toggle_play()

            event.accept()
            return

        if key in (
            Qt.Key_Left,
            Qt.Key_Right,
        ):
            if not self.frames:
                event.accept()
                return

            self.playing = False

            self.timer.stop()

            self._stop_cvr_audio()

            self.cvr_audio_event_index = -1

            delta = (
                -1
                if key == Qt.Key_Left
                else 1
            )

            new_index = max(
                0,
                min(
                    len(self.frames) - 1,
                    self.frame_index
                    + delta,
                ),
            )

            self.set_frame(
                new_index
            )

            event.accept()
            return

        super().keyPressEvent(
            event
        )

    # ========================================================
    # PLAY / PAUSE
    # ========================================================

    def toggle_play(self):
        if not self.frames:
            return

        if (
            self.playback_time
            >= self.frame_times[-1]
        ):
            self.playback_time = (
                self.frame_times[0]
            )

            self.frame_index = 0

            self.set_frame(0)

        self.playing = not self.playing

        if self.playing:
            self.elapsed.restart()

            self.timer.start()

            self.play_button.setText(
                "⏸ PAUSE"
            )

            self._stop_cvr_audio()

            self.cvr_audio_event_index = -1

            self.sync_cvr_audio(
                self.playback_time,
                force=True,
            )

        else:
            self.timer.stop()

            self._stop_cvr_audio()

            self.cvr_audio_event_index = -1

            self.play_button.setText(
                "▶ PLAY"
            )

    # ========================================================
    # RESTART
    # ========================================================

    def restart(self):
        if not self.frames:
            return

        self.playing = False

        self.timer.stop()

        self.play_button.setText(
            "▶ PLAY"
        )

        self._stop_cvr_audio()

        self.cvr_audio_event_index = -1

        self.set_frame(0)

    # ========================================================
    # TIMELINE
    # ========================================================

    def timeline_changed(
        self,
        value,
    ):
        if (
            self.scrubbing
            or not self.frames
        ):
            return

        self.playing = False

        self.timer.stop()

        self.play_button.setText(
            "▶ PLAY"
        )

        self._stop_cvr_audio()

        self.cvr_audio_event_index = -1

        self.set_frame(value)

    # ========================================================
    # PROGRESS BAR SEEKING
    # ========================================================

    def seek_progress_from_mouse(
        self,
        event,
    ):
        if not self.frames:
            return

        x = clamp(
            event.position().x(),
            0,
            max(
                1,
                self.progress.width() - 1,
            ),
        )

        ratio = (
            x
            / float(
                max(
                    1,
                    self.progress.width() - 1,
                )
            )
        )

        self.playback_time = (
            self.frame_times[0]
            + ratio
            * (
                self.frame_times[-1]
                - self.frame_times[0]
            )
        )

        self.frame_index = max(
            0,
            bisect_right(
                self.frame_times,
                self.playback_time,
            ) - 1,
        )

        frame = self.interpolated_frame(
            self.playback_time
        )

        if frame is not None:
            self.instrument_panel.set_frame(
                frame
            )

            self.chase_view.set_frame(
                frame
            )

            self.heading_panel.set_frame(
                frame
            )

            self.event_panel.update_frame(
                self.frame_index,
                frame,
            )

        self.engine_indicator.set_engine(
            engine_display_value(
                frame
            )
        )

        self.update_cvr_overlay(
            self.frame_index
        )

        if self.playing:
            self._stop_cvr_audio()

            self.cvr_audio_event_index = -1

            self.sync_cvr_audio(
                self.playback_time,
                force=True,
            )

        else:
            self._stop_cvr_audio()

            self.cvr_audio_event_index = -1

        self.update_progress()

    def progress_mouse_press(
        self,
        event,
    ):
        if event.button() == Qt.LeftButton:
            self.scrubbing = True

            self.playing = False

            self.timer.stop()

            self.play_button.setText(
                "▶ PLAY"
            )

            self.seek_progress_from_mouse(
                event
            )

            event.accept()
            return

        QProgressBar.mousePressEvent(
            self.progress,
            event,
        )

    def progress_mouse_move(
        self,
        event,
    ):
        if self.scrubbing:
            self.seek_progress_from_mouse(
                event
            )

            event.accept()
            return

        QProgressBar.mouseMoveEvent(
            self.progress,
            event,
        )

    def progress_mouse_release(
        self,
        event,
    ):
        if self.scrubbing:
            self.seek_progress_from_mouse(
                event
            )

            self.scrubbing = False

            event.accept()
            return

        QProgressBar.mouseReleaseEvent(
            self.progress,
            event,
        )

    # ========================================================
    # CLOSE
    # ========================================================

    def closeEvent(self, event):
        self.playing = False

        try:
            self.timer.stop()
        except Exception:
            pass

        self._stop_cvr_audio()

        self.cvr_audio_event_index = -1

        event.accept()

    # ========================================================
    # PROGRESS
    # ========================================================

    def update_progress(self):
        if (
            not self.frames
            or len(self.frame_times) < 1
        ):
            self.progress.setValue(0)
            return

        start = self.frame_times[0]
        end = self.frame_times[-1]

        ratio = (
            0.0
            if end <= start
            else clamp(
                (
                    self.playback_time
                    - start
                )
                / (
                    end
                    - start
                ),
                0.0,
                1.0,
            )
        )

        self.progress.setValue(
            int(
                ratio * 100000
            )
        )


# ============================================================
# MAIN
# ============================================================

def main():
    app = QApplication(sys.argv)

    app.setStyle(
        QStyleFactory.create(
            "Windows"
        )
    )

    window = RFDRWindow()

    window.show()

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
