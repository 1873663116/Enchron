from __future__ import annotations

import datetime
import json
import shutil
from pathlib import Path
from types import TracebackType
from typing import Callable, Sequence

from harness.failures import InstrumentFault


class EvidenceScope:
    def __init__(
        self,
        label: str,
        sources: Sequence[Path],
        archive_root: Path,
        now: Callable[[], datetime.datetime] = lambda: datetime.datetime.now(
            datetime.timezone.utc
        ),
    ) -> None:
        self.label = label
        self.sources = [Path(source) for source in sources]
        self.archive_root = Path(archive_root)
        self.now = now
        self.destructions: list[str] = []
        self.entered = False
        self.sealed = False

    @property
    def tainted(self) -> bool:
        return bool(self.destructions)

    def _relocate(self, source: Path, destination: Path) -> None:
        if not source.exists():
            return
        for entry in sorted(source.iterdir()):
            destination.mkdir(parents=True, exist_ok=True)
            shutil.move(str(entry), str(destination / entry.name))

    def __enter__(self) -> EvidenceScope:
        assert not self.entered, (
            f"evidence scope {self.label!r} entered twice; one scope covers one segment"
        )
        self.entered = True
        prior = self.archive_root / self.label / "prior"
        for source in self.sources:
            source.mkdir(parents=True, exist_ok=True)
            self._relocate(source, prior / source.name)
        return self

    def register_destruction(self, description: str) -> None:
        assert self.entered and not self.sealed, (
            f"destruction {description!r} declared outside the open scope "
            f"{self.label!r}"
        )
        self.destructions.append(description)
        raise InstrumentFault(
            "evidence-destroyed",
            {
                "scope": self.label,
                "destruction": description,
                "diagnosis": (
                    f"recovery destroyed {description} inside evidence scope "
                    f"{self.label!r}; every observation in this segment is void "
                    "and the segment must rerun"
                ),
            },
        )

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> bool:
        sealed_root = self.archive_root / self.label / "sealed"
        for source in self.sources:
            self._relocate(source, sealed_root / source.name)
        manifest = {
            "label": self.label,
            "sealedAt": self.now().isoformat(),
            "valid": not self.destructions,
            "destructions": list(self.destructions),
        }
        manifest_path = self.archive_root / self.label / "manifest.json"
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        self.sealed = True
        return False
