from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "ConquestCash.lua").read_text(encoding="utf-8")


def test_retail_route_and_reward_are_exactly_scoped():
    for literal in (
        "zone = 231",
        "nation = 0",
        "id = 16844",
        "cp = 4000",
        "option = 32800",
        "id = 17723471",
        "name = 'Achantere, T.K.'",
        "menu_id = 32762",
        "id = 17723486",
        "name = 'Pirvidiauce'",
    ):
        assert literal in SOURCE


def test_floor_is_persisted_and_checked_before_each_purchase():
    assert "ConquestFloor = 0" in SOURCE
    assert "data/settings_%s.xml" in SOURCE
    assert "config.save(settings, 'all')" in SOURCE
    assert "if state.active then" in SOURCE
    assert "Stop the active run before changing" in SOURCE
    assert "state.cp - PROFILE.item.cp < settings.ConquestFloor" in SOURCE
    assert "current CP - 4000 >= configured floor" in (
        ROOT / "README.md"
    ).read_text(encoding="utf-8")


def test_purchase_uses_validation_then_nonautomated_finish():
    assert "send_dialog(PROFILE.item.option, true" in SOURCE
    assert "state.phase ~= 'buy_wait_validation'" in SOURCE
    assert "elseif id == 0x05C then" in SOURCE
    assert "handle_validation_packet(packet)" in SOURCE
    assert "state.pending_purchase and state.menu_final_sent" in SOURCE
    assert "item_id ~= PROFILE.item.id" in SOURCE
    assert "send_dialog(PROFILE.item.option, false" in SOURCE
    assert SOURCE.index("send_dialog(PROFILE.item.option, true") < SOURCE.index(
        "send_dialog(PROFILE.item.option, false"
    )


def test_only_pretransaction_menu_open_is_retried():
    for literal in (
        "MINIMUM_PURCHASE_DELAY = 1.00",
        "GuardMenuResponseTimeout = 2.50",
        "GuardMenuRetryDelay = 0.75",
        "GuardMenuAttempts = 3",
        "GuardStallDrainDelay = 5.00",
        "GuardStallReleaseDelay = 1.00",
        "VendorSettleDelay = 1.00",
        "VendorMenuResponseTimeout = 2.50",
        "VendorMenuRetryDelay = 0.75",
        "VendorMenuAttempts = 3",
        "state.phase == 'buy_wait_menu'",
        "set_phase('buy_retry_menu'",
        "state.phase == 'vendor_wait_shop'",
        "set_phase('vendor_retry_shop'",
        "no purchase was submitted",
        "no sale was submitted",
    ):
        assert literal in SOURCE
    assert "request_guard_menu()" in SOURCE
    assert "state.phase == 'buy_wait_validation'" not in re.search(
        r"if state\.deadline.*?if timestamp <",
        SOURCE,
        flags=re.DOTALL,
    ).group(0)


def test_exhausted_guard_open_vendors_only_a_safe_partial_batch():
    for literal in (
        "local function finish_partial_batch_recovery(reason)",
        "not state.menu_final_sent",
        "acquired_count() > 0",
        "set_phase('buy_stall_drain'",
        "state.phase == 'buy_stall_drain'",
        "cancel_open_menu()",
        "Vending the partial batch",
    ):
        assert literal in SOURCE

    recovery = re.search(
        r"local function finish_partial_batch_recovery\(reason\).*?^end$",
        SOURCE,
        flags=re.DOTALL | re.MULTILINE,
    )
    assert recovery
    assert "send_dialog(PROFILE.item.option" not in recovery.group(0)


def test_completed_purchase_event_status_waits_without_packets_or_stopping():
    for literal in (
        "PurchaseReleaseNoticeInterval = 30.00",
        "local function can_resume_into_release_wait(current_player)",
        "local function apply_local_event_release()",
        "api.inject_incoming(0x052",
        "state.local_release_attempted",
        "set_phase('buy_release_wait'",
        "state.phase == 'buy_release_wait'",
        "waiting safely for Idle before",
        "no movement or NPC packet will be sent",
    ):
        assert literal in SOURCE

    timeout_recovery = re.search(
        r"elseif state\.phase == 'buy_cooldown'.*?return\n\s*elseif "
        r"state\.phase == 'vendor_wait_shop'",
        SOURCE,
        flags=re.DOTALL,
    )
    assert timeout_recovery
    assert "finish_partial_batch_recovery" in timeout_recovery.group(0)
    assert "apply_local_event_release()" in timeout_recovery.group(0)
    assert "fail('Timed out in phase" not in timeout_recovery.group(0)


def test_untracked_target_items_require_explicit_adoption():
    assert "untracked_item_slots()" in SOURCE
    assert "Cannot start: Inventory contains" in SOURCE
    assert "//ccash adopt confirm" in SOURCE
    assert "adopt_inventory()" in SOURCE


def test_conquest_ui_and_validation_packets_are_blocked_only_while_owned():
    assert "native dialogue from taking client-side movement/menu ownership" in SOURCE
    assert "state.active and handle_menu_packet(packet)" in SOURCE
    assert "state.active and handle_validation_packet(packet)" in SOURCE
    assert "return state.phase:sub(1, 4) == 'buy_'" in SOURCE


def test_sales_are_owned_serialized_and_acknowledged():
    assert "state.acquired[index] = true" in SOURCE
    assert "valid_sale_item(index)" in SOURCE
    assert "send_sale_pair(index)" in SOURCE
    assert "response_type == 1" in SOURCE
    assert "complete_sale_if_inventory_updated()" in SOURCE
    assert "MaxSalesPerSession = 40" in SOURCE
    assert "sale.final_sent" in SOURCE
    assert "resolve sale-none confirm" in SOURCE
    assert "for index = 1, 80 do" not in SOURCE


def test_vendor_ui_block_is_narrowly_state_gated():
    block = re.search(
        r"elseif \(id == 0x03C or id == 0x03E\) and state\.active.*?return true",
        SOURCE,
        flags=re.DOTALL,
    )
    assert block
    assert "state.phase == 'vendor_wait_shop'" in block.group(0)
    assert "state.phase == 'vendor_retry_shop'" in block.group(0)


def test_thhud_style_progress_display_is_local_and_measured():
    for literal in (
        "local Hud = assert(loadfile(windower.addon_path .. 'lib/hud.lua'))()",
        "run_started_at = nil",
        "gil_earned = 0",
        "eta_seconds_per_item = nil",
        "state.gil_earned = (tonumber(state.gil_earned) or 0) + realized",
        "update_eta_cycle_sample()",
        "{text = '13M', color = HUD_COLORS.cp}",
        "return ('%dh%02dm'):format(hours, minutes)",
        "return ('%dm'):format(minutes)",
        "elseif command == 'hud' then",
    ):
        assert literal in SOURCE

    hud_source = (ROOT / "lib" / "hud.lua").read_text(encoding="utf-8")
    for literal in (
        "local LABELS = {'CP', 'GIL', 'ETA'}",
        "font = 'Consolas'",
        "stroke = {width = 2",
        "local FRAME_WIDTH = 128",
        "local FRAME_HEIGHT = 94",
        "local VALUE_FONT_SIZE = 12",
        "local function stable_text_size",
        "local texture = 'ccash_frame@2x.png'",
        "frame:draggable(self.placement)",
    ):
        assert literal in hud_source

    assert "value_width, value_height = stable_text_size" in hud_source
    assert "while value_width" not in hud_source

    assert (ROOT / "assets" / "ccash_frame.png").is_file()
    assert (ROOT / "assets" / "ccash_frame@2x.png").is_file()
    assert "local secs" not in SOURCE


def test_six_client_control_is_broadcast_but_execution_is_independent():
    assert "IPC_PREFIX = 'conquestcash:v1:'" in SOURCE
    assert "deterministic_start_delay" in SOURCE
    assert "windower.send_ipc_message" in SOURCE
    assert "Coordinator" not in SOURCE
    assert "leader" not in SOURCE.lower()


def test_safety_stops_cover_movement_combat_zone_and_manual_actions():
    for literal in (
        "StuckTimeout = 7.0",
        "Combat engagement detected.",
        "Zone change detected.",
        "Manual movement key detected",
        "Manual action packet 0x%03X detected",
        "transaction was not retried",
        "Gil cap would be crossed",
    ):
        assert literal in SOURCE


if __name__ == "__main__":
    tests = [
        value
        for name, value in sorted(globals().items())
        if name.startswith("test_") and callable(value)
    ]
    for test in tests:
        test()
    print(f"ConquestCash source guards passed ({len(tests)} tests).")
