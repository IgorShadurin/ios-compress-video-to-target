#!/usr/bin/env python3
import os
import subprocess
import time
from pathlib import Path

from PIL import Image


ROOT = Path("/Users/test/XCodeProjects/CompressTarget")
ENV_FILE = Path("/Users/test/XCodeProjects/CompressTarget_data/CompressTarget.simulator.env")

BUNDLE_ID = "org.icorpvideo.CompressVideoToTargetSize"
DEFAULT_UDID = "4E697DCE-DE63-4B43-821C-21257C0FEBC6"

SHOWCASE_STATES = [
    ("source", "main-page"),
    ("settings", "ready-to-convert"),
    ("done", "done-window"),
    ("paywall", "paywall-window"),
]

DEVICEKIT = Path("/Library/Developer/DeviceKit")
CHROME_DIR = DEVICEKIT / "Chrome" / "phone11.devicechrome" / "Contents" / "Resources"
FRAMEBUFFER_MASK = DEVICEKIT / "FramebufferMasks" / "4E5532ED-1470-47D1-BDF4-7AA90C26957A.pdf"

TMP_DIR = Path("/tmp/compress_target_showcase")

# Canvas/layout tuned from official phone11 chrome geometry.
SCALE = 3
CANVAS_W, CANVAS_H = 452 * SCALE, 920 * SCALE
PHONE_X, PHONE_Y = 8 * SCALE, 6 * SCALE
SCREEN_X, SCREEN_Y = PHONE_X + (10 * SCALE), PHONE_Y + (2 * SCALE)
SCREEN_W, SCREEN_H = 415 * SCALE, 902 * SCALE

LEFT_BUTTON_X = 0
RIGHT_BUTTON_X = 436 * SCALE
MUTE_Y = PHONE_Y + (160 * SCALE)
VOL_UP_Y = PHONE_Y + (221 * SCALE)
VOL_DOWN_Y = PHONE_Y + (300 * SCALE)
POWER_Y = PHONE_Y + (262 * SCALE)


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=check, text=True, capture_output=True)


def read_sim_udid() -> str:
    if not ENV_FILE.exists():
        return DEFAULT_UDID

    for line in ENV_FILE.read_text().splitlines():
        if line.startswith("SIM_DEVICE_UDID="):
            value = line.split("=", 1)[1].strip().strip('"').strip("'")
            if value:
                return value
    return DEFAULT_UDID


def convert_pdf_to_png(pdf_path: Path, out_png: Path) -> None:
    run(
        [
            "sips",
            "-s",
            "format",
            "png",
            str(pdf_path),
            "--out",
            str(out_png),
        ]
    )


def ensure_sim_booted(udid: str) -> None:
    run(["xcrun", "simctl", "boot", udid], check=False)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
    run(["xcrun", "simctl", "ui", udid, "appearance", "light"], check=False)


def capture_state_raw(udid: str, step: str, out_png: Path) -> None:
    run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], check=False)
    run(["xcrun", "simctl", "launch", udid, BUNDLE_ID, "-uiShowcaseStep", step])
    wait_s = 2.4 if step == "done" else 1.8
    time.sleep(wait_s)
    run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(out_png)])


def compose_framed_screenshot(
    raw_screen_png: Path,
    phone_composite_png: Path,
    framebuffer_alpha_png: Path,
    mute_png: Path,
    vol_png: Path,
    power_png: Path,
    output_png: Path,
) -> None:
    raw = Image.open(raw_screen_png).convert("RGBA")
    phone = Image.open(phone_composite_png).convert("RGBA").resize(
        (436 * SCALE, 908 * SCALE), Image.Resampling.LANCZOS
    )
    fb_mask = Image.open(framebuffer_alpha_png).convert("L")
    mute = Image.open(mute_png).convert("RGBA").resize(
        (16 * SCALE, 34 * SCALE), Image.Resampling.LANCZOS
    )
    vol = Image.open(vol_png).convert("RGBA").resize(
        (16 * SCALE, 64 * SCALE), Image.Resampling.LANCZOS
    )
    power = Image.open(power_png).convert("RGBA").resize(
        (16 * SCALE, 101 * SCALE), Image.Resampling.LANCZOS
    )

    screen = raw.resize((SCREEN_W, SCREEN_H), Image.Resampling.LANCZOS)
    screen_mask = fb_mask.resize((SCREEN_W, SCREEN_H), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.alpha_composite(phone, (PHONE_X, PHONE_Y))
    canvas.alpha_composite(mute, (LEFT_BUTTON_X, MUTE_Y))
    canvas.alpha_composite(vol, (LEFT_BUTTON_X, VOL_UP_Y))
    canvas.alpha_composite(vol, (LEFT_BUTTON_X, VOL_DOWN_Y))
    canvas.alpha_composite(power, (RIGHT_BUTTON_X, POWER_Y))
    canvas.paste(screen, (SCREEN_X, SCREEN_Y), screen_mask)
    canvas.save(output_png, format="PNG")


def main() -> None:
    udid = read_sim_udid()
    high_dir = ROOT / "showcase" / "high"
    preview_dir = ROOT / "showcase" / "preview"
    high_dir.mkdir(parents=True, exist_ok=True)
    preview_dir.mkdir(parents=True, exist_ok=True)
    TMP_DIR.mkdir(parents=True, exist_ok=True)

    ensure_sim_booted(udid)

    phone_composite = TMP_DIR / "PhoneComposite.png"
    fb_mask = TMP_DIR / "framebuffer_mask.png"
    fb_alpha = TMP_DIR / "framebuffer_alpha.png"
    mute_btn = TMP_DIR / "Mute_BTN.png"
    vol_btn = TMP_DIR / "Vol_BTN.png"
    power_btn = TMP_DIR / "X_Power_BTN.png"

    convert_pdf_to_png(CHROME_DIR / "PhoneComposite.pdf", phone_composite)
    convert_pdf_to_png(FRAMEBUFFER_MASK, fb_mask)
    run(["magick", str(fb_mask), "-alpha", "extract", str(fb_alpha)])
    convert_pdf_to_png(CHROME_DIR / "Mute BTN.pdf", mute_btn)
    convert_pdf_to_png(CHROME_DIR / "Vol BTN.pdf", vol_btn)
    convert_pdf_to_png(CHROME_DIR / "X_Power BTN.pdf", power_btn)

    for step, filename in SHOWCASE_STATES:
        raw_file = TMP_DIR / f"{filename}_raw.png"
        high_file = high_dir / f"{filename}.png"
        preview_file = preview_dir / f"{filename}.png"

        capture_state_raw(udid, step, raw_file)
        compose_framed_screenshot(
            raw_screen_png=raw_file,
            phone_composite_png=phone_composite,
            framebuffer_alpha_png=fb_alpha,
            mute_png=mute_btn,
            vol_png=vol_btn,
            power_png=power_btn,
            output_png=high_file,
        )
        run(
            [
                "magick",
                str(high_file),
                "-filter",
                "Lanczos",
                "-resize",
                "220x",
                "-strip",
                str(preview_file),
            ]
        )

    print("Generated:")
    for _, filename in SHOWCASE_STATES:
        print(high_dir / f"{filename}.png")
        print(preview_dir / f"{filename}.png")


if __name__ == "__main__":
    main()
