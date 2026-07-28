"""Unit tests for batch_id construction.

Regression guard for FIX-002 (docs/fix/fix_log.md): batch_id overflowed
audit.etl_batch_control.batch_id VARCHAR(50) once during the bronze build and
again on the longer gold target names. The first fix shortened the *format*
without enforcing the width, so the bug simply waited for longer names — these
tests make the width a guarantee rather than an intention.

Pure-function tests: no database connection is opened.
"""

from __future__ import annotations

from ingestion.utils.batch_control import _BATCH_ID_MAX_LEN, build_batch_id

# The longest target names the pipeline actually uses, per layer.
LONGEST_GOLD = "gold.fact_customer_behavior_snapshot"  # 36 chars — broke VARCHAR(50)
LONGEST_BRONZE = "oltp_customer_status_history"  # 28 chars


def test_batch_id_fits_the_column_for_the_longest_gold_target() -> None:
    """The name that actually caused the outage must now fit."""
    assert len(build_batch_id(LONGEST_GOLD)) <= _BATCH_ID_MAX_LEN


def test_batch_id_fits_the_column_for_an_absurdly_long_name() -> None:
    """Width is guaranteed for ANY name, not just the ones that exist today."""
    assert len(build_batch_id("gold." + "x" * 200)) <= _BATCH_ID_MAX_LEN


def test_long_names_keep_the_full_epoch_suffix() -> None:
    """Uniqueness lives in the suffix, so trimming must never touch it.

    A truncated epoch could collide against uq_etl_batch_control_batch_id.
    """
    batch_id = build_batch_id(LONGEST_GOLD)
    prefix, _, epoch = batch_id.rpartition(":")
    assert epoch.isdigit()
    assert len(epoch) == 16  # microsecond precision
    assert prefix  # a readable prefix survives


def test_short_names_are_not_truncated() -> None:
    """Names that already fit must pass through untouched."""
    for name in ("silver", LONGEST_BRONZE, "gold.fact_payments"):
        assert build_batch_id(name).startswith(f"{name}:")


def test_ids_are_unique_even_in_a_tight_loop() -> None:
    """Rapid successive calls must still differ.

    The DAG opens four gold batches back to back, so uniqueness cannot depend on
    the clock advancing between calls — two ids landing in the same microsecond
    would collide against uq_etl_batch_control_batch_id and fail the task.
    """
    ids = {build_batch_id(LONGEST_GOLD) for _ in range(500)}
    assert len(ids) == 500


def test_ids_increase_monotonically() -> None:
    """Ids sort in creation order, which makes the audit log readable."""
    epochs = [int(build_batch_id("silver").rpartition(":")[2]) for _ in range(20)]
    assert epochs == sorted(epochs)
    assert len(set(epochs)) == 20
