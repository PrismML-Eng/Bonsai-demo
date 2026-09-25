// extract_feats_tf.cpp
// Feature-only teacher-force extractor for the server-generation route.
// Reads a jsonl of {"tokens":[...ids...], "n_prompt":N} (produced by gen_client.py),
// teacher-forces each full sequence through Bonsai 2, and writes the BON2 feature format
// (5 input-layer taps + post-final-norm final_hidden). loss_mask=1 on completion tokens.
// No generation and no embeddings-mode toggling -> stable graph, fast prefill.
//
// Output: header "BON2"(4)|embd u32|n_taps u32=5|tap_layers[5] u32={6,20,34,48,62}
//   per sample: n u32 | tokens i32[n] | loss_mask u8[n] | taps f32[n*5*embd] | final_hidden f32[n*embd]
//
// Every write is checked. On a short write (full disk, I/O error) or a failed close, the
// tool reports the sample, removes the partial output file, and exits with status 1.

#include "llama.h"
#include "llama-ext.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <ctime>
#include <string>
#include <vector>
#include <fstream>
#include <sys/stat.h>

// parse {"tokens":[...], "n_prompt":N}; returns false on parse failure
static bool parse_line(const std::string & s, std::vector<int32_t> & toks, int & n_prompt) {
    toks.clear(); n_prompt = -1;
    size_t tp = s.find("\"tokens\"");
    if (tp == std::string::npos) return false;
    size_t lb = s.find('[', tp);
    if (lb == std::string::npos) return false;
    size_t rb = s.find(']', lb);
    if (rb == std::string::npos) return false;
    size_t i = lb + 1;
    while (i < rb) {
        while (i < rb && (s[i]==' '||s[i]==',')) ++i;
        if (i >= rb) break;
        long v = strtol(s.c_str()+i, nullptr, 10);
        toks.push_back((int32_t)v);
        while (i < rb && s[i] != ',') ++i;
    }
    size_t np = s.find("\"n_prompt\"");
    if (np == std::string::npos) return false;
    size_t c = s.find(':', np);
    if (c == std::string::npos) return false;
    n_prompt = (int) strtol(s.c_str()+c+1, nullptr, 10);
    return !toks.empty() && n_prompt >= 0 && n_prompt <= (int)toks.size();
}

// write count items of size bytes; false on a short write
static bool write_all(FILE * f, const void * p, size_t size, size_t count) {
    return fwrite(p, size, count, f) == count;
}

int main(int argc, char ** argv) {
    // Defaults resolve against BONSAI_ROOT (the demo checkout), else the cwd.
    const char * root_env = getenv("BONSAI_ROOT");
    const std::string root = (root_env && *root_env) ? root_env : ".";
    const std::string default_model = root + "/models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf";
    const std::string default_data  = root + "/tools/dspark-retrain/prompts_gen_batch2.jsonl";
    const std::string default_out   = root + "/tools/dspark-retrain/feats/batch2.bin";
    const char * model_path = (argc>1)?argv[1] : default_model.c_str();
    const char * data_path  = (argc>2)?argv[2] : default_data.c_str();
    const char * out_path   = (argc>3)?argv[3] : default_out.c_str();
    const int max_samples   = (argc>4)?atoi(argv[4]) : 100000;
    // create the output directory if it is missing
    { std::string d(out_path); size_t sl = d.rfind('/'); if (sl != std::string::npos) { d.resize(sl); mkdir(d.c_str(), 0755); } }

    const uint32_t tap_layers[5] = {6,20,34,48,62};
    const int n_taps = 5;

    printf("=== Bonsai 2 feature-only teacher-force extractor ===\n");
    printf("model:%s\ndata:%s\nout:%s\n", model_path, data_path, out_path);

    llama_backend_init();
    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 99;
    llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (!model){ fprintf(stderr,"ERROR: model load failed\n"); return 1; }
    const int n_embd = llama_model_n_embd(model);

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx=2048; cparams.n_batch=2048; cparams.n_ubatch=2048;
    cparams.pooling_type = LLAMA_POOLING_TYPE_NONE;
    cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
    llama_context * ctx = llama_init_from_model(model, cparams);
    if (!ctx){ fprintf(stderr,"ERROR: ctx create failed\n"); return 1; }

    // features-only: embeddings on + taps on for the whole run (no toggling)
    llama_set_embeddings(ctx, true);
    for (int l=0;l<n_taps;++l) llama_set_embeddings_layer_inp(ctx, tap_layers[l], true);
    llama_memory_t mem = llama_get_memory(ctx);

    FILE * fout = fopen(out_path,"wb");
    if (!fout){ fprintf(stderr,"ERROR: cannot open %s\n",out_path); return 1; }
    int n_done=0, n_skip=0; size_t total_tok=0, total_gen=0;
    // report a short write, remove the partial output file, and exit with status 1
    auto write_fail = [&](const char * what) -> int {
        fprintf(stderr,"ERROR: short write (%s) to %s after %d complete samples: %s\n",
                what,out_path,n_done,strerror(errno));
        fclose(fout); remove(out_path);
        llama_free(ctx); llama_model_free(model); llama_backend_free();
        return 1;
    };
    const char magic[4]={'B','O','N','2'};
    uint32_t embd_u=(uint32_t)n_embd, taps_u=(uint32_t)n_taps;
    if (!write_all(fout,magic,1,4) || !write_all(fout,&embd_u,4,1) ||
        !write_all(fout,&taps_u,4,1) || !write_all(fout,tap_layers,4,5)) return write_fail("header");

    std::ifstream fin(data_path);
    if (!fin.is_open()){
        // the header is already on disk: remove the partial output file
        fprintf(stderr,"ERROR: cannot open %s\n",data_path);
        fclose(fout); remove(out_path);
        llama_free(ctx); llama_model_free(model); llama_backend_free();
        return 1;
    }

    std::string line;
    struct timespec t0; clock_gettime(CLOCK_MONOTONIC,&t0);
    std::vector<int32_t> toks; std::vector<float> taps, final_hidden;

    while (std::getline(fin,line) && n_done<max_samples) {
        if (line.empty()) continue;
        int n_prompt=-1;
        if (!parse_line(line, toks, n_prompt)) { n_skip++; continue; }
        const int n=(int)toks.size();
        if (n<2 || n>cparams.n_ctx) { n_skip++; continue; }

        std::vector<uint8_t> loss_mask(n,0);
        for (int i=n_prompt;i<n;++i) loss_mask[i]=1;

        llama_memory_clear(mem, true);
        llama_batch fb = llama_batch_init(n,0,1);
        for (int i=0;i<n;++i){ fb.token[i]=toks[i]; fb.pos[i]=i; fb.n_seq_id[i]=1; fb.seq_id[i][0]=0; fb.logits[i]=true; }
        fb.n_tokens=n;
        if (llama_decode(ctx, fb)!=0){ llama_batch_free(fb); n_skip++; continue; }
        llama_batch_free(fb);

        taps.assign((size_t)n*n_taps*n_embd, 0.0f);
        bool ok=true;
        for (int l=0;l<n_taps;++l){ float * e=llama_get_embeddings_layer_inp(ctx, tap_layers[l]);
            if(!e){ok=false;break;}
            for (int t=0;t<n;++t) memcpy(&taps[((size_t)t*n_taps+l)*n_embd], &e[(size_t)t*n_embd], n_embd*sizeof(float)); }
        if(!ok){ n_skip++; continue; }
        final_hidden.assign((size_t)n*n_embd, 0.0f);
        for (int t=0;t<n;++t){ const float * em=llama_get_embeddings_ith(ctx,t); if(!em){ok=false;break;}
            memcpy(&final_hidden[(size_t)t*n_embd], em, n_embd*sizeof(float)); }
        if(!ok){ n_skip++; continue; }

        uint32_t n_u=(uint32_t)n;
        if (!write_all(fout,&n_u,4,1) ||
            !write_all(fout,toks.data(),sizeof(int32_t),n) ||
            !write_all(fout,loss_mask.data(),1,n) ||
            !write_all(fout,taps.data(),sizeof(float),taps.size()) ||
            !write_all(fout,final_hidden.data(),sizeof(float),final_hidden.size())) return write_fail("sample");
        n_done++; total_tok+=n; total_gen+=(n-n_prompt);
        if (n_done%50==0){ struct timespec t1; clock_gettime(CLOCK_MONOTONIC,&t1);
            double el=(t1.tv_sec-t0.tv_sec)+(t1.tv_nsec-t0.tv_nsec)/1e9;
            printf("  feat %d (skip %d) | tok %zu gen %zu | %.1f tok/s | %.1fs\n",
                   n_done,n_skip,total_tok,total_gen,total_tok/el,el); fflush(stdout);
            if (fflush(fout)!=0) return write_fail("flush"); }
    }
    // fclose flushes the last buffer; a failure here is a short write as well
    if (fclose(fout)!=0) {
        fprintf(stderr,"ERROR: close of %s failed after %d complete samples: %s\n",out_path,n_done,strerror(errno));
        remove(out_path);
        llama_free(ctx); llama_model_free(model); llama_backend_free();
        return 1;
    }
    struct timespec t1; clock_gettime(CLOCK_MONOTONIC,&t1);
    double el=(t1.tv_sec-t0.tv_sec)+(t1.tv_nsec-t0.tv_nsec)/1e9;
    printf("\n=== done === samples=%d skip=%d tokens=%zu gen=%zu time=%.1fs (%.1f tok/s)\nout:%s\n",
           n_done,n_skip,total_tok,total_gen,el,total_tok/el,out_path);
    llama_free(ctx); llama_model_free(model); llama_backend_free();
    return 0;
}
