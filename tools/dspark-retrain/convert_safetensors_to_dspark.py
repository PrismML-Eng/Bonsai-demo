#!/usr/bin/env python3
"""
Convert RadixArk/Qwen3.8-27B-DSpark (safetensors) into a raw dspark GGUF.
Then gguf_dspark_to_dflash.py converts it to the final dflash format.

Every tensor in the name map is required. When one is missing, the script raises
ValueError before it opens the output file, and the command exits with status 1.
"""

import sys, os
import numpy as np
import torch
from safetensors import safe_open

# gguf-py from the llama.cpp clone in the demo checkout (BONSAI_ROOT, default: two
# levels above this file)
BONSAI_ROOT = os.environ.get("BONSAI_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(BONSAI_ROOT, "llama.cpp", "gguf-py"))
from gguf import GGUFWriter


def build_name_map():
    # Tensor mapping to legacy dspark names
    name_map = {
        "fc.weight": "dspark.fc.weight",
        "hidden_norm.weight": "dspark.hidden_norm.weight",
        "norm.weight": "output_norm.weight",
        "markov_head.markov_w1.weight": "dspark.markov_head_a.weight",
        "markov_head.markov_w2.weight": "dspark.markov_head_b.weight",
        "confidence_head.proj.weight": "dspark.confidence_head.weight",
        "confidence_head.proj.bias": "dspark.confidence_head.bias",
    }

    for i in range(5):
        name_map[f"layers.{i}.input_layernorm.weight"] = f"blk.{i}.attn_norm.weight"
        name_map[f"layers.{i}.self_attn.q_proj.weight"] = f"blk.{i}.attn_q.weight"
        name_map[f"layers.{i}.self_attn.k_proj.weight"] = f"blk.{i}.attn_k.weight"
        name_map[f"layers.{i}.self_attn.v_proj.weight"] = f"blk.{i}.attn_v.weight"
        name_map[f"layers.{i}.self_attn.o_proj.weight"] = f"blk.{i}.attn_output.weight"
        name_map[f"layers.{i}.self_attn.q_norm.weight"] = f"blk.{i}.attn_q_norm.weight"
        name_map[f"layers.{i}.self_attn.k_norm.weight"] = f"blk.{i}.attn_k_norm.weight"
        name_map[f"layers.{i}.post_attention_layernorm.weight"] = f"blk.{i}.ffn_norm.weight"
        name_map[f"layers.{i}.mlp.gate_proj.weight"] = f"blk.{i}.ffn_gate.weight"
        name_map[f"layers.{i}.mlp.up_proj.weight"] = f"blk.{i}.ffn_up.weight"
        name_map[f"layers.{i}.mlp.down_proj.weight"] = f"blk.{i}.ffn_down.weight"
    return name_map


def convert_to_dspark(safetensors_path, output_gguf_path):
    name_map = build_name_map()

    print(f"Reading {safetensors_path}...")
    with safe_open(safetensors_path, framework="pt") as f:
        st_keys = set(f.keys())
        # A missing tensor is an error: a GGUF without it is not a valid drafter, and
        # the size check of the pipeline can not detect it.
        missing = [k for k in name_map if k not in st_keys]
        if missing:
            raise ValueError(
                f"{safetensors_path}: {len(missing)} of {len(name_map)} required tensors are missing: "
                + ", ".join(missing)
            )

        writer = GGUFWriter(output_gguf_path, "dspark")

        # Architecture metadata
        writer.add_name("Qwen3.8-27B-DSpark")
        writer.add_type("model")
        writer.add_size_label("1.86B")
        writer.add_quantization_version(2)
        writer.add_file_type(32) # BF16

        # DSpark hyperparameters from config.json
        writer.add_uint32("dspark.block_count", 5)
        writer.add_uint32("dspark.context_length", 262144)
        writer.add_uint32("dspark.embedding_length", 5120)
        writer.add_uint32("dspark.feed_forward_length", 17408)
        writer.add_uint32("dspark.attention.head_count", 32)
        writer.add_uint32("dspark.attention.head_count_kv", 8)
        writer.add_float32("dspark.rope.freq_base", 10000000.0)
        writer.add_float32("dspark.attention.layer_norm_rms_epsilon", 1e-06)
        writer.add_uint32("dspark.attention.key_length", 128)
        writer.add_uint32("dspark.attention.value_length", 128)
        writer.add_uint32("dspark.block_size", 7)
        writer.add_array("dspark.target_layers", [5, 19, 33, 47, 61])
        writer.add_uint32("dspark.markov_rank", 256)
        writer.add_bool("dspark.confidence_head", True)
        writer.add_bool("dspark.confidence_head_with_markov", True)
        writer.add_uint32("dspark.vocab_size", 248320)

        # Stub tokenizer for legacy dspark format (gguf_dspark_to_dflash injects real donor vocab)
        writer.add_string("tokenizer.ggml.model", "none")
        writer.add_uint32("dspark.dspark.mask_token_id", 248070)

        print(f"Mapping {len(name_map)} tensors...")
        for st_name, gguf_name in name_map.items():
            t = f.get_tensor(st_name)
            t_np = t.contiguous().to(dtype=t.dtype if t.dtype != torch.bfloat16 else torch.float32).cpu().numpy()
            writer.add_tensor(gguf_name, t_np)

    print(f"Writing GGUF output to {output_gguf_path}...")
    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_tensors_to_file()
    writer.close()
    print("Raw dspark GGUF written successfully!")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: convert_safetensors_to_dspark.py <in.safetensors> <out-dspark-raw.gguf>", file=sys.stderr)
        sys.exit(1)
    try:
        convert_to_dspark(sys.argv[1], sys.argv[2])
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
