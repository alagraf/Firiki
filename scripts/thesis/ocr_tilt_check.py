#!/usr/bin/env python3
"""
scripts/thesis/ocr_tilt_check.py

Checks the tilted-line OCR fix (FORK_CHANGES 2.11.22) on pages the OCR benchmark doesn't use.
Makes fresh simulated scans (same degradation as make_ocr_testset.make_scan, a random tilt in
[-2.5°, 2.5°]) from 9 Labour Code excerpt pages and 5 Constitution pages, then reads every detected
line with a Python copy of the app's PaddleOCR steps in two ways: the axis-aligned crop the app used
before, and the crop along the line (principal axis) the app uses now, with the same angle limits
as GreekPaddleOCRService (at most 15°, region at least twice as long as thick, rise at least 0.25 of
the thickness, else the axis-aligned crop). Prints bag-of-words recall per page and the means.

Usage (pymupdf, pillow, numpy, onnxruntime):
  python3 scripts/thesis/ocr_tilt_check.py [work-dir]
"""

import re
import sys
import tempfile
import unicodedata
from collections import Counter, deque
from pathlib import Path

import numpy as np
import onnxruntime as ort
import pymupdf
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/thesis"))
import make_ocr_testset as testset  # noqa: E402

MODELS = ROOT / "Firiki/Resources/MLModels/GreekOCR"
SOURCES = [
    (ROOT / "Benchmarks/GreekLabourCode/pd_62_2025_excerpt.pdf", "lab", [3, 7, 11, 15, 19, 23, 27, 31, 35]),
    (ROOT / "Benchmarks/GreekConstitution/syntagma1_1.pdf", "con", [6, 14, 22, 30, 38]),
]
MAX_ANGLE, MIN_ELONGATION, MIN_RISE = 15.0, 4.0, 0.25
MEAN = np.array([0.485, 0.456, 0.406], np.float32)
STD = np.array([0.229, 0.224, 0.225], np.float32)

det = ort.InferenceSession(str(MODELS / "PP-OCRv5_mobile_det.onnx"))
rec = ort.InferenceSession(str(MODELS / "el_PP-OCRv5_mobile_rec.onnx"))
chars = (MODELS / "el_dict.txt").read_text(encoding="utf-8").split("\n")
if chars and chars[-1] == "":
    chars = chars[:-1]


def words(text):
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    return Counter(w for w in re.split(r"[^\w]+", text) if w)


def recall(reference, hypothesis):
    r, h = words(reference), words(hypothesis)
    return sum((r & h).values()) / sum(r.values())


def det_size(width, height):
    scale = 960 / max(width, height)
    r32 = lambda v: max(32, int(round(v / 32)) * 32)
    return r32(width * scale), r32(height * scale)


def regions(img):
    """Connected regions of the DB probability map as pixel centres in image coordinates."""
    W, H = img.size
    w, h = det_size(W, H)
    a = (np.asarray(img.resize((w, h), Image.BILINEAR), np.float32) / 255)[:, :, ::-1]
    a = (a - MEAN) / STD
    p = det.run(None, {det.get_inputs()[0].name: a.transpose(2, 0, 1)[None].astype(np.float32)})[0]
    p = p.reshape(-1)[-w * h:].reshape(h, w)
    mask = p > 0.3
    seen = np.zeros_like(mask)
    found = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        queue, pts = deque([(y0, x0)]), []
        seen[y0, x0] = True
        while queue:
            y, x = queue.popleft()
            pts.append((x, y))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        P = np.array(pts, float)
        if min(np.ptp(P[:, 0]), np.ptp(P[:, 1])) + 1 < 3 or len(P) < 4:
            continue
        if p[P[:, 1].astype(int), P[:, 0].astype(int)].mean() < 0.6:
            continue
        found.append((P + 0.5) * [W / w, H / h])
    return found, W / w, H / h


def read(arr):
    hh, ww = arr.shape[:2]
    tw = min(3200, max(1, int(np.ceil(48 * ww / hh))))
    pw = max(320, tw)
    a = np.asarray(Image.fromarray(arr).resize((tw, 48), Image.BILINEAR), np.float32)[:, :, ::-1] / 255
    x = np.zeros((1, 3, 48, pw), np.float32)
    x[0, :, :, :tw] = ((a - 0.5) / 0.5).transpose(2, 0, 1)
    best = rec.run(None, {rec.get_inputs()[0].name: x})[0][0].argmax(1)
    text, prev = "", -1
    for b in best:
        if b != 0 and b != prev:
            text += chars[b - 1] if b - 1 < len(chars) else " "
        prev = b
    return text


def axis_crop(A, P, sx, sy):
    x0, y0 = P.min(0)
    x1, y1 = P.max(0)
    w, h = x1 - x0 + sx, y1 - y0 + sy
    d = w * h * 1.5 / (2 * (w + h))
    H, W = A.shape[:2]
    x0, y0 = max(0, int(x0 - sx / 2 - d)), max(0, int(y0 - sy / 2 - d))
    x1, y1 = min(W, int(x1 + sx / 2 + d)), min(H, int(y1 + sy / 2 + d))
    return A[y0:y1, x0:x1] if x1 - x0 >= 3 and y1 - y0 >= 3 else None


def line_crop(A, P, sx, sy):
    """The crop along the region's principal axis, or None where the app keeps the axis crop."""
    c = P.mean(0)
    C = P - c
    lam, ev = np.linalg.eigh(C.T @ C)
    d = ev[:, 1] if ev[0, 1] >= 0 else -ev[:, 1]
    n = np.array([-d[1], d[0]])
    u, v = C @ d, C @ n
    if abs(np.degrees(np.arctan2(d[1], d[0]))) > MAX_ANGLE or lam[1] < MIN_ELONGATION * lam[0]:
        return None
    if np.ptp(u) * abs(d[1]) < MIN_RISE * (np.ptp(v) + sy):
        return None
    w, h = np.ptp(u) + sx, np.ptp(v) + sy
    grow = w * h * 1.5 / (2 * (w + h))
    w, h = w + 2 * grow, h + 2 * grow
    centre = c + (u.max() + u.min()) / 2 * d + (v.max() + v.min()) / 2 * n
    W, H = int(round(w)), int(round(h))
    gu, gv = np.meshgrid(np.arange(W) + 0.5 - W / 2, np.arange(H) + 0.5 - H / 2)
    fx = centre[0] + gu * d[0] + gv * n[0] - 0.5
    fy = centre[1] + gu * d[1] + gv * n[1] - 0.5
    x0 = np.clip(np.floor(fx).astype(int), 0, A.shape[1] - 2)
    y0 = np.clip(np.floor(fy).astype(int), 0, A.shape[0] - 2)
    wx = np.clip(fx - x0, 0, 1)[..., None]
    wy = np.clip(fy - y0, 0, 1)[..., None]
    I = A.astype(float)
    top = I[y0, x0] * (1 - wx) + I[y0, x0 + 1] * wx
    bottom = I[y0 + 1, x0] * (1 - wx) + I[y0 + 1, x0 + 1] * wx
    return (top * (1 - wy) + bottom * wy).round().clip(0, 255).astype(np.uint8)


def page_text(img):
    A = np.asarray(img)
    found, sx, sy = regions(img)
    straight, along = [], []
    for P in found:
        crop = axis_crop(A, P, sx, sy)
        text = read(crop) if crop is not None else ""
        straight.append(text)
        turned = line_crop(A, P, sx, sy)
        along.append(text if turned is None else read(turned))
    return "\n".join(straight), "\n".join(along)


def make_pages(out):
    rng = np.random.default_rng(7)
    pages = []
    for pdf, tag, numbers in SOURCES:
        doc = pymupdf.open(str(pdf))
        for number in numbers:
            page = doc[number - 1]
            reference, _, _ = testset.extract_page_reference_and_columns(page)
            if len(reference.split()) < 80:
                continue
            angle = float(rng.uniform(-2.5, 2.5))
            zoom = testset.SCAN_DPI / 72
            pix = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom))
            clean = Image.frombytes("RGB", [pix.width, pix.height], pix.samples).convert("L")
            scan = clean.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True, fillcolor=255)
            noisy = np.array(scan, np.float32) + rng.normal(0, 3.0, size=scan.size[::-1])
            scan = ImageEnhance.Contrast(Image.fromarray(np.clip(noisy, 0, 255).astype(np.uint8))).enhance(0.92)
            name = f"{tag}{number:02d}"
            clean.save(out / f"clean_{name}.jpg", quality=testset.SCAN_JPEG_QUALITY)
            scan.save(out / f"scan_{name}.jpg", quality=testset.SCAN_JPEG_QUALITY)
            pages.append((name, angle, reference))
    return pages


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="ocr-tilt-"))
    out.mkdir(parents=True, exist_ok=True)
    totals = {}
    for name, angle, reference in make_pages(out):
        cells = []
        for version in ("clean", "scan"):
            img = Image.open(out / f"{version}_{name}.jpg").convert("RGB")
            straight, along = page_text(img)
            for key, text in (("straight", straight), ("along", along)):
                value = recall(reference, text)
                totals.setdefault((version, key), []).append(value)
                cells.append(f"{version} {key} {value:.3f}")
        print(f"{name} ({angle:+.2f}°): " + "  ".join(cells), flush=True)
    print("MEAN " + "  ".join(f"{v} {k} {np.mean(x):.3f}" for (v, k), x in totals.items()))


if __name__ == "__main__":
    main()
