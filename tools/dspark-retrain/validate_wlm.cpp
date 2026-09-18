// validate_wlm.cpp
// Validation gate for W_lm.bin.
// Run llama.cpp on a short prompt. Capture per-position:
//   - llama logits            (pass A: embeddings off)
//   - final_hidden = t_embd   (pass B: embeddings on, pooling NONE, post-final-norm LM-head input)
// Recompute logits = final_hidden @ W_lm.T and compare argmax + top-1 value to llama.

#include "llama.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <cstdint>
#include <vector>
#include <string>

#ifdef _OPENMP
#include <omp.h>
#endif

static inline float f16_to_f32(uint16_t h) {
    // minimal IEEE half -> float
    const uint32_t sign = (uint32_t)(h & 0x8000) << 16;
    const uint32_t exp  = (h >> 10) & 0x1F;
    const uint32_t man  = h & 0x3FF;
    uint32_t bits;
    if (exp == 0) {
        if (man == 0) { bits = sign; }
        else {
            int e = -1; uint32_t m = man;
            do { e++; m <<= 1; } while ((m & 0x400) == 0);
            m &= 0x3FF;
            bits = sign | ((uint32_t)(127 - 15 - e) << 23) | (m << 13);
        }
    } else if (exp == 0x1F) {
        bits = sign | 0x7F800000 | (man << 13);
    } else {
        bits = sign | ((exp - 15 + 127) << 23) | (man << 13);
    }
    float f; std::memcpy(&f, &bits, 4); return f;
}

int main(int argc, char ** argv) {
    // Defaults resolve against BONSAI_ROOT (the demo checkout), else the cwd.
    const char * root_env = getenv("BONSAI_ROOT");
    const std::string root = (root_env && *root_env) ? root_env : ".";
    const std::string default_model = root + "/models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf";
    const std::string default_wlm   = root + "/tools/dspark-retrain/teacher/W_lm.bin";
    const char * model_path = (argc > 1) ? argv[1] : default_model.c_str();
    const char * wlm_path   = (argc > 2) ? argv[2] : default_wlm.c_str();
    const char * prompt = (argc > 3) ? argv[3]
        : "The quick brown fox jumps over the lazy dog. In computer science, a hash table is a data structure that maps keys to values for highly efficient lookup.";

    printf("=== W_lm validation gate ===\n");
    printf("model:  %s\nW_lm:   %s\nprompt: %s\n", model_path, wlm_path, prompt);

    // --- load W_lm.bin ---
    FILE * fw = fopen(wlm_path, "rb");
    if (!fw) { fprintf(stderr, "ERROR: cannot open %s\n", wlm_path); return 1; }
    uint32_t hdr[2];
    if (fread(hdr, sizeof(uint32_t), 2, fw) != 2) { fprintf(stderr, "ERROR: bad header\n"); return 1; }
    const int64_t W_vocab = hdr[0];
    const int64_t W_embd  = hdr[1];
    printf("W_lm header: vocab=%lld embd=%lld\n", (long long) W_vocab, (long long) W_embd);
    const size_t n_elem = (size_t) W_vocab * (size_t) W_embd;
    std::vector<uint16_t> wlm_h(n_elem);
    if (fread(wlm_h.data(), sizeof(uint16_t), n_elem, fw) != n_elem) {
        fprintf(stderr, "ERROR: short read on W_lm payload\n"); return 1;
    }
    fclose(fw);
    // convert to f32 once for fast matmul
    std::vector<float> wlm(n_elem);
    #pragma omp parallel for schedule(static)
    for (size_t i = 0; i < n_elem; ++i) wlm[i] = f16_to_f32(wlm_h[i]);
    printf("W_lm loaded and converted to f32 (%.2f GB)\n", n_elem * 4.0 / 1e9);

    // --- load model ---
    llama_backend_init();
    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 99;
    llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (!model) { fprintf(stderr, "ERROR: model load failed\n"); return 1; }
    const int n_embd  = llama_model_n_embd(model);
    const llama_vocab * vocab = llama_model_get_vocab(model);
    const int n_vocab = llama_vocab_n_tokens(vocab);
    printf("model: n_embd=%d n_vocab=%d\n", n_embd, n_vocab);
    if (n_embd != W_embd || n_vocab != W_vocab) {
        fprintf(stderr, "ERROR: shape mismatch model vs W_lm\n"); return 1;
    }

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = 512; cparams.n_batch = 512; cparams.n_ubatch = 512;
    cparams.pooling_type = LLAMA_POOLING_TYPE_NONE;
    cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
    llama_context * ctx = llama_init_from_model(model, cparams);
    if (!ctx) { fprintf(stderr, "ERROR: ctx create failed\n"); return 1; }

    // tokenize
    std::vector<llama_token> tokens(strlen(prompt) + 16);
    int n_tok = llama_tokenize(vocab, prompt, strlen(prompt), tokens.data(), tokens.size(), true, false);
    if (n_tok <= 0) { fprintf(stderr, "ERROR: tokenize failed\n"); return 1; }
    tokens.resize(n_tok);
    printf("n_tok=%d\n", n_tok);

    auto build_batch = [&](void) {
        llama_batch b = llama_batch_init(n_tok, 0, 1);
        for (int i = 0; i < n_tok; ++i) {
            b.token[i] = tokens[i]; b.pos[i] = i;
            b.n_seq_id[i] = 1; b.seq_id[i][0] = 0; b.logits[i] = true;
        }
        b.n_tokens = n_tok;
        return b;
    };

    // --- pass A: logits (embeddings off) ---
    llama_set_embeddings(ctx, false);
    llama_memory_clear(llama_get_memory(ctx), true);
    llama_batch bA = build_batch();
    if (llama_decode(ctx, bA) != 0) { fprintf(stderr, "ERROR: decode A failed\n"); return 1; }
    std::vector<int>   llama_argmax(n_tok);
    std::vector<float> llama_top1(n_tok);
    for (int i = 0; i < n_tok; ++i) {
        const float * lg = llama_get_logits_ith(ctx, i);
        if (!lg) { fprintf(stderr, "ERROR: null logits at %d\n", i); return 1; }
        int am = 0; float mx = lg[0];
        for (int v = 1; v < n_vocab; ++v) if (lg[v] > mx) { mx = lg[v]; am = v; }
        llama_argmax[i] = am; llama_top1[i] = mx;
    }
    llama_batch_free(bA);

    // --- pass B: final_hidden = t_embd (embeddings on) ---
    llama_set_embeddings(ctx, true);
    llama_memory_clear(llama_get_memory(ctx), true);
    llama_batch bB = build_batch();
    if (llama_decode(ctx, bB) != 0) { fprintf(stderr, "ERROR: decode B failed\n"); return 1; }
    std::vector<float> hidden((size_t) n_tok * n_embd);
    for (int i = 0; i < n_tok; ++i) {
        const float * em = llama_get_embeddings_ith(ctx, i);
        if (!em) { fprintf(stderr, "ERROR: null embeddings at %d\n", i); return 1; }
        std::memcpy(&hidden[(size_t) i * n_embd], em, n_embd * sizeof(float));
    }
    llama_batch_free(bB);

    // --- recompute logits = hidden @ W_lm.T and compare ---
    int match = 0;
    int val_ok = 0;
    printf("\npos | llama_argmax(top1)      | recomp_argmax(top1)     | argmax? | val%%\n");
    for (int i = 0; i < n_tok; ++i) {
        const float * h = &hidden[(size_t) i * n_embd];
        int r_am = 0; float r_mx = -1e30f;
        float r_at_llama = 0.0f;
        const int lam = llama_argmax[i];
        #pragma omp parallel
        {
            int    l_am = 0; float l_mx = -1e30f;
            #pragma omp for schedule(static) nowait
            for (int64_t v = 0; v < W_vocab; ++v) {
                const float * w = &wlm[(size_t) v * W_embd];
                float dot = 0.0f;
                for (int64_t k = 0; k < W_embd; ++k) dot += h[k] * w[k];
                if (dot > l_mx) { l_mx = dot; l_am = (int) v; }
                if ((int) v == lam) r_at_llama = dot;
            }
            #pragma omp critical
            { if (l_mx > r_mx) { r_mx = l_mx; r_am = l_am; } }
        }
        const bool am_match = (r_am == lam);
        // value check: recomputed logit at llama's argmax vs llama's top1
        const float denom = fabsf(llama_top1[i]) > 1e-6f ? fabsf(llama_top1[i]) : 1.0f;
        const float vpct = 100.0f * fabsf(r_at_llama - llama_top1[i]) / denom;
        if (am_match) match++;
        if (vpct <= 1.0f) val_ok++;
        printf("%3d | %7d (%9.3f)   | %7d (%9.3f)   | %s   | %.3f%%\n",
               i, lam, llama_top1[i], r_am, r_mx, am_match ? "yes" : "NO ", vpct);
    }

    printf("\n=== RESULT ===\n");
    printf("argmax match: %d / %d = %.2f%%\n", match, n_tok, 100.0 * match / n_tok);
    printf("top1 value within 1%%: %d / %d = %.2f%%\n", val_ok, n_tok, 100.0 * val_ok / n_tok);
    const bool pass = (100.0 * match / n_tok > 95.0) && (100.0 * val_ok / n_tok > 95.0);
    printf("GATE: %s\n", pass ? "PASS" : "FAIL");

    llama_free(ctx);
    llama_model_free(model);
    llama_backend_free();
    return pass ? 0 : 2;
}
