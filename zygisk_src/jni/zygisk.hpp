// Minimal Zygisk API stubs.
// In a real build I'd import the prebuilt zygisk headers shipped by Magisk,
// but to keep this repo self-contained I declare the symbols I use inline.
// The build script's Android.mk imports the Zygisk prebuilts at link time.
#pragma once

#include <jni.h>
#include <unistd.h>
#include <stdint.h>

#define ZYGISK_API_VERSION 4

namespace zygisk {

enum class Option { DLCLOSE_MODULE_LIBRARY = 1 };

struct AppSpecializeArgs {
    JNIEnv       *env;
    jclass        class_loader;
    jstring       nice_name;
    jstring       sourceDir;
    jstring       dataDir;
    jintArray     splitSources;
    jint          uid;
    jint          gid;
    jintArray     gids;
    jint          runtimeFlags;
    jintArray     allowedPackages;
    jboolean      is_child_zygote;
    jboolean      is_system_server;
};

struct ServerSpecializeArgs {
    JNIEnv *env;
};

class Api {
public:
    virtual void setOption(Option opt) = 0;
    virtual int  getFlags()             = 0;
    virtual ~Api() = default;
};

class ModuleBase {
public:
    virtual void onLoad(Api *api, JNIEnv *env) {}
    virtual void preAppSpecialize(AppSpecializeArgs *args) {}
    virtual void postAppSpecialize(const AppSpecializeArgs *args) {}
    virtual void preServerSpecialize(ServerSpecializeArgs *args) {}
    virtual ~ModuleBase() = default;
protected:
    Api *api_{nullptr};
    JNIEnv *env_{nullptr};
};

}  // namespace zygisk

#define REGISTER_ZYGISK_MODULE(class_name)                                  \
    extern "C" __attribute__((visibility("default")))                       \
    zygisk::ModuleBase *zygisk_module_entry() {                             \
        static class_name instance;                                         \
        return &instance;                                                   \
    }

#define MODULE_CONCAT_(a, b) a##b
#define MODULE_CONCAT(a, b)  MODULE_CONCAT_(a, b)
#define MODULE_VAR(name)     MODULE_CONCAT(name, __LINE__)
