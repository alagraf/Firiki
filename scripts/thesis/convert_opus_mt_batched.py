# Thesis fork: exports a Helsinki-NLP Opus-MT Marian model for LocalNeuralTranslator.swift as INT8
# ONNX, with a key/value cache for the decoder:
#   <prefix>_encoder.onnx        input_ids, attention_mask -> last_hidden_state
#   <prefix>_decoder_cross.onnx  encoder_hidden_states -> cross_{key,value}_<layer>
#   <prefix>_decoder_step.onnx   decoder_input_ids [B,1], encoder_attention_mask [B,S],
#                                past_{key,value}_<layer>, cross_* -> logits [B,V], present_{key,value}_<layer>
#   <prefix>_tokenizer.json      source SentencePiece pieces and scores, Marian vocabulary, special ids
# The step graph is the Marian decoder written out for one token (post-layer-norm blocks, sinusoidal
# positions, tied output layer), so each generated token costs one token's work; its greedy output
# was checked token for token against transformers' generate(). Every graph takes a batch of B
# sentences: shorter ones are padded and the encoder mask keeps cross-attention off the padding, so
# B sentences share each read of the decoder's weights (decoding one token is mostly memory reads).
# Thesis fork, experiment only (FORK_CHANGES 2.11.17): the app ships the one-sentence export of
# convert_opus_mt.py. Batches changed the INT8 translations and cost accuracy, and this step graph
# ran 2.7x slower than the one-sentence graph at batch 1 in the app.
# Usage: python convert_opus_mt_batched.py <hf-model-dir> <out-dir> <prefix>
import sys, json, os, torch, torch.nn as nn, sentencepiece as spm
from transformers import MarianMTModel, MarianTokenizer
from onnxruntime.quantization import quantize_dynamic, QuantType

src_dir, out_dir, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out_dir, exist_ok=True)
model = MarianMTModel.from_pretrained(src_dir).eval()
# Marian ties its output layer to the shared embeddings. Some checkpoints (opus-mt-tc-big-*) also
# store an lm_head with other values, which newer transformers keeps untied: the model then
# produces garbage. Tie it as the architecture intends.
model.lm_head.weight = model.model.shared.weight
# tc-big checkpoints are float16; quantization needs float32 weights and activations.
model = model.float()
for p in model.parameters():
    p.requires_grad_(False)
tok = MarianTokenizer.from_pretrained(src_dir)
cfg = model.config
L = cfg.decoder_layers
H = cfg.decoder_attention_heads
D = cfg.d_model // H
ACT = {"relu": torch.relu, "swish": nn.functional.silu, "silu": nn.functional.silu, "gelu": nn.functional.gelu}[cfg.activation_function]


def split(x):  # [B, T, d_model] -> [B, H, T, D]
    return x.view(x.shape[0], -1, H, D).transpose(1, 2)


class Encoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.m = model

    def forward(self, input_ids, attention_mask):
        return self.m.model.encoder(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state


class Cross(nn.Module):
    """Encoder output -> each decoder layer's cross-attention keys and values, once per sentence."""
    def __init__(self):
        super().__init__()
        self.m = model  # a submodule, so its weights are exported once, as initializers

    def forward(self, enc):
        out = []
        for layer in self.m.model.decoder.layers:
            out += [split(layer.encoder_attn.k_proj(enc)), split(layer.encoder_attn.v_proj(enc))]
        return tuple(out)


class Step(nn.Module):
    """One decoder token for each of B sentences with the cache. All sentences are at the same step,
    so self-attention needs no mask; cross-attention skips the padding of shorter sentences."""
    def __init__(self):
        super().__init__()
        self.m = model

    def forward(self, ids, enc_mask, *kv):
        dec = self.m.model.decoder
        past, cross = kv[: 2 * L], kv[2 * L:]
        b, t = ids.shape[0], past[0].shape[2]
        # [B, S] 1/0 -> [B, 1, 1, S] additive: padding gets -1e9, so softmax gives it no weight.
        pad = (1.0 - enc_mask.to(torch.float32)).view(b, 1, 1, -1) * -1e9
        h = dec.embed_tokens(ids) * dec.embed_scale + dec.embed_positions.weight[t].view(1, 1, -1)
        present = []
        for i, layer in enumerate(dec.layers):
            sa = layer.self_attn
            q = split(sa.q_proj(h)) * (D ** -0.5)
            k = torch.cat([past[2 * i], split(sa.k_proj(h))], dim=2)
            v = torch.cat([past[2 * i + 1], split(sa.v_proj(h))], dim=2)
            present += [k, v]
            att = torch.softmax(q @ k.transpose(-1, -2), dim=-1) @ v
            h = layer.self_attn_layer_norm(h + sa.out_proj(att.transpose(1, 2).reshape(b, 1, -1)))
            ca = layer.encoder_attn
            q = split(ca.q_proj(h)) * (D ** -0.5)
            att = torch.softmax(q @ cross[2 * i].transpose(-1, -2) + pad, dim=-1) @ cross[2 * i + 1]
            h = layer.encoder_attn_layer_norm(h + ca.out_proj(att.transpose(1, 2).reshape(b, 1, -1)))
            h = layer.final_layer_norm(h + layer.fc2(ACT(layer.fc1(h))))
        logits = self.m.lm_head(h[:, -1, :]) + self.m.final_logits_bias
        return (logits, *present)


sample = tok(["Δοκιμή κειμένου για εξαγωγή. Test text for export.", "Δεύτερη πρόταση."], return_tensors="pt", padding=True)
cross_names = [f"cross_{k}_{i}" for i in range(L) for k in ("key", "value")]
past_names = [f"past_{k}_{i}" for i in range(L) for k in ("key", "value")]
present_names = [f"present_{k}_{i}" for i in range(L) for k in ("key", "value")]
with torch.no_grad():
    enc = Encoder()(sample.input_ids, sample.attention_mask)
    cross = Cross()(enc)
    past = tuple(torch.zeros(2, H, 2, D) for _ in range(2 * L))
    torch.onnx.export(Encoder(), (sample.input_ids, sample.attention_mask), f"{out_dir}/{prefix}_encoder.fp32.onnx",
        input_names=["input_ids", "attention_mask"], output_names=["last_hidden_state"],
        dynamic_axes={"input_ids": {0: "b", 1: "s"}, "attention_mask": {0: "b", 1: "s"}, "last_hidden_state": {0: "b", 1: "s"}},
        opset_version=17, dynamo=False)
    torch.onnx.export(Cross(), (enc,), f"{out_dir}/{prefix}_decoder_cross.fp32.onnx",
        input_names=["encoder_hidden_states"], output_names=cross_names,
        dynamic_axes={"encoder_hidden_states": {0: "b", 1: "s"}, **{n: {0: "b", 2: "s"} for n in cross_names}}, opset_version=17, dynamo=False)
    torch.onnx.export(Step(), (torch.tensor([[cfg.decoder_start_token_id]] * 2), sample.attention_mask, *past, *cross),
        f"{out_dir}/{prefix}_decoder_step.fp32.onnx",
        input_names=["decoder_input_ids", "encoder_attention_mask", *past_names, *cross_names], output_names=["logits", *present_names],
        dynamic_axes={"decoder_input_ids": {0: "b"}, "encoder_attention_mask": {0: "b", 1: "s"}, "logits": {0: "b"},
                      **{n: {0: "b", 2: "t"} for n in past_names}, **{n: {0: "b", 2: "s"} for n in cross_names},
                      **{n: {0: "b", 2: "t1"} for n in present_names}},
        opset_version=17, dynamo=False)
for part in ["encoder", "decoder_cross", "decoder_step"]:
    quantize_dynamic(f"{out_dir}/{prefix}_{part}.fp32.onnx", f"{out_dir}/{prefix}_{part}.onnx", weight_type=QuantType.QInt8)
    os.remove(f"{out_dir}/{prefix}_{part}.fp32.onnx")

# Tokenizer data for Swift: source pieces with scores, shared vocab, special ids, decoder shape.
sp = spm.SentencePieceProcessor(model_file=f"{src_dir}/source.spm")
pieces = [[sp.id_to_piece(i), sp.get_score(i)] for i in range(sp.get_piece_size())]
vocab = json.load(open(f"{src_dir}/vocab.json"))
meta = {"pad_id": cfg.pad_token_id, "eos_id": cfg.eos_token_id, "unk_id": vocab.get("<unk>"),
        "decoder_start_token_id": cfg.decoder_start_token_id, "max_length": 512, "vocab_size": cfg.vocab_size,
        "decoder_layers": L, "attention_heads": H, "head_dim": D}
json.dump({"source_pieces": pieces, "vocab": vocab, "meta": meta}, open(f"{out_dir}/{prefix}_tokenizer.json", "w"), ensure_ascii=False)
print(prefix, meta, len(pieces), len(vocab))
