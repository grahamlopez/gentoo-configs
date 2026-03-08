#!/bin/bash
#          -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \

set -e  # exit on error

################################################################################
# Static Initramfs Tools Builder
# Builds fully static cryptsetup and busybox for initramfs use
################################################################################

# Paths
local_path="$HOME/local"
local_path_deps="$local_path/static_deps"
local_path_apps="$local_path/static_apps"
build_path="/dev/shm"
initramfs_dest="/usr/src/initramfs"  # Final destination for initramfs binaries

# Parallel build
par_build=24

# Version configuration
date_version=$(date +%Y.%m.%d)

# Cryptsetup and dependencies
cryptsetup_version="2.8.3"
lvm2_version="2.03.22"
json_c_version="0.18"
popt_version="1.19"
argon2_version="20190702"
openssl_version="3.5.5"
util_linux_version="2.41.3"

# Busybox
busybox_version="1.36.1"

# Build flags
BUILD_CRYPTSETUP=true
BUILD_BUSYBOX=true

# Optimization flags for smaller binaries
# -Os: Optimize for size
# -ffunction-sections -fdata-sections: Put each function/data in own section
# -fno-asynchronous-unwind-tables: Remove unwind tables (smaller binary)
# -fno-stack-protector: Remove stack protection overhead
# note that execution perf isn't a huge deal for initramfs; boot operations are
# all I/O bound anyway
OPT_CFLAGS="-Os -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -fno-stack-protector"
OPT_LDFLAGS="-Wl,--strip-all"

# Setup - create our directories
mkdir -p "$build_path/src" "$local_path_deps" "$local_path_apps" "$initramfs_dest/sbin"

################################################################################
# Helper function for downloads
################################################################################
download_and_extract() {
    local url="$1"
    local filename=$(basename "$url")
    
    if [ ! -f "$filename" ]; then
        echo "Downloading $filename..."
        wget "$url"
    fi
    
    # Extract based on extension
    if [[ "$filename" == *.tar.gz ]]; then
        tar xzf "$filename"
    elif [[ "$filename" == *.tgz ]]; then
        tar xzf "$filename"
    elif [[ "$filename" == *.tar.xz ]]; then
        tar xJf "$filename"
    elif [[ "$filename" == *.tar.bz2 ]]; then
        tar xjf "$filename"
    fi
}

################################################################################
# Build static library dependencies for cryptsetup
################################################################################
build_static_deps() {
    echo ""
    echo "==============================================="
    echo "Building static library dependencies"
    echo "==============================================="
    echo ""
    sleep 2
    
    cd "$build_path/src"
    
    # popt
    echo "Building popt-${popt_version} (static)..."
    download_and_extract "http://ftp.rpm.org/popt/releases/popt-1.x/popt-${popt_version}.tar.gz"
    cd "popt-${popt_version}"
    CFLAGS="$OPT_CFLAGS" \
    ./configure --prefix="$local_path_deps" --enable-static --disable-shared
    make -j"$par_build"
    make install
    cd ..
    rm -rf "popt-${popt_version}"
    
    # json-c
    echo "Building json-c-${json_c_version} (static)..."
    download_and_extract "https://s3.amazonaws.com/json-c_releases/releases/json-c-${json_c_version}.tar.gz"
    cd "json-c-${json_c_version}"
    mkdir build && cd build
    cmake -DCMAKE_INSTALL_PREFIX="$local_path_deps" \
          -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_SHARED_LIBS=OFF \
          -DCMAKE_BUILD_TYPE=MinSizeRel \
          -DCMAKE_C_FLAGS="$OPT_CFLAGS" \
          -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
          ..
    make -j"$par_build"
    make install
    cd ../..
    rm -rf "json-c-${json_c_version}"
    
    # Verify json-c installation and create symlink if needed
    if [ -f "$local_path_deps/lib/libjson-c.a" ]; then
        echo "✓ Found libjson-c.a in lib/"
    elif [ -f "$local_path_deps/lib64/libjson-c.a" ]; then
        echo "✓ Found libjson-c.a in lib64/ - creating symlink in lib/"
        ln -sf "$local_path_deps/lib64/libjson-c.a" "$local_path_deps/lib/libjson-c.a"
    fi
    
    # argon2
    echo "Building argon2-${argon2_version} (static)..."
    download_and_extract "https://github.com/P-H-C/phc-winner-argon2/archive/refs/tags/${argon2_version}.tar.gz"
    cd "phc-winner-argon2-${argon2_version}"
    make -j"$par_build" LIBRARY_REL=lib CFLAGS="$OPT_CFLAGS"
    make install PREFIX="$local_path_deps" LIBRARY_REL=lib
    if [ ! -f "$local_path_deps/lib/libargon2.a" ]; then
        cp libargon2.a "$local_path_deps/lib/"
    fi
    cd ..
    rm -rf "phc-winner-argon2-${argon2_version}"
    
    # OpenSSL (static)
    echo "Building openssl-${openssl_version} (static)..."
    download_and_extract "https://www.openssl.org/source/openssl-${openssl_version}.tar.gz"
    cd "openssl-${openssl_version}"
    ./config --prefix="$local_path_deps" \
             --libdir=lib \
             --openssldir="$local_path_deps/ssl" \
             no-shared \
             no-dso
    make -j"$par_build"
    make install_sw
    cd ..
    rm -rf "openssl-${openssl_version}"
    
    # Verify OpenSSL installation and create symlinks if needed
    if [ -f "$local_path_deps/lib/libcrypto.a" ]; then
        echo "✓ Found libcrypto.a in lib/"
    elif [ -f "$local_path_deps/lib64/libcrypto.a" ]; then
        echo "✓ Found libcrypto.a in lib64/ - creating symlinks in lib/"
        ln -sf "$local_path_deps/lib64/libcrypto.a" "$local_path_deps/lib/libcrypto.a"
        ln -sf "$local_path_deps/lib64/libssl.a" "$local_path_deps/lib/libssl.a"
    fi
    
    # util-linux (just libblkid and libuuid static)
    echo "Building util-linux-${util_linux_version} (static libs only)..."
    download_and_extract "https://www.kernel.org/pub/linux/utils/util-linux/v${util_linux_version%.*}/util-linux-${util_linux_version}.tar.xz"
    cd "util-linux-${util_linux_version}"
    CFLAGS="$OPT_CFLAGS" \
    ./configure --prefix="$local_path_deps" \
                --enable-static \
                --disable-shared \
                --disable-all-programs \
                --enable-libblkid \
                --enable-libuuid \
                --without-systemd \
                --without-udev
    make -j"$par_build"
    make install
    cd ..
    rm -rf "util-linux-${util_linux_version}"
    
    # Create pkg-config file for blkid if missing
    mkdir -p "$local_path_deps/lib/pkgconfig"
    if [ ! -f "$local_path_deps/lib/pkgconfig/blkid.pc" ]; then
        cat > "$local_path_deps/lib/pkgconfig/blkid.pc" << EOF
prefix=$local_path_deps
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: blkid
Description: Block device id library
Version: ${util_linux_version}
Requires:
Cflags: -I\${includedir}
Libs: -L\${libdir} -lblkid -luuid
Libs.private: -luuid
EOF
    fi
    
    # lvm2 / device-mapper (static libdevmapper only)
    echo "Building lvm2-${lvm2_version} (static device-mapper)..."
    download_and_extract "https://sourceware.org/pub/lvm2/LVM2.${lvm2_version}.tgz"
    cd "LVM2.${lvm2_version}"
    
    PKG_CONFIG_PATH="$local_path_deps/lib/pkgconfig" \
    LDFLAGS="-L${local_path_deps}/lib" \
    CFLAGS="$OPT_CFLAGS -I${local_path_deps}/include" \
    CPPFLAGS="-I${local_path_deps}/include" \
    ./configure --prefix="$local_path_deps" \
                --enable-static_link \
                --with-udev-prefix="" \
                --with-systemdsystemunitdir=no \
                --with-staticdir="$local_path_deps/sbin" \
                --enable-pkgconfig \
                --with-confdir="$local_path_deps/etc"
    
    make -j"$par_build" libdm.device-mapper || true
    
    mkdir -p "$local_path_deps/lib" "$local_path_deps/include" "$local_path_deps/sbin"
    
    cp -v libdm/ioctl/libdevmapper.a "$local_path_deps/lib/" 2>/dev/null || \
        find . -name "libdevmapper.a" -exec cp -v {} "$local_path_deps/lib/" \;
    
    cp -v libdm/libdevmapper.h "$local_path_deps/include/" 2>/dev/null || \
        find . -name "libdevmapper.h" -exec cp -v {} "$local_path_deps/include/" \;
    
    if [ -f "libdm/dmsetup.static" ]; then
        cp -v libdm/dmsetup.static "$local_path_deps/sbin/dmsetup"
    fi
    
    cat > "$local_path_deps/lib/pkgconfig/devmapper.pc" << EOF
prefix=$local_path_deps
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: devmapper
Description: Device-mapper library
Version: ${lvm2_version}
Requires: blkid
Cflags: -I\${includedir}
Libs: -L\${libdir} -ldevmapper -lblkid -luuid
Libs.private: -lpthread -lrt -ldl -lm
EOF
    
    cd ..
    rm -rf "LVM2.${lvm2_version}"
    
    echo "Static dependencies built successfully!"
}

################################################################################
# Build static cryptsetup
################################################################################
build_cryptsetup() {
    echo ""
    echo "==============================================="
    echo "Building cryptsetup-${cryptsetup_version} (static)"
    echo "==============================================="
    echo ""
    sleep 2
    
    cd "$build_path/src"
    
    download_and_extract "https://www.kernel.org/pub/linux/utils/cryptsetup/v${cryptsetup_version%.*}/cryptsetup-${cryptsetup_version}.tar.xz"
    
    cd "cryptsetup-${cryptsetup_version}"
    
    PKG_CONFIG_PATH="$local_path_deps/lib/pkgconfig" \
    LDFLAGS="-L${local_path_deps}/lib -static" \
    CFLAGS="$OPT_CFLAGS -I${local_path_deps}/include" \
    CPPFLAGS="-I${local_path_deps}/include" \
    LIBS="-lpthread -lrt -ldl -lm" \
    ./configure --prefix="$local_path_apps/cryptsetup-${cryptsetup_version}" \
                --enable-static \
                --disable-shared \
                --enable-static-cryptsetup \
                --with-crypto_backend=openssl \
                --disable-udev \
                --disable-selinux \
                --disable-ssh-token \
                --disable-asciidoc \
                --disable-veritysetup \
                --disable-integritysetup
    
    echo "Building static cryptsetup binary..."
    make -j"$par_build" cryptsetup.static
    
    # Copy binary
    echo "Copying cryptsetup binary..."
    cp -v cryptsetup.static "$initramfs_dest/sbin/cryptsetup"
    
    # Strip it
    echo "Stripping binary..."
    strip -s "$initramfs_dest/sbin/cryptsetup"
    
    echo ""
    echo "Binary size:"
    ls -lh "$initramfs_dest/sbin/cryptsetup"
    
    echo ""
    echo "Verifying cryptsetup binary:"
    file "$initramfs_dest/sbin/cryptsetup"
    if file "$initramfs_dest/sbin/cryptsetup" | grep -q "statically linked"; then
        echo "✓ cryptsetup is statically linked"
    else
        echo "✗ WARNING: cryptsetup may not be fully static!"
        ldd "$initramfs_dest/sbin/cryptsetup" 2>&1 || echo "Binary is static"
    fi
    
    cd ..
    rm -rf "cryptsetup-${cryptsetup_version}"
    
    echo "Static cryptsetup built successfully!"
}

################################################################################
# Build static busybox
################################################################################
build_busybox() {
    echo ""
    echo "==============================================="
    echo "Building busybox-${busybox_version} (static)"
    echo "==============================================="
    echo ""
    sleep 2
    
    cd "$build_path/src"
    
    download_and_extract "https://busybox.net/downloads/busybox-${busybox_version}.tar.bz2"
    
    cd "busybox-${busybox_version}"
    
    make defconfig
    
    # Enable static build
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    
    # Disable problematic features
    sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config
    sed -i 's/CONFIG_FEATURE_HAVE_RPC=y/# CONFIG_FEATURE_HAVE_RPC is not set/' .config
    sed -i 's/CONFIG_FEATURE_INETD_RPC=y/# CONFIG_FEATURE_INETD_RPC is not set/' .config
    sed -i 's/CONFIG_FEATURE_MOUNT_NFS=y/# CONFIG_FEATURE_MOUNT_NFS is not set/' .config
    
    # Note: --gc-sections doesn't work with static glibc builds
    # Build with just size optimization
    make -j"$par_build" EXTRA_CFLAGS="$OPT_CFLAGS"
    
    # Copy first, then strip
    echo "Copying and stripping busybox binary..."
    mkdir -p "$initramfs_dest/bin"
    cp -v busybox "$initramfs_dest/bin/busybox"
    strip -s "$initramfs_dest/bin/busybox"
    
    echo ""
    echo "Binary size:"
    ls -lh "$initramfs_dest/bin/busybox"
    
    echo ""
    echo "Verifying busybox binary:"
    file "$initramfs_dest/bin/busybox"
    if file "$initramfs_dest/bin/busybox" | grep -q "statically linked"; then
        echo "✓ busybox is statically linked"
    else
        echo "✗ WARNING: busybox may not be fully static!"
        ldd "$initramfs_dest/bin/busybox" 2>&1 || echo "Binary is static"
    fi
    
    echo "Creating busybox applet symlinks..."
    cd "$initramfs_dest"
    ./bin/busybox --install -s
    
    cd "$build_path/src"
    rm -rf "busybox-${busybox_version}"
    
    echo "Static busybox built successfully!"
}

################################################################################
# Main execution
################################################################################

if [ "$BUILD_CRYPTSETUP" = true ]; then
    build_static_deps
    build_cryptsetup
fi

if [ "$BUILD_BUSYBOX" = true ]; then
    build_busybox
fi

echo ""
echo "==============================================="
echo "Build complete!"
echo "==============================================="
echo ""
echo "Static binaries installed to: $initramfs_dest"
echo ""
echo "Final sizes:"
ls -lh "$initramfs_dest/sbin/cryptsetup" 2>/dev/null
ls -lh "$initramfs_dest/bin/busybox" 2>/dev/null
echo ""
echo "Total size:"
du -sh "$initramfs_dest"
echo ""
echo "Verify static linking:"
echo "  file $initramfs_dest/sbin/cryptsetup"
echo "  file $initramfs_dest/bin/busybox"
echo ""
