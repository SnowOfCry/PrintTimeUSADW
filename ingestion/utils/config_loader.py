"""
config_loader.py
----------------
Loads ingestion configuration from YAML files and environment variables.
Environment variables always take precedence over YAML values.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml

from ingestion.utils.logger import get_logger

logger = get_logger(__name__)

DEFAULT_CONFIG_PATH = Path(__file__).parent.parent / "config" / "ingestion_config.yml"


def load_config(config_path: str | Path | None = None) -> dict[str, Any]:
    """
    Load configuration from a YAML file and merge with environment variables.

    Environment variables with the prefix INGESTION_ override YAML values.
    For example, INGESTION_SOURCE_NAME overrides config["source_name"].

    Parameters
    ----------
    config_path : str or Path, optional
        Path to the YAML config file. Defaults to ingestion/config/ingestion_config.yml.

    Returns
    -------
    dict
        Merged configuration dictionary.
    """
    path = Path(config_path) if config_path else DEFAULT_CONFIG_PATH

    config: dict[str, Any] = {}

    if path.exists():
        with path.open("r", encoding="utf-8") as fh:
            loaded = yaml.safe_load(fh) or {}
            config.update(loaded)
        logger.debug("Config loaded from %s", path)
    else:
        logger.warning(
            "Config file not found at %s — using environment variables only.", path
        )

    # Overlay INGESTION_* environment variables
    for key, value in os.environ.items():
        if key.startswith("INGESTION_"):
            config_key = key[len("INGESTION_") :].lower()
            config[config_key] = value

    return config
