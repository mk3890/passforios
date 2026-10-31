#!/bin/bash

# Build libgit2 with SSH support through libssh2 and OpenSSL for iOS devices and simulators, and package the result as
# libgit2/dist/Clibgit2.xcframework. HTTPS uses Apple's Secure Transport, so that certificates are checked against the
# system trust store. Requires Xcode, CMake and Perl (both available through Homebrew).

set -euo pipefail

OPENSSL_VERSION="3.5.9"
OPENSSL_SHA256="603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"
LIBSSH2_VERSION="1.11.1"
LIBSSH2_SHA256="d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7"
LIBGIT2_VERSION="1.9.7"
LIBGIT2_SHA256="1a4fbe7589e814777ae76b64734ad80f4ecad22cd33a22682a2aaea4ae5375e7"

IOS_VERSION="13.0"

ROOT_PATH="$(pwd)/libgit2"
SOURCE_PATH="$ROOT_PATH/checkout"
BUILD_PATH="$ROOT_PATH/build"
OUTPUT_PATH="$ROOT_PATH/dist"
JOBS="$(sysctl -n hw.ncpu)"

rm -rf "$SOURCE_PATH" "$BUILD_PATH" "$OUTPUT_PATH/Clibgit2.xcframework"
mkdir -p "$SOURCE_PATH" "$BUILD_PATH" "$OUTPUT_PATH"

# Download a tarball, verify its checksum and extract it into the source directory.
download() {
    local url="$1" sha256="$2" file="$SOURCE_PATH/$(basename "$1")"
    curl --fail --silent --show-error --location --output "$file" "$url"
    echo "$sha256  $file" | shasum --algorithm 256 --check --status || {
        echo "Checksum mismatch for $url" >&2
        exit 1
    }
    tar -xzf "$file" -C "$SOURCE_PATH"
}

download "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" "$OPENSSL_SHA256"
download "https://github.com/libssh2/libssh2/releases/download/libssh2-$LIBSSH2_VERSION/libssh2-$LIBSSH2_VERSION.tar.gz" "$LIBSSH2_SHA256"
download "https://github.com/libgit2/libgit2/archive/refs/tags/v$LIBGIT2_VERSION.tar.gz" "$LIBGIT2_SHA256"

# Build all libraries for one SDK and architecture and merge them into a single static library.
build_slice() {
    local sdk="$1" arch="$2"
    local slice_path="$BUILD_PATH/$sdk-$arch"
    local prefix="$slice_path/install"
    local openssl_target min_version_flag
    case "$sdk-$arch" in
        iphoneos-arm64) openssl_target="ios64-xcrun" ;;
        iphonesimulator-arm64) openssl_target="iossimulator-arm64-xcrun" ;;
        iphonesimulator-x86_64) openssl_target="iossimulator-x86_64-xcrun" ;;
    esac
    if [ "$sdk" = "iphoneos" ]; then
        min_version_flag="-mios-version-min=$IOS_VERSION"
    else
        min_version_flag="-mios-simulator-version-min=$IOS_VERSION"
    fi

    # OpenSSL is only used by libssh2.
    mkdir -p "$slice_path/openssl"
    pushd "$slice_path/openssl"
    "$SOURCE_PATH/openssl-$OPENSSL_VERSION/Configure" "$openssl_target" "$min_version_flag" \
        no-shared no-tests no-apps no-docs no-engine no-dso no-ui-console \
        --prefix="$prefix" --libdir=lib
    make -j "$JOBS" build_libs
    make install_dev
    popd

    local cmake_options=(
        -DCMAKE_SYSTEM_NAME=iOS
        -DCMAKE_OSX_SYSROOT="$sdk"
        -DCMAKE_OSX_ARCHITECTURES="$arch"
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_VERSION"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$prefix"
        -DCMAKE_PREFIX_PATH="$prefix"
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
        -DBUILD_SHARED_LIBS=OFF
    )
    # Only find the libraries built here, never the ones of the host, e.g., from Homebrew.
    export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
    export PKG_CONFIG_PATH=""

    cmake -S "$SOURCE_PATH/libssh2-$LIBSSH2_VERSION" -B "$slice_path/libssh2" "${cmake_options[@]}" \
        -DBUILD_STATIC_LIBS=ON \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF \
        -DCRYPTO_BACKEND=OpenSSL \
        -DOPENSSL_ROOT_DIR="$prefix" \
        -DOPENSSL_USE_STATIC_LIBS=ON \
        -DENABLE_ZLIB_COMPRESSION=OFF
    cmake --build "$slice_path/libssh2" --target install -j "$JOBS"

    # The check for SSH keys in memory links against the static libssh2, which needs OpenSSL.
    cmake -S "$SOURCE_PATH/libgit2-$LIBGIT2_VERSION" -B "$slice_path/libgit2" "${cmake_options[@]}" \
        -DBUILD_TESTS=OFF \
        -DBUILD_CLI=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DUSE_SSH=libssh2 \
        -DUSE_HTTPS=SecureTransport \
        -DUSE_BUNDLED_ZLIB=ON \
        -DUSE_NTLMCLIENT=OFF \
        -DUSE_GSSAPI=OFF \
        -DREGEX_BACKEND=builtin \
        -DCMAKE_REQUIRED_LIBRARIES="$prefix/lib/libssl.a;$prefix/lib/libcrypto.a"
    cmake --build "$slice_path/libgit2" --target install -j "$JOBS"

    # Fail early instead of at runtime if a feature the app relies on was not detected.
    local features
    features="$(find "$slice_path/libgit2" -name git2_features.h -print -quit)"
    for feature in GIT_SSH_LIBSSH2 GIT_SSH_LIBSSH2_MEMORY_CREDENTIALS GIT_SECURE_TRANSPORT; do
        grep -q "#define $feature 1" "$features" || {
            echo "libgit2 was built without $feature for $sdk-$arch" >&2
            exit 1
        }
    done

    libtool -static -o "$slice_path/libClibgit2.a" \
        "$prefix/lib/libgit2.a" "$prefix/lib/libssh2.a" "$prefix/lib/libssl.a" "$prefix/lib/libcrypto.a"
}

build_slice iphoneos arm64
build_slice iphonesimulator arm64
build_slice iphonesimulator x86_64

mkdir -p "$BUILD_PATH/iphonesimulator"
lipo -create \
    "$BUILD_PATH/iphonesimulator-arm64/libClibgit2.a" \
    "$BUILD_PATH/iphonesimulator-x86_64/libClibgit2.a" \
    -output "$BUILD_PATH/iphonesimulator/libClibgit2.a"

# The headers are the same for all slices.
HEADERS_PATH="$BUILD_PATH/headers"
mkdir -p "$HEADERS_PATH"
cp -R "$BUILD_PATH/iphoneos-arm64/install/include/git2.h" "$BUILD_PATH/iphoneos-arm64/install/include/git2" "$HEADERS_PATH"
cat > "$HEADERS_PATH/module.modulemap" << EOF
module Clibgit2 {
    umbrella header "git2.h"
    export *
    link "iconv"
    link framework "CoreFoundation"
    link framework "Security"
}
EOF

xcodebuild -create-xcframework \
    -library "$BUILD_PATH/iphoneos-arm64/libClibgit2.a" -headers "$HEADERS_PATH" \
    -library "$BUILD_PATH/iphonesimulator/libClibgit2.a" -headers "$HEADERS_PATH" \
    -output "$OUTPUT_PATH/Clibgit2.xcframework"
