# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: BSD-3-Clause
#
# Modified from qtbase/cmake/FindWrapOpenGL.cmake: AGL block removed
# to support macOS SDKs where AGL.framework no longer exists (macOS 14+ SDK,
# shipped with Xcode 15.3+). Matches the fix Qt itself applied starting in 6.9.
#
# Qt's bundled version unconditionally appends "-framework AGL" as a link
# dependency of Qt6::Gui on Apple platforms when the AGL framework cannot be
# found via find_library(). Since AGL was removed from recent macOS SDKs,
# this makes every Qt Widgets/Quick app fail to link with:
#   ld: framework 'AGL' not found
#
# CMake resolves find_package(WrapOpenGL) by walking CMAKE_MODULE_PATH before
# falling back to Qt's own copy, so placing this file earlier in the search
# path overrides Qt's broken module without touching the Qt installation.

if(TARGET WrapOpenGL::WrapOpenGL)
    set(WrapOpenGL_FOUND ON)
    return()
endif()

set(WrapOpenGL_FOUND OFF)

find_package(OpenGL ${WrapOpenGL_FIND_VERSION})

if (OpenGL_FOUND)
    set(WrapOpenGL_FOUND ON)
    add_library(WrapOpenGL::WrapOpenGL INTERFACE IMPORTED)
    if(APPLE)
        get_target_property(__opengl_fw_lib_path OpenGL::GL IMPORTED_LOCATION)
        if(__opengl_fw_lib_path AND NOT __opengl_fw_lib_path MATCHES "/([^/]+)\\.framework$")
            get_filename_component(__opengl_fw_path "${__opengl_fw_lib_path}" DIRECTORY)
        endif()
        if(NOT __opengl_fw_path)
            set(__opengl_fw_path "-framework OpenGL")
        endif()
        target_link_libraries(WrapOpenGL::WrapOpenGL INTERFACE ${__opengl_fw_path})
    else()
        target_link_libraries(WrapOpenGL::WrapOpenGL INTERFACE OpenGL::GL)
    endif()
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(WrapOpenGL DEFAULT_MSG WrapOpenGL_FOUND)