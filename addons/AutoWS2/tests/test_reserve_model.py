"""Behavioral model tests for AutoWS2's aftermath reserve invariants.

These tests exercise the decisions independently of Windower. They intentionally
mirror the safety-critical ordering in AutoWS2.lua.
"""

from dataclasses import dataclass


@dataclass
class State:
    reserve_latched: bool = False


def reserve_window(rate, fallback=20, minimum=12, maximum=35, safety=4):
    if rate is None or rate <= 0:
        return fallback
    return max(minimum, min(maximum, 3000 / rate + safety))


def decide(state, tp, aftermath_active, remaining, rate):
    window = reserve_window(rate)
    if not state.reserve_latched:
        if not aftermath_active or (
            remaining is not None and remaining <= window
        ):
            state.reserve_latched = True

    if state.reserve_latched:
        if tp != 3000:
            return "hold_below_3000"
        if aftermath_active:
            return "hold_at_3000"
        return "aftermath_ws"

    return "normal_ws"


def test_dynamic_window():
    assert reserve_window(150) == 24
    assert reserve_window(1000) == 12
    assert reserve_window(50) == 35
    assert reserve_window(None) == 20


def test_reserve_latch_never_fires_early():
    state = State()
    assert decide(state, 1100, True, 20, 150) == "hold_below_3000"
    assert state.reserve_latched
    assert decide(state, 2999, False, 0, 150) == "hold_below_3000"


def test_3000_holds_until_aftermath_is_gone():
    state = State()
    assert decide(state, 3000, True, 20, 150) == "hold_at_3000"
    assert decide(state, 3000, True, 1, 150) == "hold_at_3000"
    assert decide(state, 3000, False, 0, 150) == "aftermath_ws"


def test_latch_does_not_release_if_rate_changes():
    state = State()
    assert decide(state, 1000, True, 20, 150) == "hold_below_3000"
    assert decide(state, 2000, True, 90, 300) == "hold_below_3000"
    assert state.reserve_latched


def test_unknown_timer_does_not_prepull_reserve():
    state = State()
    assert decide(state, 1000, True, None, 150) == "normal_ws"
    assert not state.reserve_latched

