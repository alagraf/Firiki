# Five-document Greek labour-law library

Test data for the PoC capabilities in `Docs/Thesis/plans/greek-legaltech-progress.md` ("PoC
capabilities"): Q&A over five documents, summary of one document, and a legal opinion drawn from
several. Nothing here is read by the app.

All five are Greek labour law (the owner's requirement). The Labour Code is the base text; the
other four came after it and amend or apply it, so a correct answer sometimes has to say which
version of an article applies.

| Document | File | Pages | Bytes | sha1 |
|---|---|---|---|---|
| Π.Δ. 62/2025 «Κώδικας Εργατικού Δικαίου», ΦΕΚ Α' 121/11.07.2025 | `../GreekLabourCode/pd_62_2025_fek_a121.pdf` | 260 | 2,488,180 | `03039d0415d086e1405ec7662e1cba38509fccaf` |
| Ν. 5239/2025 «Δίκαιη Εργασία για Όλους…», ΦΕΚ Α' 178/17.10.2025 | `n_5239_2025_fek_a178.pdf` | 104 | 4,442,802 | `8f5cf1cddbe8be1f1547742e0612b29b85fdfeab` |
| Ν. 5278/2026 «Εθνική Κοινωνική Συμφωνία για την ενίσχυση των Συλλογικών Συμβάσεων Εργασίας», ΦΕΚ Α' 22/16.02.2026 | `n_5278_2026_fek_a22.pdf` | 14 | 695,561 | `ff2e850af2dccdaff992d11571f9ccd5fa05444a` |
| Ν. 5316/2026 ισότητα αμοιβής ανδρών και γυναικών, ενσωμάτωση Οδηγίας (ΕΕ) 2023/970, ΦΕΚ Α' 105/06.07.2026 | `n_5316_2026_fek_a105.pdf` | 34 | 816,013 | `e87bf09a32ff051307596d901c8af628d6953f0f` |
| Υ.Α. 8934/2026 νομοθετημένος κατώτατος μισθός και ημερομίσθιο (από 1.4.2026), ΦΕΚ Β' 1759/27.03.2026 | `ya_8934_2026_fek_b1759.pdf` | 4 | 726,053 | `459f9af964658c6e5f87682a1e4bc65509887c5e` |

Source: the Government Gazette's official files from the National Printing Office
(search.et.gr, download link `ia37rg02wpsa01.blob.core.windows.net/fek/…`), downloaded unchanged on
2026-10-29 with the owner's approval of each file. Every file has a text layer.

Only the full Labour Code is in this library, not the 37-page excerpt. Ν. 5316/2026 transposes
Directive (EU) 2023/970, which is not in the EU holdout (checked by counting "2023/970" in
`eu_data.json`, without reading the holdout's questions or answers).
