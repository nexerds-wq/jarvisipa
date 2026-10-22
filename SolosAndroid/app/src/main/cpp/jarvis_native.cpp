#include <jni.h>
#include <string>
#include <vector>
#include <mutex>
#include <algorithm>
#include "llama.h"

static std::mutex model_lock;
static llama_model * g_model = nullptr;
static bool initialized = false;

static std::string to_utf8(JNIEnv * env, jstring value) {
    if (!value) return {};
    const char * chars = env->GetStringUTFChars(value, nullptr);
    if (!chars) return {};
    std::string s(chars);
    env->ReleaseStringUTFChars(value, chars);
    return s;
}
static void fill(llama_batch_ext * b, const llama_token * toks, int count, int position) {
    llama_batch_ext_clear(b);
    for(int i=0;i<count;i++){
        int index=llama_batch_ext_add_token(b,0,toks[i]);
        llama_pos position_i=position+i;
        llama_batch_ext_set_pos(b,index,&position_i);
    }
    llama_batch_ext_set_output_logits(b,count-1,true);
}
extern "C" JNIEXPORT jstring JNICALL
Java_com_solos_legacyhud_NativeJarvis_load(JNIEnv * env, jclass, jstring file) {
    std::lock_guard<std::mutex> guard(model_lock);
    if(g_model) return env->NewStringUTF("READY");
    if(!initialized){llama_backend_init(); initialized=true;}
    std::string path=to_utf8(env,file);
    llama_model_params params=llama_model_default_params();
    params.n_gpu_layers=0;
    g_model=llama_model_load_from_file(path.c_str(),params);
    if(!g_model) return env->NewStringUTF("AI could not load: not enough RAM or invalid GGUF.");
    return env->NewStringUTF("READY");
}
extern "C" JNIEXPORT jstring JNICALL
Java_com_solos_legacyhud_NativeJarvis_answer(JNIEnv * env, jclass, jstring query) {
    std::lock_guard<std::mutex> guard(model_lock);
    if(!g_model)return env->NewStringUTF("AI model isn't ready.");
    std::string question=to_utf8(env,query);
    if(question.size()>380)question.resize(380);
    std::string prompt="<|im_start|>system\nYou are Jarvis, a small offline AI for smart glasses. "
        "Give short, clear, factual answers in 1-2 sentences. You have no internet. "
        "If you don't know, say you don't know.\n<|im_end|>\n<|im_start|>user\n"+
        question+"\n<|im_end|>\n<|im_start|>assistant\n";
    const llama_vocab * vocab=llama_model_get_vocab(g_model);
    int count=-llama_tokenize(vocab,prompt.c_str(),prompt.size(),nullptr,0,true,true);
    if(count<=0||count>320)return env->NewStringUTF("Question is too long.");
    std::vector<llama_token> tokens(count);
    if(llama_tokenize(vocab,prompt.c_str(),prompt.size(),tokens.data(),count,true,true)<0)
        return env->NewStringUTF("Question could not be encoded.");
    llama_context_params params=llama_context_default_params();
    params.n_ctx=512;
    params.n_batch=std::max(128,count);
    params.n_threads=2;
    params.n_threads_batch=2;
    llama_context * ctx=llama_init_from_model(g_model,params);
    if(!ctx)return env->NewStringUTF("Not enough free RAM for AI answer.");
    llama_sampler * sampler=llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(sampler,llama_sampler_init_greedy());
    llama_batch_ext * batch=llama_batch_ext_init(ctx);
    if(!batch){llama_sampler_free(sampler);llama_free(ctx);return env->NewStringUTF("Memory allocation failed.");}
    fill(batch,tokens.data(),count,0);
    std::string result;
    int pos=0,batched=count;
    for(int i=0;i<100&&pos+batched<500;i++){
        if(llama_process(ctx,LLAMA_PROCESS_TYPE_DECODE,batch)!=0)break;
        pos+=batched;
        llama_token token=llama_sampler_sample(sampler,ctx,-1);
        if(llama_vocab_is_eog(vocab,token))break;
        char buf[256];
        int n=llama_token_to_piece(vocab,token,buf,sizeof(buf),0,true);
        if(n>0)result.append(buf,n);
        auto end=result.find("<|im_end|>");
        if(end!=std::string::npos){result.resize(end);break;}
        if(result.size()>600)break;
        fill(batch,&token,1,pos);batched=1;
    }
    llama_batch_ext_free(batch);
    llama_sampler_free(sampler);
    llama_free(ctx);
    if(result.empty()) result="Sorry, I couldn't answer that. Try asking something shorter.";
    // Ensure string ends on complete UTF8 codepoint for JNI.
    size_t end=result.size();
    while(end>0&&(static_cast<unsigned char>(result[end-1])&0xc0)==0x80)end--;
    if(end<result.size()){
        unsigned char lead=static_cast<unsigned char>(result[end-1]);
        int need=(lead&0xe0)==0xc0?2:(lead&0xf0)==0xe0?3:(lead&0xf8)==0xf0?4:1;
        if(static_cast<int>(result.size()-end+1)<need)result.resize(end-1);
    }
    return env->NewStringUTF(result.c_str());
}
