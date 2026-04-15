# Install script for directory: /Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/project/android/build_64")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Install shared libraries without execute permission?
if(NOT DEFINED CMAKE_INSTALL_SO_NO_EXE)
  set(CMAKE_INSTALL_SO_NO_EXE "0")
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "TRUE")
endif()

# Set path to fallback-tool for dependency-resolution.
if(NOT DEFINED CMAKE_OBJDUMP)
  set(CMAKE_OBJDUMP "/Users/wuzewen/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objdump")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include" TYPE DIRECTORY FILES "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/transformers/llm/engine/include/" FILES_MATCHING REGEX "/[^/]*\\.hpp$")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/MNN" TYPE FILE FILES
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/MNNDefine.h"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/Interpreter.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/HalideRuntime.h"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/Tensor.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/ErrorCode.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/ImageProcess.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/Matrix.h"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/Rect.h"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/MNNForwardType.h"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/AutoTime.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/MNNSharedContext.h"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/MNN/expr" TYPE FILE FILES
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/Expr.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/ExprCreator.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/MathOp.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/NeuralNetWorkOp.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/Optimizer.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/Executor.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/Module.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/NeuralNetWorkOp.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/ExecutorScope.hpp"
    "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/include/MNN/expr/Scope.hpp"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  if(EXISTS "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libMNN.so" AND
     NOT IS_SYMLINK "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libMNN.so")
    file(RPATH_CHECK
         FILE "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libMNN.so"
         RPATH "")
  endif()
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib" TYPE SHARED_LIBRARY FILES "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/project/android/build_64/libMNN.so")
  if(EXISTS "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libMNN.so" AND
     NOT IS_SYMLINK "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libMNN.so")
    if(CMAKE_INSTALL_DO_STRIP)
      execute_process(COMMAND "/Users/wuzewen/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-strip" "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/libMNN.so")
    endif()
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for each subdirectory.
  include("/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/project/android/build_64/source/backend/opencl/cmake_install.cmake")
  include("/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/project/android/build_64/express/cmake_install.cmake")
  include("/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/project/android/build_64/tools/cv/cmake_install.cmake")
  include("/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/project/android/build_64/tools/audio/cmake_install.cmake")
  include("/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/project/android/build_64/tools/converter/cmake_install.cmake")

endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
if(CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/project/android/build_64/install_local_manifest.txt"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
if(CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_COMPONENT MATCHES "^[a-zA-Z0-9_.+-]+$")
    set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INSTALL_COMPONENT}.txt")
  else()
    string(MD5 CMAKE_INST_COMP_HASH "${CMAKE_INSTALL_COMPONENT}")
    set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INST_COMP_HASH}.txt")
    unset(CMAKE_INST_COMP_HASH)
  endif()
else()
  set(CMAKE_INSTALL_MANIFEST "install_manifest.txt")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/Users/wuzewen/Projects/Omni/OmniFlow/runtime/openomnibot-merge-worktree/third_party/mnn_android/project/android/build_64/${CMAKE_INSTALL_MANIFEST}"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
