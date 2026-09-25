#!/usr/bin/env python3
"""Write the AutoBleem Store's descriptor for one platform's package (autobleem-repo CLAUDE.md, "The AutoBleem
Store's catalog"), next to the package and the picture, ready for `repo_publish.sh store <platform> ...`:

    tools/store_item.py dist/opentyrian-psc-2.1.20260913-1.zip      -> dist/store/psc/opentyrian.item.json
                                                                        + opentyrian.png + the zip

The id is the same on every platform (app/opentyrian), so an installed App is updated in place.
Only the standard library is needed.
"""
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DESCRIPTION = ("Tyrian 2.1, the 1995 vertical shooter, through OpenTyrian - the full game, freeware since 2004. "
               "Built for this machine from source; the PlayStation Classic pad layout out of the box.")


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    package = argv[1]
    m = re.match(r"^opentyrian-(?P<key>[a-z0-9]+)-(?P<version>.+)\.zip$", os.path.basename(package))
    if not m:
        print("not an opentyrian-<key>-<version>.zip: %s" % package)
        return 1
    key, version = m.group("key"), m.group("version")
    out = os.path.join(os.path.dirname(package), "store", key)
    os.makedirs(out, exist_ok=True)
    shutil.copy(package, out)
    shutil.copy(os.path.join(ROOT, "resources", "icon.png"), os.path.join(out, "opentyrian.png"))
    item = {
        "id": "app/opentyrian",
        "kind": "app",
        "title": "Tyrian (OpenTyrian)",
        "version": version,
        "author": "The OpenTyrian team; Tyrian by Jason Emery",
        "licence": "GPL-2.0-or-later (the game data: freeware)",
        "description": DESCRIPTION,
        "image": "opentyrian.png",
        "files": [{"name": os.path.basename(package)}],
    }
    with open(os.path.join(out, "opentyrian.item.json"), "w", encoding="utf-8") as f:
        json.dump(item, f, indent=2)
        f.write("\n")
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
