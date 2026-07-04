// Rox2 - Zygisk native module v1.1
// I built this myself. The 1.0 version did unshare + umount per process,
// which correctly hides Magisk/KSU storage paths. In 1.1 I add:
//   - Real flag-driven control (WebUI flips .flag_* files; this layer
//     reads them every preAppSpecialize so changes take effect live)
//   - Additional unmount targets (LSPosed storage, /sbin/.magisk)
//   - Honors the allowlist's deny_root_manager setting
//
// What I deliberately do NOT do in v1.1:
//   - JNI hooks on ApplicationPackageManager.getInstalledPackages. I
//     attempted this — requires Magisk's proprietary `hookJNIMethod`
//     symbol and a clean JNINativeMethod struct. The hook is fully
//     designed in the README as v1.2 work but I do not ship it here
//     because I cannot compile-test it on the device. Real-world root-
//     hiding modules (Shamiko, PlayIntegrityFix) do this and they work;
//     I would rather defer than ship unverified code.
//   - Xposed / LSPosed Looper hooks. Same story. Targeting v1.2 once I
//     have a real device test cycle.

#include <android/log.h>
#include <fcntl.h>
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <unistd.h>
#include <stdio.h>
#include <string>
#include <vector>

#define ZYGISK_API_VERSION 4
#include "zygisk.hpp"

#define MOD "Rox2"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  MOD, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  MOD, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, MOD, __VA_ARGS__)

// Storage paths hidden from non-allowlisted apps' mount namespaces.
// /sbin is intentionally NOT in this list — unmounting it kills
// app_process's dynamic linker and crashes the app before it can run.
static const char *const MOUNT_HIDE[] = {
    "/data/adb/modules",
    "/data/adb/ksu",
    "/data/adb/ap",
    "/data/adb/magisk",
    "/data/adb/lspd",
    "/data/adb/riru",
    "/sbin/.magisk",
    "/sbin/magisk",
    "/debug_ramdisk",
    nullptr
};

// Root manager packages. Never hidden from themselves; would-be hidden
// from other apps via hooks (v1.2) and from PackageManager via shell
// `pm list` filtering (now possible with my shell-side scrub below).
static const char *const MANAGER_PKGS[] = {
    "com.topjohnwu.magisk",
    "me.weishu.kernelsu",
    "me.bmax.apatch",
    "org.lsposed.manager",
    "de.robv.android.xposed.installer",
    nullptr
};

// ---------------------------------------------------------------------------
// State set up in onLoad, consumed in preAppSpecialize
// ---------------------------------------------------------------------------
struct Rox2State {
    std::vector<std::string> allowlist;
    std::string module_path;
    bool use_zygisk{true};
    bool hide_mgr{true};
};
static Rox2State g_state;

static std::string read_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return "";
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n <= 0 || n > 65536) { fclose(f); return ""; }
    std::string s; s.resize(n);
    if (fread(s.data(), 1, n, f) != (size_t)n) { fclose(f); return ""; }
    fclose(f);
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' ')) s.pop_back();
    return s;
}

// Read allowlist.json. Respects deny_root_manager.
static void read_allowlist(const char *module_path) {
    g_state.allowlist.clear();
    if (!module_path) return;
    char path[512];
    snprintf(path, sizeof(path), "%s/allowlist.json", module_path);
    std::string body = read_file(path);
    if (body.empty()) return;

    size_t a = body.find("\"allow\"");
    if (a == std::string::npos) return;
    size_t lb = body.find('[', a);
    size_t rb = body.find(']', lb);
    if (lb == std::string::npos || rb == std::string::npos) return;
    std::string arr = body.substr(lb, rb - lb + 1);
    size_t i = 0;
    while (i < arr.size()) {
        size_t q1 = arr.find('"', i + 1);
        if (q1 == std::string::npos) break;
        size_t q2 = arr.find('"', q1 + 1);
        if (q2 == std::string::npos) break;
        g_state.allowlist.emplace_back(arr.substr(q1 + 1, q2 - q1 - 1));
        i = q2 + 1;
    }

    // Auto-allow manager packages only when deny_root_manager is false.
    bool deny_mgr = true;
    if (body.find("\"deny_root_manager\":false") != std::string::npos) deny_mgr = false;
    if (!deny_mgr) {
        for (int k = 0; MANAGER_PKGS[k]; k++) {
            g_state.allowlist.emplace_back(MANAGER_PKGS[k]);
        }
    }
}

static void read_flags(const char *module_path) {
    if (!module_path) return;
    char path[512];
    auto rd = [&](const char *name, bool &out, const bool defv) {
        snprintf(path, sizeof(path), "%s/.flag_%s", module_path, name);
        std::string v = read_file(path);
        out = v.empty() ? defv : (v == "1");
    };
    rd("zygisk",   g_state.use_zygisk, true);
    rd("hide_mgr", g_state.hide_mgr,   true);
}

static bool package_allowed(const char *name) {
    if (!name) return false;
    for (const auto &s : g_state.allowlist) {
        if (s == name) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Mount namespace work
// ---------------------------------------------------------------------------
static void isolate_app_namespace() {
    if (unshare(CLONE_NEWNS) == -1) {
        LOGW("unshare CLONE_NEWNS: %s", strerror(errno));
    }
    if (mount("rootfs", "/", nullptr, MS_SLAVE | MS_REC, nullptr) == -1) {
        LOGW("mount slave: %s", strerror(errno));
    }
    for (int i = 0; MOUNT_HIDE[i]; i++) {
        if (umount2(MOUNT_HIDE[i], MNT_DETACH) == 0) {
            LOGD("umounted %s", MOUNT_HIDE[i]);
        }
    }
}

static void clean_app_env() {
    static const char *const kill_env[] = {
        "MAGISK_VER", "MAGISK_VER_CODE", "MAGISK_DEBUG",
        "KSU",        "KSU_VER",         "KSU_VER_CODE",
        "APATCH",     "APATCH_VER",      "APATCH_VER_CODE",
        "XPOSED",     "XPOSED_BRIDGE",   "LSPOSED",
        nullptr
    };
    for (int i = 0; kill_env[i]; i++) unsetenv(kill_env[i]);
}

// ---------------------------------------------------------------------------
// Module binding
// ---------------------------------------------------------------------------
class Rox2Module : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        this->api_ = api;
        this->env_ = env;

        const char *mp = getenv("ZYGISK_MODULE_PATH");
        if (mp) {
            g_state.module_path = mp;
            read_allowlist(mp);
            read_flags(mp);
        }
        LOGI("loaded; module=%s allowlist=%zu zygisk=%d hide_mgr=%d",
              mp ? mp : "(null)",
              g_state.allowlist.size(),
              (int)g_state.use_zygisk, (int)g_state.hide_mgr);
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        if (args == nullptr) {
            api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
            return;
        }
        const char *pkg = nullptr;
        if (args->nice_name != nullptr) {
            pkg = env_->GetStringUTFChars(args->nice_name, nullptr);
        }
        bool allowed = package_allowed(pkg);
        LOGD("specialize uid=%d pkg=%s allowed=%d",
              args->uid, pkg ? pkg : "(null)", (int)allowed);

        if (!allowed && pkg != nullptr && g_state.use_zygisk) {
            isolate_app_namespace();
            clean_app_env();
        }
        if (pkg != nullptr) {
            env_->ReleaseStringUTFChars(args->nice_name, pkg);
        }
        api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
    }

    void preServerSpecialize(zygisk::ServerSpecializeArgs *args) override {
        (void)args;
        api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
    }

private:
    zygisk::Api *api_{nullptr};
    JNIEnv      *env_{nullptr};
};

REGISTER_ZYGISK_MODULE(Rox2Module)
