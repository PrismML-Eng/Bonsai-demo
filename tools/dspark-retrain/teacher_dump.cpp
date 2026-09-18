// teacher_dump.cpp
// Dequantize Bonsai 2 output.weight and token_embd.weight from the PQ2_0 latent
// basis and apply the exact prism.hadamard transform the runtime applies, so:
//   W_lm.bin      : logits  = final_hidden @ W_lm.T           (LM head, forward fold)
//   tok_embd.bin  : primal input-embedding table              (inverse-after-lookup)
//
// Both reduce to the same per-row op:  out_row = signs (.) BlockHadamard(dequant(row))
// - forward LM head (build_lora_mm): cur = signs(.)x ; cur = H(cur) ; mul_mat(W_stored, cur)
//   composed weight-side => W_lm[v,:] = signs (.) H(W_stored[v,:])
// - inverse lookup (build_inp_embd): cur = H(z) ; cur = signs(.)cur
//   => primal[t,:]  = signs (.) H(z_t)
// H is the normalized Sylvester-Walsh-Hadamard on 1024-blocks (scale = 1/sqrt(1024)),
// built exactly as src/llama-model.cpp does; signs is the width-5120 sign vector.
//
// Pure ggml/gguf: no libllama, CPU only. Links libggml-base (dequantize_row_pq2_0,
// ggml_get_type_traits, gguf_*).

#include "ggml.h"
#include "gguf.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <cstdint>
#include <vector>
#include <string>
#include <sys/stat.h>

#ifdef _OPENMP
#include <omp.h>
#endif

static void fwht_inplace(float * a, int n) {
    // unnormalized natural-order Walsh-Hadamard transform:
    // result[i] = sum_k (-1)^popcount(i&k) * a[k]  == the matrix llama.cpp builds
    for (int len = 1; len < n; len <<= 1) {
        for (int i = 0; i < n; i += (len << 1)) {
            for (int j = i; j < i + len; ++j) {
                const float x = a[j];
                const float y = a[j + len];
                a[j]       = x + y;
                a[j + len] = x - y;
            }
        }
    }
}

int main(int argc, char ** argv) {
    // Defaults resolve against BONSAI_ROOT (the demo checkout), else the cwd.
    const char * root_env = getenv("BONSAI_ROOT");
    const std::string root = (root_env && *root_env) ? root_env : ".";
    const std::string default_model = root + "/models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf";
    const std::string default_out   = root + "/tools/dspark-retrain/teacher";
    const char * model_path = (argc > 1) ? argv[1] : default_model.c_str();
    const char * out_dir    = (argc > 2) ? argv[2] : default_out.c_str();
    mkdir(out_dir, 0755); // create the output directory if it is missing

    printf("=== Bonsai 2 teacher tensor dump ===\n");
    printf("model:   %s\n", model_path);
    printf("out_dir: %s\n", out_dir);

    struct ggml_context * meta = nullptr;
    struct gguf_init_params gp = { /*.no_alloc=*/ false, /*.ctx=*/ &meta };
    struct gguf_context * gguf = gguf_init_from_file(model_path, gp);
    if (!gguf || !meta) {
        fprintf(stderr, "ERROR: failed to open gguf %s\n", model_path);
        return 1;
    }

    // --- prism.hadamard metadata ---
    auto req_key = [&](const char * k) -> int64_t {
        int64_t id = gguf_find_key(gguf, k);
        if (id < 0) { fprintf(stderr, "ERROR: missing gguf key %s\n", k); exit(1); }
        return id;
    };
    const uint32_t block_size = gguf_get_val_u32(gguf, req_key("prism.hadamard.block_size"));
    const int64_t sw_id = req_key("prism.hadamard.sign_widths");
    const int64_t sv_id = req_key("prism.hadamard.sign_values");
    const size_t n_widths = gguf_get_arr_n(gguf, sw_id);
    const size_t n_signs  = gguf_get_arr_n(gguf, sv_id);
    const int32_t * sign_widths = (const int32_t *) gguf_get_arr_data(gguf, sw_id);
    const int32_t * sign_values = (const int32_t *) gguf_get_arr_data(gguf, sv_id);
    printf("block_size=%u sign_widths=%zu sign_values=%zu\n", block_size, n_widths, n_signs);

    const float had_scale = 1.0f / sqrtf((float) block_size);

    // locate the width-5120 sign vector offset (n_embd sign vector)
    auto sign_offset_for_width = [&](uint32_t width) -> int64_t {
        size_t off = 0;
        for (size_t i = 0; i < n_widths; ++i) {
            if ((uint32_t) sign_widths[i] == width) return (int64_t) off;
            off += (size_t) sign_widths[i];
        }
        return -1;
    };

    const char * tensor_names[2] = { "output.weight", "token_embd.weight" };
    const char * out_files[2]    = { "W_lm.bin",       "tok_embd.bin"      };

    // reusable f16 output buffer, sized on first tensor
    std::vector<uint16_t> obuf;

    for (int t = 0; t < 2; ++t) {
        struct ggml_tensor * w = ggml_get_tensor(meta, tensor_names[t]);
        if (!w) { fprintf(stderr, "ERROR: tensor %s not found\n", tensor_names[t]); return 1; }

        const int64_t n_embd  = w->ne[0];
        const int64_t n_vocab = w->ne[1];
        const enum ggml_type type = w->type;
        const struct ggml_type_traits * tr = ggml_get_type_traits(type);
        if (!tr || !tr->to_float) {
            fprintf(stderr, "ERROR: type %d has no to_float\n", (int) type);
            return 1;
        }
        if (n_embd % (int64_t) block_size != 0) {
            fprintf(stderr, "ERROR: n_embd %lld not divisible by block_size %u\n",
                    (long long) n_embd, block_size);
            return 1;
        }
        const int64_t n_blocks = n_embd / (int64_t) block_size;
        const size_t row_bytes = ggml_row_size(type, n_embd);

        const int64_t sign_off = sign_offset_for_width((uint32_t) n_embd);
        if (sign_off < 0) {
            fprintf(stderr, "ERROR: no sign vector for width %lld\n", (long long) n_embd);
            return 1;
        }
        const int32_t * signs = sign_values + sign_off;

        printf("\n[%s] ne=[%lld,%lld] type=%s row_bytes=%zu n_blocks=%lld sign_off=%lld\n",
               tensor_names[t], (long long) n_embd, (long long) n_vocab,
               tr->type_name, row_bytes, (long long) n_blocks, (long long) sign_off);

        const size_t n_elem = (size_t) n_embd * (size_t) n_vocab;
        obuf.resize(n_elem);

        const char * base = (const char *) w->data;

        int64_t next_report = 0;
        #pragma omp parallel
        {
            std::vector<float> row(n_embd);
            #pragma omp for schedule(static)
            for (int64_t v = 0; v < n_vocab; ++v) {
                tr->to_float(base + (size_t) v * row_bytes, row.data(), n_embd);
                for (int64_t b = 0; b < n_blocks; ++b) {
                    float * blk = row.data() + b * (int64_t) block_size;
                    fwht_inplace(blk, (int) block_size);
                }
                uint16_t * dst = obuf.data() + (size_t) v * (size_t) n_embd;
                for (int64_t j = 0; j < n_embd; ++j) {
                    const float val = row[j] * had_scale * (float) signs[j];
                    dst[j] = ggml_fp32_to_fp16(val);
                }
                #pragma omp critical
                {
                    if (v >= next_report) {
                        printf("  %s: row %lld / %lld\n", tensor_names[t], (long long) v, (long long) n_vocab);
                        fflush(stdout);
                        next_report = v + n_vocab / 10;
                    }
                }
            }
        }

        char path[1024];
        snprintf(path, sizeof(path), "%s/%s", out_dir, out_files[t]);
        FILE * fo = fopen(path, "wb");
        if (!fo) { fprintf(stderr, "ERROR: cannot open %s\n", path); return 1; }
        const uint32_t hdr[2] = { (uint32_t) n_vocab, (uint32_t) n_embd };
        fwrite(hdr, sizeof(uint32_t), 2, fo);
        // write in chunks
        size_t written = 0;
        const size_t chunk = (size_t) n_embd * 4096;
        while (written < n_elem) {
            const size_t nw = (n_elem - written < chunk) ? (n_elem - written) : chunk;
            fwrite(obuf.data() + written, sizeof(uint16_t), nw, fo);
            written += nw;
        }
        fclose(fo);
        printf("  wrote %s (%zu bytes payload + 8 header)\n", path, n_elem * 2);
    }

    gguf_free(gguf);
    ggml_free(meta);
    printf("\n=== done ===\n");
    return 0;
}
