# Greek OCR Benchmark Test Set

Generated from `pd_62_2025_excerpt.pdf` (ΦΕΚ Α' 121/2025, Presidential Decree 62/2025 Labour Code).
Includes 10 representative pages spread across the document:
[1, 4, 8, 12, 16, 20, 24, 28, 32, 36]

Total dataset footprint is kept strictly under 15 MB.

## Versions
- **clean**: Rendered in grayscale at 200 DPI, JPEG quality 40 with optimization (un-degraded control).
- **scan**: Rendered in grayscale at 180 DPI, rotated by fixed small angles per page (between −1.5° and +1.5°), mild Gaussian noise, slight contrast loss, JPEG quality 45.
- **photo**: Rendered in color at 200 DPI, perspective quad warp (simulating smartphone tilt), spatial lighting gradient across the page, light blur, JPEG quality 55.
- **photos/**: Real-world user photos matching `p<page>_<n>.jpg`.

## Files
- `manifest.json`: Full metadata for each benchmark sample (page number, version, image path, reference text path, rotation angle, dpi, JPEG quality).
- `images/`: The 30 generated JPEG page images.
- `ref/`: The reference text files extracted from the PDF text layer with joined line-end hyphens and NFKC normalization.
- `scan_pages.pdf`: 10-page image-only PDF composed of the scan pages, used for whole-document ingestion testing.
