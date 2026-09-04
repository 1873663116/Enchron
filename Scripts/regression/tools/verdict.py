#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass

from regression.core.errors import RegressionError
from regression.core.ids import NodeID, SignatureID, parse_identifier
from regression.core.runview import Attribution
from regression.tools.signatures import SignatureError, signature


class VerdictError(ValueError):
    pass


def _parse(kind: str, value: str, location: str, refusal: str) -> None:
    try:
        parse_identifier(kind, value, location)
    except RegressionError as error:
        raise VerdictError(refusal) from error


@dataclass(frozen=True)
class Verdict:
    node: NodeID
    first_deviant_frame: int | None
    region_observation: str
    attribution: Attribution
    signature: SignatureID | None

    def __post_init__(self) -> None:
        if not isinstance(self.node, str) or not self.node:
            raise VerdictError("Verdict node must be a node identifier")
        _parse(
            "node", self.node, "verdict.node", "Verdict node must be a node identifier"
        )
        frame = self.first_deviant_frame
        if frame is not None and (type(frame) is not int or frame < 0):
            raise VerdictError(
                "Verdict first deviant frame must be a non-negative integer or None"
            )
        if not isinstance(self.region_observation, str):
            raise VerdictError("Verdict region observation must be text")
        if not isinstance(self.attribution, Attribution):
            raise VerdictError(
                "Verdict attribution must be product, harness or spec"
            )
        if self.signature is not None:
            if not isinstance(self.signature, str) or not self.signature:
                raise VerdictError("Verdict signature must be a signature identifier")
            _parse(
                "signature",
                self.signature,
                "verdict.signature",
                "Verdict signature must be a signature identifier",
            )
            try:
                signature(self.signature)
            except SignatureError as error:
                raise VerdictError(str(error)) from error


__all__ = (
    "Attribution",
    "Verdict",
    "VerdictError",
)
