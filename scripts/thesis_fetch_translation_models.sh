#!/bin/bash
# Thesis fork: downloads Helsinki-NLP/opus-mt-tc-big-el-en and opus-mt-tc-big-en-el from Hugging Face, converts
# them to INT8 ONNX with a decoder key/value cache (scripts/thesis/convert_opus_mt.py) and puts them in
# OpenIntelligence/Resources/MLModels/Translation/, which git ignores (about 730 MB).
# Needs python3 and about 2 GB for the temporary virtual environment and PyTorch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${THESIS_MODEL_WORK:-$(mktemp -d)}"
OUT="$ROOT/OpenIntelligence/Resources/MLModels/Translation"
mkdir -p "$OUT" "$WORK/dl"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install -q torch transformers sentencepiece onnx onnxruntime sacremoses
for m in tc-big-el-en tc-big-en-el; do
  d="$WORK/dl/opus-mt-$m"; mkdir -p "$d"
  for f in config.json generation_config.json pytorch_model.bin source.spm target.spm tokenizer_config.json vocab.json special_tokens_map.json; do
    # Not every model has every file; curl -f writes nothing for a missing one.
    curl -sfL -o "$d/$f" "https://huggingface.co/Helsinki-NLP/opus-mt-$m/resolve/main/$f" || true
  done
  "$WORK/venv/bin/python" -I "$ROOT/scripts/thesis/convert_opus_mt.py" "$d" "$OUT" "opus-mt-$m"
done
ls -la "$OUT"
