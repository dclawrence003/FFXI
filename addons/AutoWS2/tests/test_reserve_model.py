"""Behavioral model tests for AutoWS2's aftermath reserve invariants.

These tests exercise the decisions independently of Windower. They intentionally
mirror the safety-critical ordering in AutoWS2.lua.
"""

from dataclasses import dataclass


@dataclass
class State:
    reserve_latched: bool = False


def reserve_window(
    rate, tp, fallback=18, minimum=4, maximum=30, safety=3
):
    deficit = max(0, 3000 - tp)
    if rate is None or rate <= 0:
        predicted = fallback * deficit / 3000 + safety
    else:
        predicted = deficit / rate + safety
    return max(minimum, min(maximum, predicted))


def decide(state, tp, aftermath_active, remaining, rate):
    window = reserve_window(rate, tp)
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
    assert reserve_window(150, 1200) == 15
    assert reserve_window(1000, 2500) == 4
    assert reserve_window(50, 0) == 30
    assert reserve_window(None, 1500) == 12


def test_existing_tp_shortens_reserve_window():
    assert reserve_window(150, 0) == 23
    assert reserve_window(150, 1000) < reserve_window(150, 0)
    assert reserve_window(150, 2000) < reserve_window(150, 1000)


def test_reserve_latch_never_fires_early():
    state = State()
    assert decide(state, 1100, True, 15, 150) == "hold_below_3000"
    assert state.reserve_latched
    assert decide(state, 2999, False, 0, 150) == "hold_below_3000"


def test_3000_holds_until_aftermath_is_gone():
    state = State(reserve_latched=True)
    assert decide(state, 3000, True, 20, 150) == "hold_at_3000"
    assert decide(state, 3000, True, 1, 150) == "hold_at_3000"
    assert decide(state, 3000, False, 0, 150) == "aftermath_ws"


def test_latch_does_not_release_if_rate_changes():
    state = State()
    assert decide(state, 1000, True, 15, 150) == "hold_below_3000"
    assert decide(state, 2000, True, 90, 300) == "hold_below_3000"
    assert state.reserve_latched


def test_unknown_timer_does_not_prepull_reserve():
    state = State()
    assert decide(state, 1000, True, None, 150) == "normal_ws"
    assert not state.reserve_latched
