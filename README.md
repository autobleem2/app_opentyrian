# app_opentyrian

[OpenTyrian](https://github.com/opentyrian/opentyrian) - the open-source port of the DOS shooter Tyrian - packaged
as an [AutoBleem](https://github.com/autobleem2/autobleem) App for the PlayStation Classic, the Raspberry Pi, the
AutoBleem PC stick and Windows, with the freeware Tyrian 2.1 data. Install it from the AutoBleem Store.

The upstream sources are pinned submodules; this repository holds only the build (`ci/build.sh`, run in the
[autobleem-build](https://github.com/autobleem2/autobleem-build) image), two small patches (the PlayStation
Classic pad layout by default, full screen by default) and the App's files.

```
git clone --recurse-submodules https://github.com/autobleem2/app_opentyrian
ci/build.sh all    # inside ghcr.io/autobleem2/autobleem-build
```

Controls (PlayStation Classic pad): D-pad move, Cross/Triangle fire, Square/Circle rear weapon mode, L1/L2 and
R1/R2 the sidekicks, Start pause, Select menu. Hold Start + Select to leave.

Licence: the build and patches GPL-3.0-or-later, OpenTyrian GPL-2.0-or-later, SDL_net zlib; the Tyrian 2.1 data
is freeware (see `LICENSE`).
