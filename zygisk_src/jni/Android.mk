# Rox2 Zygisk module - NDK build file
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := Rox2
LOCAL_SRC_FILES := module.cpp
LOCAL_C_INCLUDES := $(LOCAL_PATH)
LOCAL_CPPFLAGS := -std=c++17 -fno-rtti -fno-exceptions -Wall -Wextra -Wno-unused-parameter
LOCAL_LDFLAGS := -Wl,-z,relro -Wl,-z,now
LOCAL_MODULE_TAGS := optional
# liblog / libandroid / libdl are pulled in by name via LDLIBS so the
# linker resolves __android_log_print without needing a module alias.
LOCAL_LDLIBS := -llog -landroid -ldl

include $(BUILD_SHARED_LIBRARY)
