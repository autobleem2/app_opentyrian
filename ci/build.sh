#!/usr/bin/env bash
# Builds the OpenTyrian App in the autobleem-build image (ghcr.io/autobleem2/autobleem-build) and packages it:
#
#   ci/build.sh native                    a host build (build_native/), run with the fetched data as a smoke test
#   ci/build.sh psc|rpi|rpi64|pcusb|win   a target, packed into dist/opentyrian-<key>-<version>.zip
#   ci/build.sh all                       every one of them
#
# What is ours and what is upstream's (CLAUDE.md): upstream/opentyrian and upstream/SDL_net are pinned
# submodules, never edited - each build copies them into build_<key>/ and applies patches/<name>/*.patch there.
#
# A package is the App's folder as a stick has it - Apps/opentyrian/app.ini, the shared files (icon, readme,
# the game data), bin/<key>/opentyrian and lib/<key>/ (SDL2_net; SDL2 itself is the launcher's or the
# system's) for its one platform - which is what the Store's AppInstaller lays over Apps/opentyrian/, keeping
# any other platform's bin/<key>/ and lib/<key>/. The version is app.ini's Version=, or AB_VERSION.
#
# On the build server: docker run --rm -u $(id -u):$(id -g) -v $PWD:/src -w /src \
#                          ghcr.io/autobleem2/autobleem-build:develop ci/build.sh all
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

APP=opentyrian
VERSION="${AB_VERSION:-$(sed -n 's/^Version=//p' resources/app.ini | tr -d '\r')}"
UPSTREAM_VERSION=$(git -C upstream/opentyrian describe --tags 2>/dev/null || echo "v2.1.20260913")
JOBS="${JOBS:-$(nproc)}"
PSC=${AB_PSC_TOOLCHAIN:-/opt/psc}
MINGW_SDL2=${AB_MINGW_SDL2:-/opt/mingw-sdl2/x86_64-w64-mingw32}

# The freeware Tyrian 2.1 data, from our own mirror of the file upstream's get_data.sh fetches
# (https://camanis.net/tyrian/tyrian21.zip) - pinned by its checksum, so a changed file fails the build.
DATA_URL="${AB_TYRIAN_DATA_URL:-https://autobleem.retromenele.pl/mirror/opentyrian/tyrian21.zip}"
DATA_SHA256="${AB_TYRIAN_DATA_SHA256:-7790d09a2a3addcd33c66ef063d5900eb81cc9c342f4807eb8356364dd1d9277}"

banner() { printf '\n==== %s ====\n' "$*"; }

# ---------------------------------------------------------------------------------------------------------
# The game data: downloaded once into build_data/, flattened and lower-cased (what the engine opens)
# ---------------------------------------------------------------------------------------------------------
fetch_data() {
    local dir=build_data
    if [ -f "$dir/data/tyrian1.lvl" ]; then return; fi
    banner "data: Tyrian 2.1 ($DATA_URL)"
    rm -rf "$dir"
    mkdir -p "$dir/x" "$dir/data"
    curl -fsSL -o "$dir/tyrian21.zip" "$DATA_URL"
    echo "$DATA_SHA256  $dir/tyrian21.zip" | sha256sum -c -
    python3 - "$dir/tyrian21.zip" "$dir/data" <<'EOF'
import os, sys, zipfile
# every file of the archive into one folder, lower-cased; the archive nests them in a folder of its own
with zipfile.ZipFile(sys.argv[1]) as z:
    for info in z.infolist():
        if info.is_dir():
            continue
        name = os.path.basename(info.filename).lower()
        with z.open(info) as src, open(os.path.join(sys.argv[2], name), "wb") as dst:
            dst.write(src.read())
EOF
    test -f "$dir/data/tyrian1.lvl" || { echo "no tyrian1.lvl in the data" >&2; exit 1; }
}

# ---------------------------------------------------------------------------------------------------------
# One target. The variables set by each target_* function:
#   CC, STRIP, CFLAGS_T      the compiler, its strip, the target's CPU flags
#   SDL_CFLAGS, SDL_LIBS     how to compile and link against SDL2
#   SO                       the shared library's file name pattern (so or dll)
#   PLATFORM_T               upstream's PLATFORM (UNIX or WIN32)
# ---------------------------------------------------------------------------------------------------------
target_native() {
    CC=gcc; STRIP=strip; CFLAGS_T="-O2"; PLATFORM_T=UNIX; EXE=opentyrian
    SDL_CFLAGS=$(pkg-config --cflags sdl2); SDL_LIBS=$(pkg-config --libs sdl2)
}
target_psc() {
    # the console's gcc-6 against a Debian Stretch sysroot, and the launcher's SDL2 2.0.14 (/opt/psc/sdl2),
    # which is what /tmp/lib holds on the console
    CC="$PSC/bin/armv8-sony-linux-gnueabihf-gcc"; STRIP="$PSC/bin/armv8-sony-linux-gnueabihf-strip"
    CFLAGS_T="-mfloat-abi=hard -march=armv8-a -mfpu=neon-vfpv4 -Os"; PLATFORM_T=UNIX; EXE=opentyrian
    SDL_CFLAGS=$(PKG_CONFIG_LIBDIR="$PSC/sdl2/lib/pkgconfig" pkg-config --cflags sdl2)
    SDL_LIBS=$(PKG_CONFIG_LIBDIR="$PSC/sdl2/lib/pkgconfig" pkg-config --libs sdl2)
}
target_rpi() {
    CC=arm-linux-gnueabihf-gcc; STRIP=arm-linux-gnueabihf-strip
    CFLAGS_T="-mfloat-abi=hard -mfpu=neon-vfpv4 -march=armv7-a -Os"; PLATFORM_T=UNIX; EXE=opentyrian
    SDL_CFLAGS=$(arm-linux-gnueabihf-pkg-config --cflags sdl2); SDL_LIBS=$(arm-linux-gnueabihf-pkg-config --libs sdl2)
}
target_rpi64() {
    CC=aarch64-linux-gnu-gcc; STRIP=aarch64-linux-gnu-strip
    CFLAGS_T="-march=armv8-a -Os"; PLATFORM_T=UNIX; EXE=opentyrian
    SDL_CFLAGS=$(aarch64-linux-gnu-pkg-config --cflags sdl2); SDL_LIBS=$(aarch64-linux-gnu-pkg-config --libs sdl2)
}
target_pcusb() {
    CC=i686-linux-gnu-gcc; STRIP=i686-linux-gnu-strip
    CFLAGS_T="-march=i686 -mtune=generic -D_FILE_OFFSET_BITS=64 -Os"; PLATFORM_T=UNIX; EXE=opentyrian
    SDL_CFLAGS=$(i386-linux-gnu-pkg-config --cflags sdl2); SDL_LIBS=$(i386-linux-gnu-pkg-config --libs sdl2)
}
target_win() {
    # the official SDL2 mingw development package (/opt/mingw-sdl2), the same SDL2.dll the Windows product ships
    CC=x86_64-w64-mingw32-gcc; STRIP=x86_64-w64-mingw32-strip; WINDRES=x86_64-w64-mingw32-windres
    CFLAGS_T="-O2"; PLATFORM_T=WIN32; EXE=opentyrian.exe
    SDL_CFLAGS="-I$MINGW_SDL2/include/SDL2 -Dmain=SDL_main"
    SDL_LIBS="-L$MINGW_SDL2/lib -lmingw32 -lSDL2main -lSDL2 -mwindows"
}

build_target() { # build_target <key>
    local key="$1" dir="build_$1"
    banner "$key ($dir)"
    "target_$key"

    rm -rf "$dir"
    mkdir -p "$dir/sdlnet" "$dir/Apps/$APP/bin/$key" "$dir/Apps/$APP/lib/$key"
    cp -r upstream/opentyrian "$dir/src"
    rm -rf "$dir/src/.git"
    for p in patches/opentyrian/*.patch; do
        [ -f "$p" ] || continue
        echo "patch: $p"
        patch -d "$dir/src" -p1 --no-backup-if-mismatch < "$p"
    done

    # SDL2_net: four C files; built by hand so every target (the console's old compiler included) takes it
    # the same way, as the shared library its package carries
    local net=upstream/SDL_net netlib netflags=() netlibs=""
    if [ "$PLATFORM_T" = WIN32 ]; then
        netlib=SDL2_net.dll
        netflags=(-Wl,--out-implib,"$dir/sdlnet/libSDL2_net.dll.a")
        netlibs="-lws2_32 -liphlpapi"
    else
        netlib=libSDL2_net-2.0.so.0
        netflags=(-fPIC -Wl,-soname,"$netlib")
    fi
    # shellcheck disable=SC2086
    "$CC" $CFLAGS_T -shared "${netflags[@]}" -DBUILD_SDL -DDLL_EXPORT $SDL_CFLAGS -I"$net/include" -I"$net/src" \
        "$net/src/SDLnet.c" "$net/src/SDLnetTCP.c" "$net/src/SDLnetUDP.c" "$net/src/SDLnetselect.c" \
        -o "$dir/sdlnet/$netlib" $SDL_LIBS $netlibs
    mkdir -p "$dir/sdlnet/include"
    cp "$net/include/SDL_net.h" "$dir/sdlnet/include/"
    if [ "$PLATFORM_T" = WIN32 ]; then
        NET_LIBS="-L$ROOT/$dir/sdlnet -lSDL2_net"
    else
        ln -sf "$netlib" "$dir/sdlnet/libSDL2_net.so"
        NET_LIBS="-L$ROOT/$dir/sdlnet -lSDL2_net"
    fi

    # OpenTyrian: upstream's Makefile, told everything on its command line (no pkg-config of its own - the
    # cross targets answer through wrappers the Makefile does not know about)
    local makevars=(
        CC="$CC" PLATFORM="$PLATFORM_T" TARGET="$EXE" WITH_NETWORK=true
        VCS_IDREV="echo $UPSTREAM_VERSION"
        SDL_CPPFLAGS="$SDL_CFLAGS -I$ROOT/$dir/sdlnet/include"
        SDL_LDFLAGS="" SDL_LDLIBS="$NET_LIBS $SDL_LIBS"
        CFLAGS="-pedantic -Wall -Wextra -Wno-missing-field-initializers $CFLAGS_T"
    )
    if [ "$PLATFORM_T" = WIN32 ]; then makevars+=(WINDRES="$WINDRES" RES=obj/resources.o); else makevars+=(RES=); fi
    make -C "$dir/src" -j "$JOBS" "${makevars[@]}"

    local stage="$dir/Apps/$APP"
    cp "$dir/src/$EXE" "$stage/bin/$key/"
    "$STRIP" "$stage/bin/$key/$EXE"
    cp "$dir/sdlnet/$netlib" "$stage/lib/$key/"
    "$STRIP" --strip-unneeded "$stage/lib/$key/$netlib"
    stage_shared "$stage"
}

stage_shared() { # the files every platform's package carries
    local stage="$1"
    cp resources/app.ini resources/readme.txt resources/icon.png "$stage/"
    cp upstream/opentyrian/COPYING "$stage/COPYING.txt"
    cp -r build_data/data "$stage/data"
    sed -i "s/^Version=.*/Version=$VERSION/" "$stage/app.ini"
}

package() { # package <key>
    local key="$1" dir="build_$1"
    mkdir -p dist
    local zip="dist/$APP-$key-$VERSION.zip"
    rm -f "$zip"
    (cd "$dir" && python3 - "$ROOT/$zip" "$APP" <<'EOF'
import os, sys, zipfile
# every file under Apps/<app>, with its mode (the program stays executable where the filesystem keeps it)
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(os.path.join("Apps", sys.argv[2])):
        dirs.sort()
        for name in sorted(files):
            z.write(os.path.join(root, name))
EOF
    )
    ls -l "$zip"
}

check() { # check <key>: what the program needs, and that it is what the platform can load
    local key="$1" stage="build_$1/Apps/$APP"
    case "$key" in
        psc)
            file "$stage/bin/psc/opentyrian" | grep -q 'ELF 32-bit LSB.*ARM'
            bash tools/check_psc_binary.sh "$stage/bin/psc/opentyrian" "$PSC"
            bash tools/check_psc_binary.sh "$stage/lib/psc/libSDL2_net-2.0.so.0" "$PSC" ;;
        rpi) file "$stage/bin/rpi/opentyrian" | grep -q 'ELF 32-bit LSB.*ARM' ;;
        rpi64) file "$stage/bin/rpi64/opentyrian" | grep -q 'ELF 64-bit LSB.*aarch64' ;;
        pcusb) file "$stage/bin/pcusb/opentyrian" | grep -q 'ELF 32-bit LSB.*Intel 80386' ;;
        win) file "$stage/bin/win/opentyrian.exe" | grep -q 'PE32+ executable.*x86-64' ;;
    esac
    # nothing but the base system, SDL2 and our own lib/<key>/
    bash tools/check_needed.sh "$key" "$stage"
}

build_native() {
    fetch_data
    build_target native
    # a smoke test: the program starts on the data, under the dummy drivers, and quits on its own
    local stage=build_native/Apps/$APP
    SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy LD_LIBRARY_PATH="$stage/lib/native" \
        timeout 10 "$stage/bin/native/opentyrian" -t "$stage/data" --help >/dev/null 2>&1 || true
    ldd "$stage/bin/native/opentyrian" | grep -q 'libSDL2_net' || { echo "native: no SDL2_net linked" >&2; exit 1; }
}

build_one() { # build_one <key>
    fetch_data
    build_target "$1"
    check "$1"
    package "$1"
}

[ $# -gt 0 ] || { echo "usage: $0 native|psc|rpi|rpi64|pcusb|win|all" >&2; exit 2; }
for target in "$@"; do
    case "$target" in
        native) build_native ;;
        psc | rpi | rpi64 | pcusb | win) build_one "$target" ;;
        all) build_native; for k in psc rpi rpi64 pcusb win; do build_one "$k"; done ;;
        *) echo "unknown target: $target" >&2; exit 2 ;;
    esac
done
