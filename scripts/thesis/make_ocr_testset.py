#!/usr/bin/env python3
"""
scripts/thesis/make_ocr_testset.py

Generates the Greek OCR test set from Benchmarks/GreekLabourCode/pd_62_2025_excerpt.pdf.
Creates:
  - Benchmarks/GreekOCR/manifest.json
  - Benchmarks/GreekOCR/images/ (clean, scan, photo versions of 10 fixed pages)
  - Benchmarks/GreekOCR/ref/ (normalized reference texts and per-column extracts)
  - Benchmarks/GreekOCR/scan_pages.pdf (image-only PDF from the 10 scan pages)
  - Benchmarks/GreekOCR/README.md
  - Benchmarks/GreekOCR/photos/README.md

Maintains total Benchmarks/GreekOCR/ directory size strictly under 15 MB.

Requirements:
  pip install pymupdf pillow numpy
"""

import json
import os
import re
import sys
import unicodedata
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageEnhance, ImageFilter
    import pymupdf
except ImportError as e:
    sys.exit(f"Missing dependency: {e}. Run in a venv with: pip install pymupdf pillow numpy")

# 10 pages spread over the 37-page excerpt, skipping near-empty pages (1-indexed)
PAGES = [1, 4, 8, 12, 16, 20, 24, 28, 32, 36]

# Fixed rotation angles per page between -1.5° and +1.5°
SCAN_ROTATIONS = {
    1: -1.2,
    4: 0.8,
    8: -0.5,
    12: 1.4,
    16: -0.9,
    20: 1.1,
    24: -1.5,
    28: 0.6,
    32: -1.0,
    36: 1.3,
}

# Resolutions and JPEG qualities calibrated to keep total folder size under 15 MB
CLEAN_DPI = 200
CLEAN_JPEG_QUALITY = 40
SCAN_DPI = 180
SCAN_JPEG_QUALITY = 45
PHOTO_DPI = 200
PHOTO_JPEG_QUALITY = 55

SEED = 20261029


def normalize_and_dehyphen(text: str) -> str:
    """Normalize Unicode to NFKC and join hyphenated line breaks."""
    text = unicodedata.normalize("NFKC", text)
    # Join Greek/Latin hyphenated line-end words
    text = re.sub(r'(\w+)[-\u00ad\u2010]\s*\n\s*(\w+)', r'\1\2', text)
    return text


def extract_page_reference_and_columns(page: pymupdf.Page):
    """
    Extracts:
      1. Full-page reference text (from page.get_text("text"))
      2. Column 1 (left) and Column 2 (right) reference texts when separable.
    """
    raw_text = page.get_text("text")
    full_ref = normalize_and_dehyphen(raw_text)

    # Separate blocks into header, col1, col2, footer
    mid_x = page.rect.width / 2.0
    blocks = [b for b in page.get_text("blocks") if b[6] == 0 and b[4].strip()]

    # Sort blocks: full-width header/footer vs column blocks
    col1_blocks = []
    col2_blocks = []
    for b in blocks:
        # b = (x0, y0, x1, y2, text, block_no, block_type)
        center_x = (b[0] + b[2]) / 2.0
        if center_x < mid_x:
            col1_blocks.append(b)
        else:
            col2_blocks.append(b)

    col1_blocks.sort(key=lambda b: (b[1], b[0]))
    col2_blocks.sort(key=lambda b: (b[1], b[0]))

    col1_text = normalize_and_dehyphen("\n".join(b[4] for b in col1_blocks))
    col2_text = normalize_and_dehyphen("\n".join(b[4] for b in col2_blocks))

    return full_ref, col1_text, col2_text


def render_clean(page: pymupdf.Page) -> Image.Image:
    """Render clean control page in grayscale at target DPI."""
    zoom = CLEAN_DPI / 72.0
    mat = pymupdf.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=mat)
    return Image.frombytes("RGB", [pix.width, pix.height], pix.samples).convert("L")


def make_scan(page: pymupdf.Page, page_num: int, rng: np.random.Generator) -> Image.Image:
    """Render scan: target DPI, grayscale, rotated by fixed small angle, Gaussian noise, contrast loss."""
    zoom = SCAN_DPI / 72.0
    mat = pymupdf.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=mat)
    img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples).convert("L")

    angle = SCAN_ROTATIONS[page_num]
    # Rotate with white background fill
    img = img.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True, fillcolor=255)

    # Mild Gaussian noise
    arr = np.array(img, dtype=np.float32)
    noise = rng.normal(0, 3.0, size=arr.shape)
    arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr)

    # Slight contrast loss
    img = ImageEnhance.Contrast(img).enhance(0.92)
    return img


def make_photo(page: pymupdf.Page, page_num: int, rng: np.random.Generator) -> Image.Image:
    """
    Render photo: RGB at target DPI, perspective quad warp (simulating smartphone camera angle),
    spatial lighting gradient across the page, and light Gaussian blur.
    """
    zoom = PHOTO_DPI / 72.0
    mat = pymupdf.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=mat)
    img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)

    w, h = img.size

    # Perspective warp: quad transform representing a slight tilt
    dx1 = int(rng.uniform(14, 24))
    dy1 = int(rng.uniform(6, 14))
    dx2 = int(rng.uniform(10, 20))
    dy2 = int(rng.uniform(12, 22))

    quad = [
        dx1, dy1,                                   # top-left
        0, h - dy2,                                 # bottom-left
        w - dx2, h - int(rng.uniform(8, 16)),       # bottom-right
        w - int(rng.uniform(20, 32)), int(rng.uniform(10, 20)),  # top-right
    ]
    warped = img.transform((w, h), Image.Transform.QUAD, quad, Image.Resampling.BICUBIC, fillcolor=(255, 255, 255))

    # Uneven light gradient across the page (brighter top-left, dimmer bottom-right)
    arr = np.array(warped, dtype=np.float32)
    x_grad = np.linspace(1.04, 0.94, w)
    y_grad = np.linspace(1.02, 0.92, h)
    grad = np.outer(y_grad, x_grad)
    if arr.ndim == 3:
        grad = grad[:, :, np.newaxis]
    arr = np.clip(arr * grad, 0, 255).astype(np.uint8)

    # Light blur
    photo = Image.fromarray(arr).filter(ImageFilter.GaussianBlur(radius=0.7))
    return photo


def main():
    root = Path(__file__).resolve().parents[2]
    source_pdf = root / "Benchmarks/GreekLabourCode/pd_62_2025_excerpt.pdf"
    if not source_pdf.is_file():
        sys.exit(f"Source PDF not found at {source_pdf}")

    out_dir = root / "Benchmarks/GreekOCR"
    images_dir = out_dir / "images"
    ref_dir = out_dir / "ref"
    photos_dir = out_dir / "photos"

    images_dir.mkdir(parents=True, exist_ok=True)
    ref_dir.mkdir(parents=True, exist_ok=True)
    photos_dir.mkdir(parents=True, exist_ok=True)

    rng = np.random.default_rng(SEED)
    doc = pymupdf.open(str(source_pdf))

    manifest = {
        "description": "Greek OCR test set from pd_62_2025_excerpt.pdf across clean, scan, and photo versions",
        "source": "Benchmarks/GreekLabourCode/pd_62_2025_excerpt.pdf",
        "pages": PAGES,
        "items": [],
    }

    scan_image_paths = []

    for page_num in PAGES:
        print(f"Processing page {page_num}...")
        page_idx = page_num - 1
        page = doc[page_idx]

        # Reference text
        full_ref, col1_ref, col2_ref = extract_page_reference_and_columns(page)
        ref_file = ref_dir / f"page_{page_num:02d}_ref.txt"
        col1_file = ref_dir / f"page_{page_num:02d}_col1.txt"
        col2_file = ref_dir / f"page_{page_num:02d}_col2.txt"

        ref_file.write_text(full_ref, encoding="utf-8")
        col1_file.write_text(col1_ref, encoding="utf-8")
        col2_file.write_text(col2_ref, encoding="utf-8")

        # 1. Clean
        img_clean = render_clean(page)
        clean_file = images_dir / f"clean_p{page_num:02d}.jpg"
        img_clean.save(str(clean_file), quality=CLEAN_JPEG_QUALITY, optimize=True)

        manifest["items"].append({
            "page": page_num,
            "version": "clean",
            "file": f"images/{clean_file.name}",
            "reference_text_file": f"ref/{ref_file.name}",
            "reference_column_files": [f"ref/{col1_file.name}", f"ref/{col2_file.name}"],
            "rotation_degrees": 0.0,
            "jpeg_quality": CLEAN_JPEG_QUALITY,
            "dpi": CLEAN_DPI,
        })

        # 2. Scan
        img_scan = make_scan(page, page_num, rng)
        scan_file = images_dir / f"scan_p{page_num:02d}.jpg"
        img_scan.save(str(scan_file), quality=SCAN_JPEG_QUALITY, optimize=True)
        scan_image_paths.append((scan_file, SCAN_DPI))

        manifest["items"].append({
            "page": page_num,
            "version": "scan",
            "file": f"images/{scan_file.name}",
            "reference_text_file": f"ref/{ref_file.name}",
            "reference_column_files": [f"ref/{col1_file.name}", f"ref/{col2_file.name}"],
            "rotation_degrees": SCAN_ROTATIONS[page_num],
            "jpeg_quality": SCAN_JPEG_QUALITY,
            "dpi": SCAN_DPI,
        })

        # 3. Photo
        img_photo = make_photo(page, page_num, rng)
        photo_file = images_dir / f"photo_p{page_num:02d}.jpg"
        img_photo.save(str(photo_file), quality=PHOTO_JPEG_QUALITY, optimize=True)

        manifest["items"].append({
            "page": page_num,
            "version": "photo",
            "file": f"images/{photo_file.name}",
            "reference_text_file": f"ref/{ref_file.name}",
            "reference_column_files": [f"ref/{col1_file.name}", f"ref/{col2_file.name}"],
            "rotation_degrees": 0.0,
            "jpeg_quality": PHOTO_JPEG_QUALITY,
            "dpi": PHOTO_DPI,
        })

    # Save manifest.json
    manifest_path = out_dir / "manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    print(f"Manifest written to {manifest_path}")

    # Generate image-only PDF from the 10 scan pages: scan_pages.pdf
    scan_pdf_path = out_dir / "scan_pages.pdf"
    scan_doc = pymupdf.open()
    for img_path, dpi in scan_image_paths:
        with Image.open(img_path) as im:
            w_px, h_px = im.size
        # Standard PDF page rect matching aspect ratio at 72 points per inch
        rect = pymupdf.Rect(0, 0, w_px * 72.0 / dpi, h_px * 72.0 / dpi)
        new_page = scan_doc.new_page(width=rect.width, height=rect.height)
        new_page.insert_image(rect, filename=str(img_path))
    scan_doc.save(str(scan_pdf_path), garbage=4, deflate=True)
    scan_doc.close()
    print(f"Scan PDF written to {scan_pdf_path}")

    # Write README.md in Benchmarks/GreekOCR/
    readme_path = out_dir / "README.md"
    readme_content = f"""# Greek OCR Benchmark Test Set

Generated from `pd_62_2025_excerpt.pdf` (ΦΕΚ Α' 121/2025, Presidential Decree 62/2025 Labour Code).
Includes 10 representative pages spread across the document:
{PAGES}

Total dataset footprint is kept strictly under 15 MB.

## Versions
- **clean**: Rendered in grayscale at {CLEAN_DPI} DPI, JPEG quality {CLEAN_JPEG_QUALITY} with optimization (un-degraded control).
- **scan**: Rendered in grayscale at {SCAN_DPI} DPI, rotated by fixed small angles per page (between −1.5° and +1.5°), mild Gaussian noise, slight contrast loss, JPEG quality {SCAN_JPEG_QUALITY}.
- **photo**: Rendered in color at {PHOTO_DPI} DPI, perspective quad warp (simulating smartphone tilt), spatial lighting gradient across the page, light blur, JPEG quality {PHOTO_JPEG_QUALITY}.
- **photos/**: Real-world user photos matching `p<page>_<n>.jpg`.

## Files
- `manifest.json`: Full metadata for each benchmark sample (page number, version, image path, reference text path, rotation angle, dpi, JPEG quality).
- `images/`: The 30 generated JPEG page images.
- `ref/`: The reference text files extracted from the PDF text layer with joined line-end hyphens and NFKC normalization.
- `scan_pages.pdf`: 10-page image-only PDF composed of the scan pages, used for whole-document ingestion testing.
"""
    readme_path.write_text(readme_content, encoding="utf-8")
    print(f"README written to {readme_path}")

    # Write photos/README.md
    photos_readme = photos_dir / "README.md"
    photos_readme_content = """# Owner Photos for Greek OCR Benchmark

Place real phone photographs of printed pages from `pd_62_2025_excerpt.pdf` in this directory.

## Naming convention:
`p<page>_<n>.jpg`

Where:
- `<page>` is the 1-indexed page number of the excerpt (e.g., `p04_1.jpg`, `p12_1.jpg`).
- `<n>` is an index for multiple photos of the same page.

Any JPEG file matching this pattern will automatically be evaluated against the reference text for that page by `GreekOCRBenchmarkTests.swift`.
"""
    photos_readme.write_text(photos_readme_content, encoding="utf-8")
    print(f"Photos README written to {photos_readme}")

    # Total size check
    total_bytes = sum(f.stat().st_size for f in out_dir.rglob("*") if f.is_file())
    print(f"Total directory size: {total_bytes / (1024 * 1024):.2f} MB")


if __name__ == "__main__":
    main()
