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

            cmake . -G "$AUTOBUILD_WIN_CMAKE_GEN" \
                  -DCMAKE_INSTALL_PREFIX:STRING="$(cygpath -w ${stage})" \
                  -DCMAKE_CXX_FLAGS="$LL_BUILD_RELEASE" \
                  -DCMAKE_C_FLAGS="$LL_BUILD_RELEASE"

            build_sln "uriparser.sln" "Release|$AUTOBUILD_WIN_VSPLATFORM" "uriparser"

            mkdir -p "$stage/lib/release"
            cp -a "Release/uriparser.lib" \
                "$stage/lib/release/uriparser.lib"
            mkdir -p "$stage/include/uriparser"
            cp -a include/uriparser/*.h "$stage/include/uriparser"
        ;;

        darwin*)
            # populate version_file
            cc -DVERSION_HEADER_FILE="\"$VERSION_HEADER_FILE\"" \
               -DVERSION_MACRO="$VERSION_MACRO" \
               -o "$stage/version" "$top/version.c"
            "$stage/version" > "$stage/VERSION.txt"
            rm "$stage/version"

            cmake . -DCMAKE_INSTALL_PREFIX:STRING="${stage}" \
                  -DCMAKE_CXX_FLAGS="$LL_BUILD_RELEASE" \
                  -DCMAKE_C_FLAGS="$LL_BUILD_RELEASE"
            make
            make install
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
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # generate configure script
            ./autogen.sh

            # Release
            CFLAGS="$opts" CXXFLAGS="$opts" \
                ./configure --prefix="$stage" \
                --includedir="$stage/include" --libdir="$stage/lib/release" --disable-test
            make
            make install

            # clean the build artifacts
            make distclean
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    pwd
    cp -a COPYING "$stage/LICENSES/uriparser.txt"
popd
