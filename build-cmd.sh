#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# bleat on references to undefined shell variables
set -u

URIPARSER_SOURCE_DIR="uriparser"
VERSION_HEADER_FILE="${URIPARSER_SOURCE_DIR}/include/uriparser/UriBase.h"
VERSION_MACRO="URI_VER_ANSI"


if [ -z "$AUTOBUILD" ] ; then 
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

top="$(pwd)"
stage="$top"/stage

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$AUTOBUILD" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

pushd "$URIPARSER_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        windows*)
            load_vsvars

            # populate version_file
            cl /DVERSION_HEADER_FILE="\"$VERSION_HEADER_FILE\"" \
               /DVERSION_MACRO="$VERSION_MACRO" \
               /Fo"$(cygpath -w "$stage/version.obj")" \
               /Fe"$(cygpath -w "$stage/version.exe")" \
               "$(cygpath -w "$top/version.c")"
            "$stage/version.exe" > "$stage/VERSION.txt"
            rm "$stage"/version.{obj,exe}

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                archflags="/arch:SSE2"
            else
                archflags=""
            fi

            mkdir -p "$stage/include/uriparser"
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            mkdir -p "build_debug"
            pushd "build_debug"
                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" -T host="$AUTOBUILD_WIN_VSHOST" .. -DBUILD_SHARED_LIBS=OFF \
                    -DURIPARSER_BUILD_DOCS=OFF -DURIPARSER_BUILD_TESTS=OFF -DURIPARSER_BUILD_TOOLS=OFF

                cmake --build . --config Debug --clean-first

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi

                cp -a "Debug/uriparser.lib" "$stage/lib/debug/"
            popd

            mkdir -p "build_release"
            pushd "build_release"
                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" -T host="$AUTOBUILD_WIN_VSHOST" .. -DBUILD_SHARED_LIBS=OFF \
                    -DURIPARSER_BUILD_DOCS=OFF -DURIPARSER_BUILD_TESTS=OFF -DURIPARSER_BUILD_TOOLS=OFF

                cmake --build . --config Release --clean-first

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi

                cp -a "Release/uriparser.lib" "$stage/lib/release/"
            popd

            cp -a include/uriparser/*.h "$stage/include/uriparser"
        ;;

        darwin*)
            # Setup osx sdk platform
            SDKNAME="macosx"
            export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)

            # Deploy Targets
            X86_DEPLOY=10.15
            ARM64_DEPLOY=11.0

            # Setup build flags
            ARCH_FLAGS_X86="-arch x86_64 -mmacosx-version-min=${X86_DEPLOY} -isysroot ${SDKROOT} -msse4.2"
            ARCH_FLAGS_ARM64="-arch arm64 -mmacosx-version-min=${ARM64_DEPLOY} -isysroot ${SDKROOT}"
            DEBUG_COMMON_FLAGS="-O0 -g -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="-O3 -g -fPIC -DPIC -fstack-protector-strong"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC"
            DEBUG_LDFLAGS="-Wl,-headerpad_max_install_names"
            RELEASE_LDFLAGS="-Wl,-headerpad_max_install_names"

            # populate version_file
            cc -arch x86_64 -arch arm64 -isysroot ${SDKROOT} -DVERSION_HEADER_FILE="\"$VERSION_HEADER_FILE\"" \
               -DVERSION_MACRO="$VERSION_MACRO" \
               -o "$stage/version" "$top/version.c"
            "$stage/version" > "$stage/VERSION.txt"
            rm "$stage/version"

            # x86 Deploy Target
            export MACOSX_DEPLOYMENT_TARGET=${X86_DEPLOY}

            mkdir -p "build_debug_x86"
            pushd "build_debug_x86"
                CFLAGS="$ARCH_FLAGS_X86 $DEBUG_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_X86 $DEBUG_CXXFLAGS" \
                CPPFLAGS="$ARCH_FLAGS_X86 $DEBUG_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_X86 $DEBUG_LDFLAGS" \
                cmake .. -GXcode -DBUILD_SHARED_LIBS=OFF -DURIPARSER_BUILD_DOCS=OFF \
                    -DURIPARSER_BUILD_TESTS=OFF -DURIPARSER_BUILD_TOOLS=OFF \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_X86 $DEBUG_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_X86 $DEBUG_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="0" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=OFF \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=OFF \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/debug_x86"

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
                CPPFLAGS="$ARCH_FLAGS_X86 $RELEASE_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_X86 $RELEASE_LDFLAGS" \
                cmake .. -GXcode -DBUILD_SHARED_LIBS=OFF -DURIPARSER_BUILD_DOCS=OFF \
                    -DURIPARSER_BUILD_TESTS=OFF -DURIPARSER_BUILD_TOOLS=OFF \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="3" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/release_x86"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # ARM64 Deploy Target
            export MACOSX_DEPLOYMENT_TARGET=${ARM64_DEPLOY}

            mkdir -p "build_debug_arm64"
            pushd "build_debug_arm64"
                CFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CXXFLAGS" \
                CPPFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_LDFLAGS" \
                cmake .. -GXcode -DBUILD_SHARED_LIBS=OFF -DURIPARSER_BUILD_DOCS=OFF \
                    -DURIPARSER_BUILD_TESTS=OFF -DURIPARSER_BUILD_TOOLS=OFF \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="0" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=OFF \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=OFF \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/debug_arm64"

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            mkdir -p "build_release_arm64"
            pushd "build_release_arm64"
                CFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
                CPPFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_LDFLAGS" \
                cmake .. -GXcode -DBUILD_SHARED_LIBS=OFF -DURIPARSER_BUILD_DOCS=OFF \
                    -DURIPARSER_BUILD_TESTS=OFF -DURIPARSER_BUILD_TOOLS=OFF \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="3" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/release_arm64"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # setup staging dirs
            mkdir -p "$stage/include/uriparser"
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            # create fat libraries
            lipo -create ${stage}/debug_x86/lib/liburiparser.a ${stage}/debug_arm64/lib/liburiparser.a -output ${stage}/lib/debug/liburiparser.a
            lipo -create ${stage}/release_x86/lib/liburiparser.a ${stage}/release_arm64/lib/liburiparser.a -output ${stage}/lib/release/liburiparser.a

            # copy headers
            mv $stage/release_x86/include/uriparser/* $stage/include/uriparser/
        ;;

        linux*)
            # populate version_file
            cc -DVERSION_HEADER_FILE="\"$VERSION_HEADER_FILE\"" \
               -DVERSION_MACRO="$VERSION_MACRO" \
               -o "$stage/version" "$top/version.c"
            "$stage/version" > "$stage/VERSION.txt"
            rm "$stage/version"

            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS
        
            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
            DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -fstack-protector-strong -DPIC -D_FORTIFY_SOURCE=2"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC -D_FORTIFY_SOURCE=2"
        
            JOBS=`cat /proc/cpuinfo | grep processor | wc -l`

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Debug
            mkdir -p "build_debug"
            pushd "build_debug"
                CFLAGS="$DEBUG_CFLAGS" \
                CXXFLAGS="$DEBUG_CXXFLAGS" \
                CPPFLAGS="$DEBUG_CPPFLAGS" \
                    cmake ../ -G"Unix Makefiles" -DCMAKE_BUILD_TYPE="Debug" -DBUILD_SHARED_LIBS=FALSE \
                        -DURIPARSER_BUILD_TESTS=FALSE -DURIPARSER_BUILD_DOCS=FALSE -DURIPARSER_BUILD_TOOLS=FALSE \
                        -DCMAKE_INSTALL_PREFIX="$stage"

                make -j$JOBS
                make install

                mkdir -p ${stage}/lib/debug
                mv ${stage}/lib/*.a ${stage}/lib/debug
                mkdir -p ${stage}/lib/debug/pkgconfig
                cp $top/pkgconfig/liburiparser-debug.pc ${stage}/lib/debug/pkgconfig/liburiparser.pc
            popd

            # Release
            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS" \
                CXXFLAGS="$RELEASE_CXXFLAGS" \
                CPPFLAGS="$RELEASE_CPPFLAGS" \
                    cmake ../ -G"Unix Makefiles" -DCMAKE_BUILD_TYPE="Release" -DBUILD_SHARED_LIBS=FALSE \
                        -DURIPARSER_BUILD_TESTS=FALSE -DURIPARSER_BUILD_DOCS=FALSE -DURIPARSER_BUILD_TOOLS=FALSE \
                        -DCMAKE_INSTALL_PREFIX="$stage"

                make -j$JOBS
                make install

                mkdir -p ${stage}/lib/release
                mv ${stage}/lib/*.a ${stage}/lib/release
                mkdir -p ${stage}/lib/release/pkgconfig
                cp $top/pkgconfig/liburiparser-release.pc ${stage}/lib/release/pkgconfig/liburiparser.pc
            popd
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    pwd
    cp -a COPYING "$stage/LICENSES/uriparser.txt"
popd
