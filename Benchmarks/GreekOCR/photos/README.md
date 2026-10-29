# Owner Photos for Greek OCR Benchmark

Place real phone photographs of printed pages from `pd_62_2025_excerpt.pdf` in this directory.

## Naming convention:
`p<page>_<n>.jpg`

Where:
- `<page>` is the 1-indexed page number of the excerpt (e.g., `p04_1.jpg`, `p12_1.jpg`).
- `<n>` is an index for multiple photos of the same page.

Any JPEG file matching this pattern will automatically be evaluated against the reference text for that page by `GreekOCRBenchmarkTests.swift`.
