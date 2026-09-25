# app_opentyrian - developer context

**OpenTyrian** (the open-source port of the DOS shooter Tyrian) packaged as an AutoBleem App: `Apps/opentyrian/`,
Store id `app/opentyrian`, one zip per platform (`dist/opentyrian-<key>-<version>.zip`) in the multi-platform App
format (the launcher's `docs/app-format-plan.md`). Started 2026-09-25, the first of the third-party App ports
(autobleem-main `docs/decisions.md`, "Third-party App ports"; the order and the rules are there). It replaces
the RetroBoot 1.2 binary (genderbent's 2019 PSC build, psc only) the Store's psc catalog carried.

## The rules this repository follows (the owner's, 2026-09-25)

- **Patches over pinned upstream submodules**, never a fork: `upstream/opentyrian` (v2.1.20260913) and
  `upstream/SDL_net` (release-2.4.0) are never edited - `ci/build.sh` copies them into `build_<key>/` and
  applies `patches/<name>/*.patch` there. Make a patch by editing the submodule, `git -C upstream/<name> diff >
  patches/<name>/NNNN-what.patch`, and checking the submodule out clean again.
- **A package carries its own libraries** in `lib/<key>/` (`Lib=lib/{key}`), except SDL2 (the launcher's
  2.0.14 in `/tmp/lib` on the console and its `SDL2.dll` on Windows, the system's on the Pis and the PC stick),
  the C library family and the graphics stack. `tools/check_needed.sh` fails the build otherwise.
- **The freeware game data ships**: Tyrian 2.1, from our mirror (`mirror/opentyrian/tyrian21.zip` on the site,
  pinned by sha256 in `ci/build.sh`; published with autobleem-repo's `repo_publish.sh mirror`). Its
  `license.doc` is the original 1995 Epic MegaGames agreement - the freeware status is the author's 2004
  announcement (see `LICENSE`).
- **`VirtualPad=true`**: OpenTyrian reads the raw joystick API, so on Linux the virtual pad shows it an Xbox
  360 pad.

## Layout

| path | what |
|---|---|
| `upstream/opentyrian`, `upstream/SDL_net` | the pinned upstream sources (submodules) |
| `patches/opentyrian/0001-psc-default-pad-layout.patch` | a pad shaped like the X360 pad (>= 8 buttons, >= 6 axes - the virtual pad on Linux, an XInput pad on Windows) gets the 2020 PSC layout by default: Cross/Triangle fire, Square/Circle change fire, L1/L2 and R1/R2 the sidekicks (the triggers are axes 2 and 5, resting low), Select menu, Start pause. A saved `joystick` section in opentyrian.cfg still wins. |
| `patches/opentyrian/0002-fullscreen-by-default.patch` | full screen on display 0 instead of a window |
| `resources/` | `app.ini` (`Exec=bin/{key}/opentyrian`, `Args=-t data`, `Lib=lib/{key}`, no `Startup=` - the launcher's `rc/app_run.sh` starts it, in the App's folder), `readme.txt`, `icon.png` (the 2020 package's: the OpenTyrian icon over Tyrian art) |
| `ci/build.sh` | `native|psc|rpi|rpi64|pcusb|win|all` in the autobleem-build image. SDL2_net is compiled by hand (four C files, the same way on every target); OpenTyrian's own Makefile runs with everything on its command line (`PLATFORM`, `TARGET`, `SDL_CPPFLAGS/LDLIBS`, `VCS_IDREV`) |
| `tools/check_psc_binary.sh` | from the console tools: glibc <= 2.24, GLIBCXX <= 3.4.22, no RPATH (made to accept a C program, which has no GLIBCXX at all) |
| `tools/check_needed.sh` | every NEEDED / imported DLL is the system's, SDL2's or in `lib/<key>/` |
| `tools/store_item.py` | a package -> `dist/store/<key>/` with `opentyrian.item.json` (id `app/opentyrian`, the same on every platform) and `opentyrian.png`, for autobleem-repo's `repo_publish.sh store <key> dist/store/<key>/*` |

## Things to know

- **Where things are at run time**: the data is `-t data` relative to the App's folder (the launcher starts
  every App there, `rc/app_run.sh` on Linux and `LaunchService::planApp` on Windows); the settings and saves are
  `$XDG_CONFIG_HOME/opentyrian/` - on the stick's `Home/.config/` (app_env.sh) - and `%APPDATA%\OpenTyrian` on
  Windows. Upstream's portable mode (an `opentyrian.cfg` next to the program) is not used: the program's folder
  is `bin/<key>/`, one per platform.
- **SDL**: nothing newer than SDL 2.0.14 is used unguarded (`keyboard.c`'s 2.26 call is behind
  `SDL_VERSION_ATLEAST`), so the console's SDL2 runs it.
- **Windows**: a MinGW build against the official SDL2 mingw package; `SDL2.dll` is the launcher's (the launcher
  puts its own folder on an App's PATH). Run on the dev PC on 2026-09-25 as the launcher would (App folder as
  the working directory, `lib/win` on PATH): the intro plays.
- **Line endings**: the submodules must be checked out with LF (`git -C upstream/<name> config core.autocrlf
  false`, then re-checkout) or the patches do not apply on a Windows checkout synced to the server.
- **Build on the server**: sync with MSYS2's rsync (excluding `/build_*`, `/dist`), then
  `docker run --rm -u $(id -u):$(id -g) -v $PWD:/src -w /src ghcr.io/autobleem2/autobleem-build:develop ci/build.sh all`.
- **Not yet run**: on a console, a Pi or the PC stick (the tester checklist).
