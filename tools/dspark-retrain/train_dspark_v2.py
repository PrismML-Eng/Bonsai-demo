#!/usr/bin/env python3
"""
train_dspark_v2.py - real DSpark speculative-drafter trainer for Bonsai 2.

This is the v2 rewrite of the DSpark drafter trainer. The v1 trainer
(train_bonsai2_dflash.py, not included here) uses a degenerate objective: it regresses the
target's same-position layer-62 hidden state with cosine + MSE, with the target
present in its own input. There is no next-token prediction, no shift, no
LM-head cross-entropy, and no block rollout. Acceptance stalls at 12-30%.

This file implements the real DSpark block-parallel objective, ported from the
SpecForge reference (specforge/algorithms/common/dflash_family_model.py and
specforge/modeling/draft/dspark.py). The training forward mirrors the llama.cpp
runtime path (src/models/dflash.cpp):

  ENCODER  : the 5 target taps -> fc -> hidden_norm produce a per-token context.
             Each draft layer projects that SAME context through k_proj/v_proj
             (no per-layer input_layernorm) to form the draft K/V, exactly like
             the runtime's embd-batch KV injection.
  DECODER  : a Qwen3-style transformer runs over the [anchor, mask x (B-1)]
             noise-token embeddings (from tok_embd, mask_token_id=248070). Each
             noise query attends to (a) context features strictly before its
             anchor and (b) the noise positions of its own block, matching the
             runtime's token-batch non-causal attention over the KV cache.
  HEAD     : each block hidden state is projected through the borrowed target
             LM head W_lm, then biased by the DSpark Markov head.

Loss (defaults 0.1*CE + 0.9*L1 + 1.0*confBCE), token-normalized over eval_mask:
  CE   : F.cross_entropy(draft_logits, target_ids) masked by eval_mask.
  L1   : teacher_probs = softmax(aligned_target_hidden @ W_lm.T);
         draft_probs   = softmax(draft_logits);
         l1_per_token  = |draft_probs - teacher_probs|.sum(-1);
         accept_prob   = (1 - 0.5*l1).clamp(0, 1).
  conf : confidence head predicts accept_prob (detached) via BCE-with-logits.

The saved safetensors uses the SpecForge tensor names, so the existing GGUF
converter (convert_safetensors_to_dspark.py, in this directory) consumes it unchanged.

Run a shape/loss dry-run on a synthetic fixture (no real data needed):
    python3 train_dspark_v2.py --dry-run

Launch full training once the real v2 features and teacher files exist (paths
relative to the demo checkout, BONSAI_ROOT):
    python3 tools/dspark-retrain/train_dspark_v2.py \
        --feats-dir tools/dspark-retrain/feats \
        --teacher-dir tools/dspark-retrain/teacher \
        --warm-start models/qwen38-dspark/model.safetensors \
        --out models/bonsai2-dspark/bonsai2_dspark_v2.safetensors \
        --epochs 2 --batch-size 2 --lr 1e-4
"""

from __future__ import annotations

import argparse
import glob
import math
import os
import struct
import sys
import time
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset

# Default paths: BONSAI_ROOT is the demo checkout (default: two levels above this
# file); work products (features, teacher tensors) live next to this file.
HERE = os.path.dirname(os.path.abspath(__file__))
BONSAI_ROOT = os.environ.get("BONSAI_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))

# ---------------------------------------------------------------------------
# Constants from the Bonsai 2 / Qwen3.8-27B-DSpark config
# ---------------------------------------------------------------------------
MASK_TOKEN_ID = 248070          # dflash_config.mask_token_id
DEFAULT_VOCAB = 248320
DEFAULT_EMBD = 5120
DEFAULT_TAPS = 5
DEFAULT_BLOCK_SIZE = 7          # dflash.block_size in the GGUF metadata


@dataclass
class ModelConfig:
    """Architecture hyperparameters. Defaults match Bonsai 2 27B-DSpark."""

    hidden_size: int = DEFAULT_EMBD
    n_taps: int = DEFAULT_TAPS
    n_layers: int = 5
    num_heads: int = 32
    num_kv_heads: int = 8
    head_dim: int = 128
    intermediate_size: int = 17408
    vocab_size: int = DEFAULT_VOCAB
    markov_rank: int = 256
    block_size: int = DEFAULT_BLOCK_SIZE
    mask_token_id: int = MASK_TOKEN_ID
    rms_eps: float = 1e-6
    # RoPE (Qwen3 YaRN). rope_theta and the yarn schedule come from config.json.
    rope_theta: float = 10000000.0
    rope_yarn: bool = True
    yarn_factor: float = 32.0
    yarn_orig_max_pos: int = 8192
    beta_fast: float = 32.0
    beta_slow: float = 1.0


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------
class RMSNorm(nn.Module):
    def __init__(self, dim: int, eps: float = 1e-6):
        super().__init__()
        self.eps = eps
        self.weight = nn.Parameter(torch.ones(dim))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        in_dtype = x.dtype
        x = x.float()
        norm = torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + self.eps)
        return (x * norm).to(in_dtype) * self.weight


def _rotate_half(x: torch.Tensor) -> torch.Tensor:
    x1, x2 = x.chunk(2, dim=-1)
    return torch.cat((-x2, x1), dim=-1)


def _apply_rope(x: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor) -> torch.Tensor:
    # x: [B, heads, S, head_dim]; cos/sin: [B, S, head_dim]
    cos = cos.unsqueeze(1)
    sin = sin.unsqueeze(1)
    return (x.float() * cos + _rotate_half(x.float()) * sin).to(x.dtype)


class YarnRotaryEmbedding(nn.Module):
    """Qwen3 rotary embedding with optional YaRN scaling (HF-compatible)."""

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        dim = cfg.head_dim
        base = cfg.rope_theta
        if not cfg.rope_yarn:
            inv_freq = 1.0 / (base ** (torch.arange(0, dim, 2, dtype=torch.float32) / dim))
            attention_factor = 1.0
        else:
            inv_freq, attention_factor = self._yarn(cfg, dim, base)
        self.attention_scaling = float(attention_factor)
        self.register_buffer("inv_freq", inv_freq, persistent=False)

    @staticmethod
    def _yarn(cfg: ModelConfig, dim: int, base: float):
        factor = cfg.yarn_factor
        orig_max = cfg.yarn_orig_max_pos
        beta_fast, beta_slow = cfg.beta_fast, cfg.beta_slow
        # HF default attention (mscale) factor for yarn.
        attention_factor = 0.1 * math.log(factor) + 1.0

        def find_dim(num_rotations):
            return (dim * math.log(orig_max / (num_rotations * 2 * math.pi))) / (
                2 * math.log(base)
            )

        low = math.floor(find_dim(beta_fast))
        high = math.ceil(find_dim(beta_slow))
        low = max(low, 0)
        high = min(high, dim - 1)

        pos_freqs = base ** (torch.arange(0, dim, 2, dtype=torch.float32) / dim)
        inv_freq_extrapolation = 1.0 / pos_freqs
        inv_freq_interpolation = 1.0 / (factor * pos_freqs)

        # linear ramp over [low, high]
        idx = torch.arange(dim // 2, dtype=torch.float32)
        ramp = (idx - low) / max(high - low, 1e-3)
        ramp = ramp.clamp(0.0, 1.0)
        inv_freq_extrapolation_factor = 1.0 - ramp
        inv_freq = (
            inv_freq_interpolation * (1.0 - inv_freq_extrapolation_factor)
            + inv_freq_extrapolation * inv_freq_extrapolation_factor
        )
        return inv_freq, attention_factor

    @torch.no_grad()
    def forward(self, position_ids: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        # position_ids: [B, S]
        inv = self.inv_freq.to(position_ids.device)
        freqs = position_ids.float().unsqueeze(-1) * inv.view(1, 1, -1)  # [B, S, dim/2]
        emb = torch.cat((freqs, freqs), dim=-1)  # [B, S, dim]
        cos = emb.cos() * self.attention_scaling
        sin = emb.sin() * self.attention_scaling
        return cos, sin


class DSparkAttention(nn.Module):
    """GQA attention over the family's context-then-noise KV layout.

    q comes from the noise hidden states. k/v are the concat of the encoded
    context (projected once, no per-layer norm) and the noise. A boolean mask
    (True = attend) restricts each noise query to its allowed context/noise.
    """

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.num_heads = cfg.num_heads
        self.num_kv_heads = cfg.num_kv_heads
        self.head_dim = cfg.head_dim
        self.scaling = self.head_dim ** -0.5
        self.q_proj = nn.Linear(cfg.hidden_size, self.num_heads * self.head_dim, bias=False)
        self.k_proj = nn.Linear(cfg.hidden_size, self.num_kv_heads * self.head_dim, bias=False)
        self.v_proj = nn.Linear(cfg.hidden_size, self.num_kv_heads * self.head_dim, bias=False)
        self.o_proj = nn.Linear(self.num_heads * self.head_dim, cfg.hidden_size, bias=False)
        self.q_norm = RMSNorm(self.head_dim, cfg.rms_eps)
        self.k_norm = RMSNorm(self.head_dim, cfg.rms_eps)

    def forward(
        self,
        noise: torch.Tensor,          # [B, Q, H]  (post input_layernorm)
        context: torch.Tensor,        # [B, S, H]  (encoder output, raw)
        cos_full: torch.Tensor,       # [B, S+Q, head_dim]  (context-then-noise)
        sin_full: torch.Tensor,
        attn_mask: torch.Tensor,      # [B, 1, Q, S+Q] bool, True = attend
    ) -> torch.Tensor:
        B, Q, _ = noise.shape
        S = context.shape[1]

        q = self.q_proj(noise).view(B, Q, self.num_heads, self.head_dim)
        q = self.q_norm(q).transpose(1, 2)  # [B, nH, Q, hd]

        k_ctx = self.k_proj(context)
        k_noise = self.k_proj(noise)
        k = torch.cat([k_ctx, k_noise], dim=1).view(B, S + Q, self.num_kv_heads, self.head_dim)
        v_ctx = self.v_proj(context)
        v_noise = self.v_proj(noise)
        v = torch.cat([v_ctx, v_noise], dim=1).view(B, S + Q, self.num_kv_heads, self.head_dim)
        k = self.k_norm(k).transpose(1, 2)  # [B, nKV, S+Q, hd]
        v = v.transpose(1, 2)

        # RoPE: queries at noise positions, keys over context-then-noise.
        cos_q, sin_q = cos_full[:, S:], sin_full[:, S:]
        q = _apply_rope(q, cos_q, sin_q)
        k = _apply_rope(k, cos_full, sin_full)

        # GQA repeat
        if self.num_heads != self.num_kv_heads:
            rep = self.num_heads // self.num_kv_heads
            k = k.repeat_interleave(rep, dim=1)
            v = v.repeat_interleave(rep, dim=1)

        # Guard fully-masked query rows (invalid blocks) against NaN. Those
        # tokens carry loss weight 0, so their finite garbage never affects grads.
        safe_mask = attn_mask | (~attn_mask.any(dim=-1, keepdim=True))
        out = F.scaled_dot_product_attention(q, k, v, attn_mask=safe_mask, scale=self.scaling)
        out = out.transpose(1, 2).contiguous().view(B, Q, -1)
        return self.o_proj(out)


class DSparkMLP(nn.Module):
    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.gate_proj = nn.Linear(cfg.hidden_size, cfg.intermediate_size, bias=False)
        self.up_proj = nn.Linear(cfg.hidden_size, cfg.intermediate_size, bias=False)
        self.down_proj = nn.Linear(cfg.intermediate_size, cfg.hidden_size, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.down_proj(F.silu(self.gate_proj(x)) * self.up_proj(x))


class DSparkDecoderLayer(nn.Module):
    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.input_layernorm = RMSNorm(cfg.hidden_size, cfg.rms_eps)
        self.self_attn = DSparkAttention(cfg)
        self.post_attention_layernorm = RMSNorm(cfg.hidden_size, cfg.rms_eps)
        self.mlp = DSparkMLP(cfg)

    def forward(self, noise, context, cos_full, sin_full, attn_mask):
        residual = noise
        x = self.input_layernorm(noise)
        x = self.self_attn(x, context, cos_full, sin_full, attn_mask)
        noise = residual + x
        residual = noise
        x = self.post_attention_layernorm(noise)
        x = self.mlp(x)
        return residual + x


class VanillaMarkovHead(nn.Module):
    """Low-rank previous-token logit bias (SpecForge VanillaMarkovHead)."""

    def __init__(self, vocab_size: int, markov_rank: int):
        super().__init__()
        self.vocab_size = vocab_size
        self.markov_rank = markov_rank
        self.markov_w1 = nn.Embedding(vocab_size, markov_rank)
        self.markov_w2 = nn.Linear(markov_rank, vocab_size, bias=False)

    def get_prev_embeddings(self, token_ids: torch.Tensor) -> torch.Tensor:
        return self.markov_w1(token_ids.long())

    def bias(self, prev_token_ids: torch.Tensor) -> torch.Tensor:
        # returns [..., vocab]
        return self.markov_w2(self.get_prev_embeddings(prev_token_ids))


class AcceptRatePredictor(nn.Module):
    """Predict per-position acceptance probability (logit)."""

    def __init__(self, input_dim: int):
        super().__init__()
        self.proj = nn.Linear(input_dim, 1)

    def forward(self, features: torch.Tensor) -> torch.Tensor:
        return self.proj(features).squeeze(-1)


class DSparkDraftModel(nn.Module):
    """DFlash backbone + DSpark Markov and confidence heads.

    Submodule names match the SpecForge/RadixArk checkpoint and the GGUF
    converter, so warm-start and save need no key remapping.
    """

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.cfg = cfg
        self.fc = nn.Linear(cfg.n_taps * cfg.hidden_size, cfg.hidden_size, bias=False)
        self.hidden_norm = RMSNorm(cfg.hidden_size, cfg.rms_eps)   # encoder norm
        self.layers = nn.ModuleList([DSparkDecoderLayer(cfg) for _ in range(cfg.n_layers)])
        self.norm = RMSNorm(cfg.hidden_size, cfg.rms_eps)          # decoder final norm
        self.markov_head = VanillaMarkovHead(cfg.vocab_size, cfg.markov_rank)
        self.confidence_head = AcceptRatePredictor(cfg.hidden_size + cfg.markov_rank)
        self.rotary = YarnRotaryEmbedding(cfg)

    def encode_context(self, taps: torch.Tensor) -> torch.Tensor:
        # taps: [B, S, n_taps*H] -> context [B, S, H]
        return self.hidden_norm(self.fc(taps))

    def forward_blocks(
        self,
        taps: torch.Tensor,               # [B, S, n_taps*H]
        noise_emb: torch.Tensor,          # [B, Q, H]
        full_position_ids: torch.Tensor,  # [B, S+Q]
        attn_mask: torch.Tensor,          # [B, 1, Q, S+Q] bool
    ) -> torch.Tensor:
        context = self.encode_context(taps)             # [B, S, H]
        cos_full, sin_full = self.rotary(full_position_ids)
        noise = noise_emb
        for layer in self.layers:
            noise = layer(noise, context, cos_full, sin_full, attn_mask)
        return self.norm(noise)                          # [B, Q, H]


# ---------------------------------------------------------------------------
# Block target / mask construction (SpecForge parity)
# ---------------------------------------------------------------------------
def sample_anchor_positions(
    seq_len: int,
    loss_mask: torch.Tensor,     # [B, S] float/bool
    num_anchors: int,
    device: torch.device,
) -> Tuple[torch.Tensor, torch.Tensor]:
    """Sample anchors whose clean token and first target are supervised.

    Mirrors OnlineDFlashModel._sample_anchor_positions. When num_anchors covers
    every valid position, every supervised token becomes an anchor.
    """
    num_candidates = max(seq_len - 1, 0)
    valid = (loss_mask[:, :num_candidates] > 0.5) & (loss_mask[:, 1 : num_candidates + 1] > 0.5)
    valid_counts = valid.sum(dim=1)
    max_valid = int(valid_counts.max().item()) if valid.numel() else 0
    width = min(num_anchors, max(0, max_valid))
    if width == 0:
        raise ValueError("DSpark training requires two consecutive supervised tokens")

    rnd = torch.rand(valid.shape, device=device)
    rnd.masked_fill_(~valid, 2.0)
    candidates = rnd.argsort(dim=1)[:, :width]
    keep = torch.arange(width, device=device).unsqueeze(0) < valid_counts.clamp(max=width).unsqueeze(1)
    sentinel = valid.shape[1]
    anchors = torch.where(keep, candidates, torch.full_like(candidates, sentinel))
    anchors = anchors.sort(dim=1).values
    keep = anchors < sentinel
    return torch.where(keep, anchors, torch.zeros_like(anchors)), keep


def build_block_targets(
    input_ids: torch.Tensor,        # [B, S]
    loss_mask: torch.Tensor,        # [B, S]
    anchor_positions: torch.Tensor, # [B, N]
    block_keep_mask: torch.Tensor,  # [B, N] bool
    block_size: int,
) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
    """Return (target_ids, eval_mask, prev_token_ids, safe_label_indices).

    target_ids[b,n,j]        = input_ids at anchor + (j + 1)          (offsets 1..B)
    eval_mask[b,n,j]         = (within-seq) & (loss_mask>0.5) & block_keep, then
                               cumprod along the block axis (prefix acceptance)
    prev_token_ids[b,n,j]    = concat(anchor_token, target_ids[..., :-1])
    safe_label_indices[b,n,j]= clamped label indices, zeroed on dropped blocks
    """
    B, S = input_ids.shape
    device = input_ids.device
    label_offsets = torch.arange(1, block_size + 1, device=device).view(1, 1, -1)
    label_indices = anchor_positions.unsqueeze(-1) + label_offsets            # [B, N, bs]
    safe_label_indices = label_indices.clamp(max=S - 1)
    safe_label_indices = torch.where(
        block_keep_mask.unsqueeze(-1), safe_label_indices, torch.zeros_like(safe_label_indices)
    )
    N = anchor_positions.size(1)
    target_ids = torch.gather(
        input_ids.unsqueeze(1).expand(-1, N, -1), 2, safe_label_indices
    )

    target_valid = label_indices < S
    target_loss_mask = torch.gather(
        loss_mask.unsqueeze(1).expand(-1, N, -1), 2, safe_label_indices
    )
    eval_mask = target_valid & (target_loss_mask > 0.5) & block_keep_mask.unsqueeze(-1)
    eval_mask = eval_mask.to(torch.int32).cumprod(dim=-1).bool()

    anchor_tokens = torch.gather(input_ids, 1, anchor_positions.clamp(0, S - 1)).unsqueeze(-1)
    prev_token_ids = torch.cat([anchor_tokens, target_ids[:, :, :-1]], dim=-1)
    return target_ids, eval_mask, prev_token_ids, safe_label_indices


def create_noise_ids(
    input_ids: torch.Tensor,        # [B, S]
    anchor_positions: torch.Tensor, # [B, N]
    block_keep_mask: torch.Tensor,  # [B, N]
    block_size: int,
    mask_token_id: int = MASK_TOKEN_ID,
) -> torch.Tensor:
    """noise_ids[b, n*bs + 0] = anchor token (or MASK if block dropped); rest MASK."""
    B, S = input_ids.shape
    N = anchor_positions.shape[1]
    device = input_ids.device
    noise_ids = torch.full((B, N * block_size), mask_token_id, dtype=torch.long, device=device)
    block_starts = (torch.arange(N, device=device) * block_size).unsqueeze(0).expand(B, -1)
    anchor_tokens = torch.gather(input_ids, 1, anchor_positions.clamp(0, S - 1))
    batch_idx = torch.arange(B, device=device).unsqueeze(1).expand(B, N)
    noise_ids[batch_idx, block_starts] = anchor_tokens.masked_fill(~block_keep_mask, mask_token_id)
    return noise_ids


def create_sdpa_mask(
    anchor_positions: torch.Tensor,  # [B, N]
    block_keep_mask: torch.Tensor,   # [B, N]
    S: int,
    block_size: int,
    device: torch.device,
) -> torch.Tensor:
    """Dense boolean DFlash mask, True = attend (SpecForge create_dflash_sdpa_mask)."""
    B, N = anchor_positions.shape
    Q_LEN = N * block_size
    KV_LEN = S + N * block_size
    q_idx = torch.arange(Q_LEN, device=device).view(1, 1, -1, 1)
    kv_idx = torch.arange(KV_LEN, device=device).view(1, 1, 1, -1)
    q_block = q_idx // block_size
    anchor_exp = anchor_positions.view(B, 1, N, 1).repeat_interleave(block_size, dim=2)  # [B,1,Q,1]

    mask_context = (kv_idx < S) & (kv_idx < anchor_exp)         # context strictly before anchor
    is_draft = kv_idx >= S
    kv_block = (kv_idx - S) // block_size
    mask_draft = is_draft & (q_block == kv_block)               # own block noise (non-causal)
    valid_block = block_keep_mask.view(B, 1, N, 1).repeat_interleave(block_size, dim=2)
    return (mask_context | mask_draft) & valid_block


def create_full_position_ids(
    anchor_positions: torch.Tensor, S: int, block_size: int
) -> torch.Tensor:
    B, N = anchor_positions.shape
    device = anchor_positions.device
    ctx_pos = torch.arange(S, device=device).unsqueeze(0).expand(B, -1)
    offsets = torch.arange(block_size, device=device).view(1, 1, -1)
    draft_pos = (anchor_positions.unsqueeze(-1) + offsets).view(B, -1)
    return torch.cat([ctx_pos, draft_pos], dim=1)


# ---------------------------------------------------------------------------
# Loss (block-parallel CE + L1 + confidence BCE), memory-bounded over anchors
# ---------------------------------------------------------------------------
@dataclass
class LossAlphas:
    ce: float = 0.1
    l1: float = 0.9
    conf: float = 1.0


def dspark_loss_backward(
    model: DSparkDraftModel,
    W_lm: torch.Tensor,              # [vocab, H] frozen
    draft_hidden: torch.Tensor,      # [B, N, bs, H] (requires grad)
    target_ids: torch.Tensor,        # [B, N, bs]
    eval_mask: torch.Tensor,         # [B, N, bs] bool
    prev_token_ids: torch.Tensor,    # [B, N, bs]
    aligned_target_hidden: torch.Tensor,  # [B, N, bs, H] frozen (teacher)
    alphas: LossAlphas,
    chunk_blocks: int = 64,
    do_backward: bool = True,
) -> dict:
    """Compute the DSpark loss and (optionally) backprop, chunked over anchors.

    Full-vocab logits are the memory bottleneck. We normalize by the global
    supervised-token count computed up front, then run the objective one anchor
    chunk at a time, calling backward per chunk (retain_graph on all but the
    last) so only one chunk's vocab logits live at a time.
    """
    B, N, bs, H = draft_hidden.shape
    vocab = W_lm.shape[0]
    loss_weights = eval_mask.float()
    den = loss_weights.sum().clamp_min(1.0)

    tot = {k: 0.0 for k in ("loss", "ce", "l1", "conf", "correct", "eval_den", "acc_prob")}

    chunk_blocks = max(1, chunk_blocks)
    n_chunks = (N + chunk_blocks - 1) // chunk_blocks
    for ci in range(n_chunks):
        n0 = ci * chunk_blocks
        n1 = min(N, n0 + chunk_blocks)
        last = ci == n_chunks - 1

        h = draft_hidden[:, n0:n1]                     # [B, c, bs, H]
        tgt = target_ids[:, n0:n1]
        ev = eval_mask[:, n0:n1]
        prev = prev_token_ids[:, n0:n1]
        w = loss_weights[:, n0:n1]

        base_logits = F.linear(h, W_lm)                # [B, c, bs, vocab]
        draft_logits = base_logits + model.markov_head.bias(prev)

        ce = F.cross_entropy(
            draft_logits.reshape(-1, vocab), tgt.reshape(-1), reduction="none"
        ).reshape_as(tgt)
        ce_num = (ce * w).sum()

        # L1 teacher term
        with torch.no_grad():
            teacher_logits = F.linear(aligned_target_hidden[:, n0:n1], W_lm)
            teacher_probs = torch.softmax(teacher_logits.float(), dim=-1)
        draft_probs = torch.softmax(draft_logits.float(), dim=-1)
        l1_per_token = (draft_probs - teacher_probs).abs().sum(dim=-1)
        accept_prob = (1.0 - 0.5 * l1_per_token).clamp(0.0, 1.0)
        l1_num = (l1_per_token * w).sum()

        # Confidence BCE: predict detached accept_prob.
        prev_emb = model.markov_head.get_prev_embeddings(prev).to(h.dtype)
        conf_feat = torch.cat([h, prev_emb], dim=-1)
        conf_logit = model.confidence_head(conf_feat)  # [B, c, bs]
        conf_bce = F.binary_cross_entropy_with_logits(
            conf_logit.float(), accept_prob.detach(), reduction="none"
        )
        conf_num = (conf_bce * w).sum()

        chunk_loss = (alphas.ce * ce_num + alphas.l1 * l1_num + alphas.conf * conf_num) / den
        if do_backward:
            chunk_loss.backward(retain_graph=not last)

        with torch.no_grad():
            pred = draft_logits.argmax(dim=-1)
            tot["correct"] += ((pred == tgt) & ev).float().sum().item()
            tot["eval_den"] += ev.float().sum().item()
            tot["loss"] += chunk_loss.detach().item()
            tot["ce"] += (alphas.ce * ce_num / den).detach().item()
            tot["l1"] += (alphas.l1 * l1_num / den).detach().item()
            tot["conf"] += (alphas.conf * conf_num / den).detach().item()
            tot["acc_prob"] += (accept_prob * w).sum().item()

    tot["den"] = den.item()
    tot["acc"] = tot["correct"] / max(tot["eval_den"], 1.0)
    tot["mean_accept_prob"] = tot["acc_prob"] / max(tot["den"], 1.0)
    return tot


def run_forward_and_loss(
    model: DSparkDraftModel,
    tok_embd: torch.Tensor,   # [vocab, H] frozen
    W_lm: torch.Tensor,       # [vocab, H] frozen
    input_ids: torch.Tensor,  # [B, S]
    loss_mask: torch.Tensor,  # [B, S]
    taps: torch.Tensor,       # [B, S, n_taps*H]
    final_hidden: torch.Tensor,  # [B, S, H]
    cfg: ModelConfig,
    num_anchors: int,
    alphas: LossAlphas,
    chunk_blocks: int,
    do_backward: bool = True,
) -> dict:
    device = input_ids.device
    B, S = input_ids.shape
    bs = cfg.block_size

    anchors, block_keep = sample_anchor_positions(S, loss_mask, num_anchors, device)
    N = anchors.shape[1]

    noise_ids = create_noise_ids(input_ids, anchors, block_keep, bs, cfg.mask_token_id)  # [B, N*bs]
    noise_emb = F.embedding(noise_ids, tok_embd).to(taps.dtype)               # [B, N*bs, H]
    full_pos = create_full_position_ids(anchors, S, bs)
    attn_mask = create_sdpa_mask(anchors, block_keep, S, bs, device)

    draft_hidden = model.forward_blocks(taps, noise_emb, full_pos, attn_mask)  # [B, N*bs, H]
    draft_hidden = draft_hidden.view(B, N, bs, cfg.hidden_size)

    target_ids, eval_mask, prev_token_ids, safe_label = build_block_targets(
        input_ids, loss_mask, anchors, block_keep, bs
    )
    # aligned target hidden = final_hidden at (label_index - 1) = anchor + j
    pred_idx = (safe_label - 1).clamp(min=0)                                   # [B, N, bs]
    gather_idx = pred_idx.reshape(B, -1, 1).expand(-1, -1, cfg.hidden_size)
    aligned = torch.gather(final_hidden, 1, gather_idx).reshape(B, N, bs, cfg.hidden_size)

    return dspark_loss_backward(
        model, W_lm, draft_hidden, target_ids, eval_mask, prev_token_ids,
        aligned, alphas, chunk_blocks=chunk_blocks, do_backward=do_backward,
    )


# ---------------------------------------------------------------------------
# Data: v2 feature files (BON2) and teacher tensors
# ---------------------------------------------------------------------------
def has_supervised_pair(loss_mask: np.ndarray) -> bool:
    """True when the mask holds two consecutive supervised positions.

    sample_anchor_positions needs one anchor whose clean token and first target are
    both supervised. A sample without such a pair contributes no loss, and a batch made
    only of such samples raises in sample_anchor_positions.
    """
    m = loss_mask > 0
    return m.shape[0] >= 2 and bool(np.any(m[:-1] & m[1:]))


class BON2Dataset(Dataset):
    """Reads v2 feature .bin files.

    header  : "BON2"(4) | embd u32 | n_taps u32 | tap_layers[5] u32
    sample  : n_tokens u32 | token_ids i32[n] | loss_mask u8[n] |
              taps f32[n*n_taps*embd] | final_hidden f32[n*embd]

    __getitem__ keeps the first max_seq_len positions. A sample whose loss mask has no
    two consecutive supervised positions inside that window is skipped at index time and
    counted in n_skipped, so it never reaches a batch. A truncated file raises ValueError.
    """

    MAGIC = b"BON2"

    def __init__(self, paths: List[str], max_seq_len: int = 512):
        self.paths = paths
        self.max_seq_len = max_seq_len
        self.index: List[Tuple[int, int, int]] = []  # (file_idx, byte_offset, n_tokens)
        self.n_skipped = 0
        self.embd = None
        self.n_taps = None
        for fi, p in enumerate(paths):
            with open(p, "rb") as f:
                size = os.fstat(f.fileno()).st_size
                magic = f.read(4)
                if magic != self.MAGIC:
                    raise ValueError(f"{p}: bad magic {magic!r}, expected BON2")
                embd, n_taps = struct.unpack("<II", f.read(8))
                struct.unpack("<5I", f.read(20))  # tap_layers
                if self.embd is None:
                    self.embd, self.n_taps = embd, n_taps
                elif (self.embd, self.n_taps) != (embd, n_taps):
                    raise ValueError(f"{p}: header mismatch vs first file")
                tap_stride = n_taps * embd
                while True:
                    off = f.tell()
                    b = f.read(4)
                    if not b:
                        break
                    n = struct.unpack("<I", b)[0]
                    # token_ids i32, then loss_mask u8, then taps f32 + final_hidden f32
                    f.seek(n * 4, os.SEEK_CUR)
                    loss_mask = np.frombuffer(f.read(n), dtype=np.uint8)
                    f.seek(n * tap_stride * 4 + n * embd * 4, os.SEEK_CUR)
                    if loss_mask.shape[0] != n or f.tell() > size:
                        raise ValueError(f"{p}: truncated sample at byte offset {off} (n_tokens={n})")
                    if not has_supervised_pair(loss_mask[: max_seq_len]):
                        self.n_skipped += 1
                        continue
                    self.index.append((fi, off, n))
        print(f"[data] indexed {len(self.index)} samples across {len(paths)} file(s); "
              f"embd={self.embd} n_taps={self.n_taps}")
        if self.n_skipped:
            print(f"[data] WARNING: skipped {self.n_skipped} sample(s) with fewer than two consecutive "
                  f"supervised tokens inside max_seq_len={max_seq_len}")
        if not self.index:
            raise ValueError(f"no usable samples: every sample lacks a supervised pair inside "
                             f"max_seq_len={max_seq_len}")

    def __len__(self):
        return len(self.index)

    def __getitem__(self, i):
        fi, off, n = self.index[i]
        embd, n_taps = self.embd, self.n_taps
        tap_stride = n_taps * embd
        with open(self.paths[fi], "rb") as f:
            f.seek(off + 4)
            tokens = np.frombuffer(f.read(n * 4), dtype=np.int32)
            loss_mask = np.frombuffer(f.read(n * 1), dtype=np.uint8)
            taps = np.frombuffer(f.read(n * tap_stride * 4), dtype=np.float32).reshape(n, tap_stride)
            final_hidden = np.frombuffer(f.read(n * embd * 4), dtype=np.float32).reshape(n, embd)
        if n > self.max_seq_len:
            tokens = tokens[: self.max_seq_len]
            loss_mask = loss_mask[: self.max_seq_len]
            taps = taps[: self.max_seq_len]
            final_hidden = final_hidden[: self.max_seq_len]
        return (
            torch.from_numpy(tokens.copy()).long(),
            torch.from_numpy(loss_mask.copy()).float(),
            torch.from_numpy(taps.copy()).float(),
            torch.from_numpy(final_hidden.copy()).float(),
        )


def bon2_collate(batch):
    max_len = max(b[0].shape[0] for b in batch)
    B = len(batch)
    tap_stride = batch[0][2].shape[1]
    embd = batch[0][3].shape[1]
    tokens = torch.zeros(B, max_len, dtype=torch.long)
    loss_mask = torch.zeros(B, max_len, dtype=torch.float32)
    taps = torch.zeros(B, max_len, tap_stride, dtype=torch.float32)
    final_hidden = torch.zeros(B, max_len, embd, dtype=torch.float32)
    for i, (tok, lm, tp, fh) in enumerate(batch):
        L = tok.shape[0]
        tokens[i, :L] = tok
        loss_mask[i, :L] = lm
        taps[i, :L] = tp
        final_hidden[i, :L] = fh
    return tokens, loss_mask, taps, final_hidden


def read_teacher_matrix(path: str) -> torch.Tensor:
    """Read W_lm.bin / tok_embd.bin: [vocab u32, embd u32] then f16[vocab*embd]."""
    with open(path, "rb") as f:
        vocab, embd = struct.unpack("<II", f.read(8))
        data = np.frombuffer(f.read(vocab * embd * 2), dtype=np.float16).reshape(vocab, embd)
    return torch.from_numpy(data.copy())


# ---------------------------------------------------------------------------
# Warm-start / save
# ---------------------------------------------------------------------------
def warm_start(model: DSparkDraftModel, path: str):
    from safetensors import safe_open
    print(f"[warm-start] loading {path}")
    sd = {}
    with safe_open(path, framework="pt") as f:
        for k in f.keys():
            sd[k] = f.get_tensor(k)
    missing, unexpected = model.load_state_dict(sd, strict=False)
    # rotary.inv_freq is a non-persistent buffer -> expected in 'missing'
    missing = [m for m in missing if not m.endswith("inv_freq")]
    print(f"[warm-start] loaded. missing={len(missing)} unexpected={len(unexpected)}")
    if missing:
        print(f"[warm-start] missing (kept at init): {missing[:12]}{' ...' if len(missing) > 12 else ''}")
    if unexpected:
        print(f"[warm-start] unexpected (ignored): {unexpected[:12]}{' ...' if len(unexpected) > 12 else ''}")


def save_checkpoint(model: DSparkDraftModel, path: str):
    from safetensors.torch import save_file
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    sd = {}
    for k, v in model.state_dict().items():
        if k.endswith("inv_freq") or k.startswith("rotary."):
            continue  # runtime rebuilds rope; not a checkpoint tensor
        sd[k] = v.detach().to(torch.bfloat16).contiguous().cpu()
    save_file(sd, path)
    print(f"[save] wrote {len(sd)} tensors -> {path}")


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------
def build_optimizer(model: DSparkDraftModel, lr: float):
    # Higher lr for the feature-fusion and auxiliary heads, base lr for the backbone.
    head_params = (
        list(model.fc.parameters())
        + list(model.hidden_norm.parameters())
        + list(model.confidence_head.parameters())
    )
    head_ids = {id(p) for p in head_params}
    base_params = [p for p in model.parameters() if id(p) not in head_ids and p.requires_grad]
    return torch.optim.AdamW(
        [
            {"params": [p for p in head_params if p.requires_grad], "lr": lr * 2},
            {"params": base_params, "lr": lr},
        ],
        weight_decay=0.01,
    )


def train(args):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    dtype = torch.bfloat16 if device.type == "cuda" else torch.float32
    print(f"[train] device={device} dtype={dtype} "
          f"({torch.cuda.get_device_name(0) if device.type == 'cuda' else 'CPU'})")

    cfg = ModelConfig(rope_yarn=not args.no_rope_yarn)
    feats = sorted(glob.glob(os.path.join(args.feats_dir, "*.bin")))
    if not feats:
        print(f"[train] ERROR: no *.bin features in {args.feats_dir}. "
              f"Real teacher/feature files are required to run full training.", file=sys.stderr)
        sys.exit(2)
    w_lm_path = os.path.join(args.teacher_dir, "W_lm.bin")
    tok_embd_path = os.path.join(args.teacher_dir, "tok_embd.bin")
    for p in (w_lm_path, tok_embd_path):
        if not os.path.exists(p):
            print(f"[train] ERROR: missing teacher file {p}. Real teacher files are "
                  f"required to run full training.", file=sys.stderr)
            sys.exit(2)

    print("[train] loading teacher matrices (this reads ~2.5 GB f16 each) ...")
    W_lm = read_teacher_matrix(w_lm_path).to(device=device, dtype=dtype)
    tok_embd = read_teacher_matrix(tok_embd_path).to(device=device, dtype=dtype)
    assert W_lm.shape[0] == cfg.vocab_size and W_lm.shape[1] == cfg.hidden_size, W_lm.shape
    W_lm.requires_grad_(False)
    tok_embd.requires_grad_(False)

    dataset = BON2Dataset(feats, max_seq_len=args.max_seq_len)
    loader = DataLoader(dataset, batch_size=args.batch_size, shuffle=True, collate_fn=bon2_collate)

    model = DSparkDraftModel(cfg).to(device=device, dtype=dtype)
    if args.warm_start and os.path.exists(args.warm_start):
        warm_start(model, args.warm_start)
    else:
        print("[train] WARNING: no warm-start checkpoint; training the drafter from scratch.")

    optimizer = build_optimizer(model, args.lr)
    total_steps = len(loader) * args.epochs
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=max(total_steps, 1), eta_min=1e-6)
    alphas = LossAlphas(ce=args.ce_alpha, l1=args.l1_alpha, conf=args.conf_alpha)

    print(f"[train] {total_steps} steps, {args.epochs} epochs, {len(dataset)} samples, "
          f"num_anchors={args.num_anchors}, block_size={cfg.block_size}")
    model.train()
    step = 0
    t0 = time.time()
    for epoch in range(args.epochs):
        if args.max_steps and step >= args.max_steps: break
        for tokens, loss_mask, taps, final_hidden in loader:
            tokens = tokens.to(device)
            loss_mask = loss_mask.to(device)
            taps = taps.to(device=device, dtype=dtype)
            final_hidden = final_hidden.to(device=device, dtype=dtype)
            optimizer.zero_grad(set_to_none=True)
            stats = run_forward_and_loss(
                model, tok_embd, W_lm, tokens, loss_mask, taps, final_hidden,
                cfg, args.num_anchors, alphas, chunk_blocks=args.chunk_blocks, do_backward=True,
            )
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            scheduler.step()
            step += 1
            if args.max_steps and step >= args.max_steps:
                print(f"[train] max_steps {args.max_steps} reached; stopping early", flush=True); break
            if args.save_every and step % args.save_every == 0 and step < total_steps:
                save_checkpoint(model, args.out.replace(".safetensors", f"_step{step}.safetensors"))
            if step % args.log_every == 0 or step == total_steps:
                el = time.time() - t0
                vram = torch.cuda.memory_allocated() / 1024**3 if device.type == "cuda" else 0.0
                print(f"ep {epoch+1}/{args.epochs} step {step}/{total_steps} "
                      f"loss {stats['loss']:.4f} (ce {stats['ce']:.4f} l1 {stats['l1']:.4f} "
                      f"conf {stats['conf']:.4f}) acc {stats['acc']:.3f} "
                      f"acc_p {stats['mean_accept_prob']:.3f} lr {scheduler.get_last_lr()[0]:.2e} "
                      f"vram {vram:.1f}G {el/60:.1f}m")
        save_checkpoint(model, args.out)
        save_checkpoint(model, args.out.replace(".safetensors", f"_epoch{epoch+1}.safetensors"))
    print("[train] done.")


# ---------------------------------------------------------------------------
# Dry run on a synthetic fixture (tiny dims, CPU-friendly)
# ---------------------------------------------------------------------------
def write_synthetic_fixture(path: str, cfg: ModelConfig, n_samples=4, seq=16, seed=0,
                            prompt_lens: Optional[List[int]] = None):
    """Write a BON2 fixture. prompt_lens[i] positions of sample i are unsupervised
    (loss_mask 0); the default supervises every position."""
    rng = np.random.default_rng(seed)
    embd, n_taps = cfg.hidden_size, cfg.n_taps
    with open(path, "wb") as f:
        f.write(b"BON2")
        f.write(struct.pack("<II", embd, n_taps))
        f.write(struct.pack("<5I", 6, 20, 34, 48, 62))
        for i in range(n_samples):
            n = seq
            n_prompt = prompt_lens[i] if prompt_lens is not None else 0
            loss_mask = np.ones(n, dtype=np.uint8)
            loss_mask[:n_prompt] = 0
            f.write(struct.pack("<I", n))
            f.write(rng.integers(0, cfg.vocab_size, size=n, dtype=np.int32).tobytes())
            f.write(loss_mask.tobytes())
            f.write((rng.standard_normal((n, n_taps * embd)).astype(np.float32) * 0.1).tobytes())
            f.write((rng.standard_normal((n, embd)).astype(np.float32) * 0.1).tobytes())


def write_synthetic_teacher(dir_path: str, cfg: ModelConfig, seed=1):
    rng = np.random.default_rng(seed)
    os.makedirs(dir_path, exist_ok=True)
    for name in ("W_lm.bin", "tok_embd.bin"):
        with open(os.path.join(dir_path, name), "wb") as f:
            f.write(struct.pack("<II", cfg.vocab_size, cfg.hidden_size))
            mat = (rng.standard_normal((cfg.vocab_size, cfg.hidden_size)) * 0.02).astype(np.float16)
            f.write(mat.tobytes())


def dry_run(steps: int = 12):
    import tempfile
    torch.manual_seed(0)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    dtype = torch.float32  # CPU-friendly; the real run uses bf16 on the GB10.
    print(f"[dry-run] device={device} dtype={dtype}")

    # Tiny architecture so the forward runs fast on CPU.
    cfg = ModelConfig(
        hidden_size=64, n_taps=5, n_layers=2, num_heads=4, num_kv_heads=2,
        head_dim=16, intermediate_size=128, vocab_size=256, markov_rank=32,
        block_size=4, mask_token_id=255, rope_yarn=True, yarn_orig_max_pos=64,
    )
    tmp = tempfile.mkdtemp(prefix="dspark_dry_")
    feats_dir = os.path.join(tmp, "feats")
    teacher_dir = os.path.join(tmp, "teacher")
    os.makedirs(feats_dir, exist_ok=True)
    write_synthetic_fixture(os.path.join(feats_dir, "synth.bin"), cfg, n_samples=6, seq=16)
    write_synthetic_teacher(teacher_dir, cfg)
    print(f"[dry-run] wrote synthetic fixture under {tmp}")

    W_lm = read_teacher_matrix(os.path.join(teacher_dir, "W_lm.bin")).to(device, dtype)
    tok_embd = read_teacher_matrix(os.path.join(teacher_dir, "tok_embd.bin")).to(device, dtype)
    W_lm.requires_grad_(False)
    tok_embd.requires_grad_(False)

    dataset = BON2Dataset([os.path.join(feats_dir, "synth.bin")], max_seq_len=64)
    loader = DataLoader(dataset, batch_size=2, shuffle=True, collate_fn=bon2_collate)

    model = DSparkDraftModel(cfg).to(device, dtype)
    n_params = sum(p.numel() for p in model.parameters())
    print(f"[dry-run] model params = {n_params:,}")
    optimizer = build_optimizer(model, 3e-3)
    alphas = LossAlphas()

    # Report tensor shapes for one batch before training.
    tokens, loss_mask, taps, final_hidden = next(iter(loader))
    tokens, loss_mask = tokens.to(device), loss_mask.to(device)
    taps, final_hidden = taps.to(device, dtype), final_hidden.to(device, dtype)
    B, S = tokens.shape
    anchors, keep = sample_anchor_positions(S, loss_mask, num_anchors=64, device=device)
    N = anchors.shape[1]
    noise_ids = create_noise_ids(tokens, anchors, keep, cfg.block_size, cfg.mask_token_id)
    noise_emb = F.embedding(noise_ids, tok_embd)
    full_pos = create_full_position_ids(anchors, S, cfg.block_size)
    attn_mask = create_sdpa_mask(anchors, keep, S, cfg.block_size, device)
    dh = model.forward_blocks(taps, noise_emb, full_pos, attn_mask).view(B, N, cfg.block_size, cfg.hidden_size)
    tgt, ev, prev, _ = build_block_targets(tokens, loss_mask, anchors, keep, cfg.block_size)
    print("[dry-run] SHAPES")
    print(f"  input_ids           {tuple(tokens.shape)}")
    print(f"  taps (fc input)     {tuple(taps.shape)}  (n_taps*H={cfg.n_taps*cfg.hidden_size})")
    print(f"  final_hidden        {tuple(final_hidden.shape)}")
    print(f"  anchors             {tuple(anchors.shape)}  N={N}")
    print(f"  noise_ids           {tuple(noise_ids.shape)}  (=N*block_size)")
    print(f"  full_position_ids   {tuple(full_pos.shape)}  (=S + N*block_size)")
    print(f"  attn_mask           {tuple(attn_mask.shape)}  bool, True=attend")
    print(f"  draft_hidden        {tuple(dh.shape)}  [B,N,block,H]")
    print(f"  target_ids/eval     {tuple(tgt.shape)} / {tuple(ev.shape)}")
    print(f"  prev_token_ids      {tuple(prev.shape)}")
    print(f"  W_lm / tok_embd     {tuple(W_lm.shape)} / {tuple(tok_embd.shape)}")

    print("[dry-run] LOSS CURVE (expect a downward trend)")
    losses = []
    it = iter(loader)
    for s in range(steps):
        try:
            batch = next(it)
        except StopIteration:
            it = iter(loader)
            batch = next(it)
        tokens, loss_mask, taps, final_hidden = batch
        tokens, loss_mask = tokens.to(device), loss_mask.to(device)
        taps, final_hidden = taps.to(device, dtype), final_hidden.to(device, dtype)
        optimizer.zero_grad(set_to_none=True)
        stats = run_forward_and_loss(
            model, tok_embd, W_lm, tokens, loss_mask, taps, final_hidden,
            cfg, num_anchors=64, alphas=alphas, chunk_blocks=16, do_backward=True,
        )
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optimizer.step()
        losses.append(stats["loss"])
        print(f"  step {s:02d} loss {stats['loss']:.4f} "
              f"(ce {stats['ce']:.4f} l1 {stats['l1']:.4f} conf {stats['conf']:.4f}) "
              f"acc {stats['acc']:.3f} acc_p {stats['mean_accept_prob']:.3f}")

    # Save + verify converter-compatible tensor names.
    ckpt = os.path.join(tmp, "dry_ckpt.safetensors")
    save_checkpoint(model, ckpt)
    from safetensors import safe_open
    with safe_open(ckpt, framework="pt") as f:
        keys = set(f.keys())
    required = {"fc.weight", "hidden_norm.weight", "norm.weight",
                "markov_head.markov_w1.weight", "markov_head.markov_w2.weight",
                "confidence_head.proj.weight", "confidence_head.proj.bias"}
    for i in range(cfg.n_layers):
        required |= {
            f"layers.{i}.input_layernorm.weight",
            f"layers.{i}.self_attn.q_proj.weight", f"layers.{i}.self_attn.k_proj.weight",
            f"layers.{i}.self_attn.v_proj.weight", f"layers.{i}.self_attn.o_proj.weight",
            f"layers.{i}.self_attn.q_norm.weight", f"layers.{i}.self_attn.k_norm.weight",
            f"layers.{i}.post_attention_layernorm.weight",
            f"layers.{i}.mlp.gate_proj.weight", f"layers.{i}.mlp.up_proj.weight",
            f"layers.{i}.mlp.down_proj.weight",
        }
    missing = required - keys
    extra = keys - required
    print(f"[dry-run] checkpoint keys: {len(keys)} total")
    print(f"[dry-run] converter-required keys present: {len(required - missing)}/{len(required)}")
    if missing:
        print(f"[dry-run] MISSING converter keys: {sorted(missing)}")
    if extra:
        print(f"[dry-run] extra keys (not required by converter): {sorted(extra)}")
    # Truncation check: with max_seq_len=8, only the sample with prompt length 4 keeps a
    # supervised pair. Prompt length 7 keeps one supervised position, 12 keeps none inside
    # the window, and 16 has no supervised position at all. All three must be skipped.
    trunc_path = os.path.join(tmp, "trunc.bin")
    write_synthetic_fixture(trunc_path, cfg, n_samples=4, seq=16, prompt_lens=[4, 7, 12, 16])
    trunc_ds = BON2Dataset([trunc_path], max_seq_len=8)
    trunc_ok = len(trunc_ds) == 1 and trunc_ds.n_skipped == 3
    print(f"[dry-run] truncation skip: kept {len(trunc_ds)}/4 (expect 1), "
          f"skipped {trunc_ds.n_skipped} (expect 3) -> {'ok' if trunc_ok else 'FAIL'}")

    down = losses[0] - losses[-1]
    print(f"[dry-run] loss[0]={losses[0]:.4f} -> loss[-1]={losses[-1]:.4f} (delta {down:+.4f})")
    ok = (not missing) and (down > 0) and trunc_ok
    print(f"[dry-run] RESULT: {'PASS' if ok else 'CHECK'} "
          f"(tensors flow, keys match converter, loss {'decreased' if down > 0 else 'did not decrease'}, "
          f"truncation skip {'ok' if trunc_ok else 'FAIL'})")
    return ok


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="DSpark v2 drafter trainer (Bonsai 2)")
    ap.add_argument("--dry-run", action="store_true", help="synthetic shape/loss test on CPU")
    ap.add_argument("--dry-run-steps", type=int, default=12)
    ap.add_argument("--feats-dir", default=os.path.join(HERE, "feats"))
    ap.add_argument("--teacher-dir", default=os.path.join(HERE, "teacher"))
    ap.add_argument("--warm-start", default=os.path.join(BONSAI_ROOT, "models", "qwen38-dspark", "model.safetensors"))
    ap.add_argument("--out", default=os.path.join(BONSAI_ROOT, "models", "bonsai2-dspark", "bonsai2_dspark_v2.safetensors"))
    ap.add_argument("--epochs", type=int, default=2)
    ap.add_argument("--batch-size", type=int, default=2)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--max-seq-len", type=int, default=512)
    ap.add_argument("--num-anchors", type=int, default=512,
                    help="max anchors per sequence; covers every supervised position for seq<=this")
    ap.add_argument("--no-rope-yarn", action="store_true",
                    help="use plain RoPE (theta only) instead of YaRN; match this to the runtime GGUF")
    ap.add_argument("--chunk-blocks", type=int, default=64, help="anchor chunk for bounded vocab-logit memory")
    ap.add_argument("--ce-alpha", type=float, default=0.1)
    ap.add_argument("--l1-alpha", type=float, default=0.9)
    ap.add_argument("--conf-alpha", type=float, default=1.0)
    ap.add_argument("--log-every", type=int, default=10)
    ap.add_argument("--save-every", type=int, default=0, help="save an intermediate checkpoint every N steps (0=off)")
    ap.add_argument("--max-steps", type=int, default=0, help="stop after N optimizer steps (0=full epochs)")
    args = ap.parse_args()

    if args.dry_run:
        ok = dry_run(steps=args.dry_run_steps)
        sys.exit(0 if ok else 1)
    train(args)


if __name__ == "__main__":
    main()
