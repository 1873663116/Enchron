#!/usr/bin/env python3

"""One Swift lexer for every checker that has to look past comments and strings.

The offsets and the newlines survive masking, so a caller can report a position
in the original file while reading the masked copy.
"""

from __future__ import annotations

from functools import lru_cache
import re


STRING_START_PATTERN = re.compile(r'(?P<hashes>#+)?(?P<quotes>"""|")')


@lru_cache(maxsize=64)
def mask_noncode(source: str) -> str:
    characters = list(source)
    index = 0
    while index < len(source):
        if source.startswith("//", index):
            while index < len(source) and source[index] != "\n":
                characters[index] = " "
                index += 1
            continue
        if source.startswith("/*", index):
            depth = 1
            characters[index] = characters[index + 1] = " "
            index += 2
            while index < len(source) and depth:
                if source.startswith("/*", index):
                    characters[index] = characters[index + 1] = " "
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    characters[index] = characters[index + 1] = " "
                    depth -= 1
                    index += 2
                else:
                    if source[index] != "\n":
                        characters[index] = " "
                    index += 1
            continue
        opening = STRING_START_PATTERN.match(source, index)
        if opening is not None:
            hashes = opening.group("hashes") or ""
            quotes = opening.group("quotes")
            closing = quotes + hashes
            start_length = len(hashes) + len(quotes)
            for masked in range(index, index + start_length):
                characters[masked] = " "
            index += start_length
            while index < len(source):
                if source.startswith(closing, index):
                    for masked in range(index, index + len(closing)):
                        characters[masked] = " "
                    index += len(closing)
                    break
                if source[index] != "\n":
                    characters[index] = " "
                index += 1
            continue
        index += 1
    return "".join(characters)
