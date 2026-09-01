#!/usr/bin/env python3

"""The app must stay able to reach a media server named by an IP address.

App Transport Security stopped allowing cleartext loads to IP addresses in the
iOS 17 generation, and a self-hosted Emby or WebDAV server is normally reached
at exactly that: an address the wearer types, on a private network, with no
certificate for any name. NSAllowsArbitraryLoads is the only key that restores
those loads for addresses nobody can enumerate ahead of time.

The key is silent when it is overruled. The system ignores
NSAllowsArbitraryLoads outright and substitutes NO whenever the Information
Property List also carries any of the three narrower global exceptions, and
Apple's own documentation suggests adding one of them, NSAllowsLocalNetworking,
as a declaration of intent. A plist that reads as permissive then blocks every
routable address, with no build warning and no runtime log. Nothing in Swift
can observe which keys the plist carries alongside the one it needs, so no unit
test covers it.
"""

from __future__ import annotations

import argparse
import plistlib
from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PLIST = REPOSITORY_ROOT / "Config/Enchron-Info.plist"
SECURITY_KEY = "NSAppTransportSecurity"
CLEARTEXT_KEY = "NSAllowsArbitraryLoads"
OVERRULING_KEYS = (
    "NSAllowsLocalNetworking",
    "NSAllowsArbitraryLoadsInWebContent",
    "NSAllowsArbitraryLoadsForMedia",
)


def failures(plist: Path) -> list[str]:
    payload = plistlib.loads(plist.read_bytes())
    security = payload.get(SECURITY_KEY)
    if not isinstance(security, dict):
        return [f"{SECURITY_KEY} is missing, so cleartext loads to an IP address are blocked"]

    found = []
    if security.get(CLEARTEXT_KEY) is not True:
        found.append(f"{CLEARTEXT_KEY} is not true, so cleartext loads to an IP address are blocked")
    for key in OVERRULING_KEYS:
        if key in security:
            found.append(f"{key} makes the system ignore {CLEARTEXT_KEY} and substitute NO")
    return found


def main() -> int:
    argparse.ArgumentParser(description=__doc__).parse_args()

    found = failures(DEFAULT_PLIST)
    for failure in found:
        print(f"{DEFAULT_PLIST.relative_to(REPOSITORY_ROOT)}: {failure}")
    if found:
        return 1
    print(f"{CLEARTEXT_KEY} is in effect: no key overrules it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
