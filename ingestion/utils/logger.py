"""
logger.py
---------
Centralized logging configuration for the ingestion layer.
"""

from __future__ import annotations

import logging
import os
import sys


def get_logger(name: str) -> logging.Logger:
    """
    Return a configured logger for the given module name.

    Log level is controlled by the LOG_LEVEL environment variable.
    Defaults to INFO. Valid values: DEBUG, INFO, WARNING, ERROR, CRITICAL.
    """
    level_name = os.environ.get("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)

    logger = logging.getLogger(name)

    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setLevel(level)
        formatter = logging.Formatter(
            fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    logger.setLevel(level)
    return logger
