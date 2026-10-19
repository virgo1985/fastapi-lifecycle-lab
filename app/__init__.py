"""Lifecycle Lab API."""

import os


def __build_info__() -> dict[str, str]:
    """Metadatos que el pipeline inyecta en la imagen (build args -> ENV)."""
    return {
        "built_as": os.environ.get("BUILD_VERSION", "unknown"),
        "git_sha": os.environ.get("BUILD_GIT_SHA", "unknown"),
        "git_ref": os.environ.get("BUILD_GIT_REF", "unknown"),
        "build_date": os.environ.get("BUILD_DATE", "unknown"),
    }
