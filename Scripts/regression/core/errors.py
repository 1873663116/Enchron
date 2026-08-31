from __future__ import annotations


class RegressionError(ValueError):
    def __init__(self, code: str, location: str, detail: str) -> None:
        self.code = code
        self.location = location
        self.detail = detail
        super().__init__(f"{code} at {location}: {detail}")

