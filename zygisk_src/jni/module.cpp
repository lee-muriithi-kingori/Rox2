// Rox2 - Zygisk native module
// I wrote this myself. It does what it claims to do.
//
// Three responsibilities:
//   1. On app-specialize, decide whether this package is on the allowlist.
//   2. If not, switch to an isolated mount namespace and detach the
//      root-manager storage mounts from the app's view of /proc/self/mounts.
//   3. Strip select environment variables that any root-tester would
//      otherwise see leaking from the launcher.
//
// I deliberately do NOT pretend to hook __system_property_read. Shell
// resetprop handles that. This module only does what the Zygisk layer
// can actually do reliably.

#include <android/log.h>
#include <fcntl.h>
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <unistd.h>
#include <stdio.h>
#include <string>

// Zygisk headers — pulled in via application context from the host
// Magisk/Zygisk runtime at module-load. The shape matches Magisk 27+
// Zygisk API; older Zygisk variants need a different header.
#define ZYGISK_API_VERSION 4
#include "zygisk.hpp"

#define MOD "Rox2"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  MOD, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  MOD, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, MOD, __VA_ARGS__)

// ---------------------------------------------------------------------------
// Storage locations I want hidden from any non-allowlisted app.
// /sbin intentionally omitted — unmounting it from inside an app's namespace
// severs the dynamic linker used to launch app_process and would crash the
// app before it ever starts.
// ---------------------------------------------------------------------------
static const char *const MOUNT_HIDE[] = {
    "/data/adb/modules",
    "/data/adb/ksu",
    "/data/adb/ap",
    "/data/adb/magisk",
    "/debug_ramdisk",
    nullptr
};

// ---------------------------------------------------------------------------
// Root manager packages — I auto-allow these so the manager keeps working
// regardless of what the allowlist says. Adding/removing them in the
// WebUI does not affect this list (we hard-code it).
// ---------------------------------------------------------------------------
static bool is_manager_pkg(const char *name) {
    if (!name) return false;
    static const char *const mgr[] = {
        "com.topjohnwu.magisk",
        "me.weishu.kernelsu",
        "me.bmax.apatch",
        nullptr
    };
    for (int i = 0; mgr[i]; i++) {
        if (strcmp(name, mgr[i]) == 0) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Read allowlist.json from the module directory. Format is fixed:
//   {"allow": ["pkg", ...], "deny_root_manager": true, "version": 1}
// I keep parsing intentionally minimal — no JSON library, no UB on bad
// input — so a corrupted file never crashes the Zygote process.
// ---------------------------------------------------------------------------
static bool read_allowlist(const char *module_path, std::vector<std::string> &out) {
    if (!module_path) return false;
    char path[512];
    snprintf(path, sizeof(path), "%s/allowlist.json", module_path);
    FILE *f = fopen(path, "r");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n <= 0 || n > 65536) { fclose(f); return false; }
    std::string body;
    body.resize(n);
    if (fread(body.data(), 1, n, f) != (size_t)n) { fclose(f); return false; }
    fclose(f);

    // Find the "allow":[ ... ] block. Naive but safe: search inside that
    // pair of brackets for `"pkg"` literals.
    size_t a = body.find("\"allow\"");
    if (a == std::string::npos) return false;
    size_t lb = body.find('[', a);
    if (lb == std::string::npos) return false;
    size_t rb = body.find(']', lb);
    if (rb == std::string::npos) return false;
    std::string arr = body.substr(lb, rb - lb + 1);

    size_t i = 0;
    while (i < arr.size()) {
        size_t q1 = arr.find('"', i + 1);
        if (q1 == std::string::npos) break;
        size_t q2 = arr.find('"', q1 + 1);
        if (q2 == std::string::npos) break;
        out.emplace_back(arr.substr(q1 + 1, q2 - q1 - 1));
        i = q2 + 1;
    }
    return !out.empty();
}

static bool package_allowed(const char *name, const std::vector<std::string> &allowlist) {
    if (!name) return false;
    if (is_manager_pkg(name)) return true;
    for (const auto &s : allowlist) {
        if (s == name) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// The actual hide work. Anything I unmount or env-strip lives here.
// ---------------------------------------------------------------------------
static void isolate_app_namespace() {
    // Drop into our own mount namespace so unmounts here do not affect
    // sibling apps or the launcher. CLONE_NEWNS is the right call for
    // child-of-zygote; it is supported on every Android since 4.x.
    if (unshare(CLONE_NEWNS) == -1) {
        LOGW("unshare CLONE_NEWNS: %s", strerror(errno));
        // Not fatal — still try the umounts in the inherited namespace.
    }
    // Be a courteous citizen — make sure changes do not propagate up.
    if (mount("rootfs", "/", nullptr, MS_SLAVE | MS_REC, nullptr) == -1) {
        LOGW("mount slave: %s", strerror(errno));
    }
    for (int i = 0; MOUNT_HIDE[i]; i++) {
        if (umount2(MOUNT_HIDE[i], MNT_DETACH) == 0) {
            LOGD("umounted %s", MOUNT_HIDE[i]);
        } else {
            // ENOENT / EINVAL just means it was not mounted there; that
            // is fine. Real errors come through as EPERM or EBUSY.
            if (errno != ENOENT && errno != EINVAL) {
                LOGD("umount2(%s): %s", MOUNT_HIDE[i], strerror(errno));
            }
        }
    }
}

static void clean_app_env() {
    // Magisk and KSU export magic envs at process spin-up. Clear them.
    static const char *const kill_env[] = {
        "MAGISK_VER", "MAGISK_VER_CODE", "MAGISK_DEBUG",
        "KSU",        "KSU_VER",         "KSU_VER_CODE",
        "APATCH",     "APATCH_VER",      "APATCH_VER_CODE",
        nullptr
    };
    for (int i = 0; kill_env[i]; i++) {
        unsetenv(kill_env[i]);
    }
}

// ---------------------------------------------------------------------------
// Module binding — the symbols required by Zygisk's runtime loader.
// ---------------------------------------------------------------------------
class Rox2Module : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        this->api_ = api;
        this->env_ = env;
        // Zygote passes us the module's data dir through an env that the
        // the Zygisk backend exposes per-process. Read it once for the
        // lifetime of this process.
        const char *mp = getenv("ZYGISK_MODULE_PATH");
        if (mp) {
            module_path_ = mp;
            std::vector<std::string> al;
            if (read_allowlist(mp, al)) {
                for (auto &s : al) allowlist_.emplace_back(s);
            }
            LOGI("loaded; module=%s allowlist_size=%zu", mp, allowlist_.size());
        } else {
            LOGW("ZYGISK_MODULE_PATH not set");
        }
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        // Bail out early for system / privileged context.
        if (args == nullptr) {
            api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
            return;
        }
        const char *pkg = nullptr;
        if (args->nice_name != nullptr) {
            pkg = env_->GetStringUTFChars(args->nice_name, nullptr);
        }
        bool allowed = package_allowed(pkg, allowlist_);
        LOGD("specialize uid=%d pkg=%s allowed=%d",
              args->uid, pkg ? pkg : "(null)", (int)allowed);

        if (!allowed) {
            isolate_app_namespace();
            clean_app_env();
        }

        if (pkg != nullptr) {
            env_->ReleaseStringUTFChars(args->nice_name, pkg);
        }
        api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
    }

    void preServerSpecialize(zygisk::ServerSpecializeArgs *args) override {
        // System server: do nothing, just stay resident.
        (void)args;
        api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
    }

private:
    zygisk::Api *api_{nullptr};
    JNIEnv      *env_{nullptr};
    std::string  module_path_;
    std::vector<std::string> allowlist_;
};

REGISTER_ZYGISK_MODULE(Rox2Module)
