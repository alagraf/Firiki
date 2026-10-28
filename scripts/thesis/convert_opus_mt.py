# Thesis fork: exports a Helsinki-NLP Opus-MT Marian model to ONNX (encoder; decoder with LM head,
# last position only) quantized to INT8, plus a JSON tokenizer file (source SentencePiece pieces and
# scores, Marian vocabulary, special ids) for LocalNeuralTranslator.swift.
# Usage: python convert_opus_mt.py <hf-model-dir> <out-dir> <prefix>

import sys, json, os, torch, sentencepiece as spm
from transformers import MarianMTModel, MarianTokenizer
from onnxruntime.quantization import quantize_dynamic, QuantType
src_dir, out_dir, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out_dir, exist_ok=True)
model = MarianMTModel.from_pretrained(src_dir).eval()
tok = MarianTokenizer.from_pretrained(src_dir)
cfg = model.config
class Enc(torch.nn.Module):
    def __init__(s, m): super().__init__(); s.e = m.get_encoder()
    def forward(s, input_ids, attention_mask): return s.e(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state
class Dec(torch.nn.Module):
    def __init__(s, m): super().__init__(); s.d = m.get_decoder(); s.h = m.lm_head; s.b = m.final_logits_bias
    def forward(s, decoder_input_ids, encoder_hidden_states, encoder_attention_mask):
        o = s.d(input_ids=decoder_input_ids, encoder_hidden_states=encoder_hidden_states, encoder_attention_mask=encoder_attention_mask, use_cache=False).last_hidden_state
        return s.h(o[:, -1, :]) + s.b
ids = tok(["Δοκιμή κειμένου."], return_tensors="pt")
with torch.no_grad():
    hid = Enc(model)(ids.input_ids, ids.attention_mask)
    torch.onnx.export(Enc(model), (ids.input_ids, ids.attention_mask), f"{out_dir}/{prefix}_encoder.fp32.onnx",
        input_names=["input_ids","attention_mask"], output_names=["last_hidden_state"],
        dynamic_axes={"input_ids":{0:"b",1:"s"},"attention_mask":{0:"b",1:"s"},"last_hidden_state":{0:"b",1:"s"}}, opset_version=17, dynamo=False)
    dec_ids = torch.tensor([[cfg.decoder_start_token_id, 5]])
    torch.onnx.export(Dec(model), (dec_ids, hid, ids.attention_mask), f"{out_dir}/{prefix}_decoder.fp32.onnx",
        input_names=["decoder_input_ids","encoder_hidden_states","encoder_attention_mask"], output_names=["logits"],
        dynamic_axes={"decoder_input_ids":{0:"b",1:"t"},"encoder_hidden_states":{0:"b",1:"s"},"encoder_attention_mask":{0:"b",1:"s"},"logits":{0:"b"}}, opset_version=17, dynamo=False)
for part in ["encoder","decoder"]:
    quantize_dynamic(f"{out_dir}/{prefix}_{part}.fp32.onnx", f"{out_dir}/{prefix}_{part}.onnx", weight_type=QuantType.QInt8)
    os.remove(f"{out_dir}/{prefix}_{part}.fp32.onnx")
# Tokenizer data for Swift: source pieces with scores, shared vocab, special ids.
sp = spm.SentencePieceProcessor(model_file=f"{src_dir}/source.spm")
pieces = [[sp.id_to_piece(i), sp.get_score(i)] for i in range(sp.get_piece_size())]
vocab = json.load(open(f"{src_dir}/vocab.json"))
meta = {"pad_id": cfg.pad_token_id, "eos_id": cfg.eos_token_id, "unk_id": vocab.get("<unk>"),
        "decoder_start_token_id": cfg.decoder_start_token_id, "max_length": 512, "vocab_size": cfg.vocab_size}
json.dump({"source_pieces": pieces, "vocab": vocab, "meta": meta}, open(f"{out_dir}/{prefix}_tokenizer.json","w"), ensure_ascii=False)
print(prefix, meta, len(pieces), len(vocab))
