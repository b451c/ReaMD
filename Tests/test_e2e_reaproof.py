"""ReaProof-authored E2E (U7): drives ReaMD inside a real, isolated REAPER via
the permanent D26 test seam (ExtState b4s1c_ReaMD_Test/enable=1 set BEFORE dofile).
Needs the ReaProof platform: set REAPROOF_HOME or keep ../../ReaProof.
Run: PYTHONPATH=$REAPROOF_HOME/src pytest Tests/test_e2e_reaproof.py -q
COVERS = ['open_markdown_file', 'link_click_dispatch', 'extstate_migration']
REAMD_MAIN may point at another checkout's Main/ReaMD.lua (negative control).
"""
import os
import re
import sys
from pathlib import Path

REAPROOF = Path(os.environ.get("REAPROOF_HOME",
                               Path(__file__).resolve().parents[2] / "ReaProof"))
sys.path.insert(0, str(REAPROOF / "src"))

import pytest

from reaproof import paths
from reaproof.runner.session import ReaperSession

pytestmark = [pytest.mark.reaper, pytest.mark.slow]

REAMD_MAIN = Path(os.environ.get("REAMD_MAIN",
                                 Path(__file__).resolve().parents[1] / "Main" / "ReaMD.lua"))


def _session(name):
    """Isolated REAPER with ReaImGui. ReaProof only copies JS_ReaScriptAPI into
    Linux/Windows profiles; without ReaImGui, ReaMD stops at its modal
    "ReaImGui required" box and the bridge hangs."""
    imgui = sorted(paths.USER_USERPLUGINS.glob("reaper_imgui*"))
    if not imgui:
        pytest.fail(f"ReaImGui not found in {paths.USER_USERPLUGINS}")
    return ReaperSession(name, extensions=imgui[:1])


def _boot(s):
    s.eval('reaper.SetExtState("b4s1c_ReaMD_Test","enable","1",false); return true')
    res = s.eval(f"local ok, err = pcall(dofile, [[{REAMD_MAIN}]])\n"
                 "return {ok = ok, err = tostring(err)}")
    assert res and res.get("ok"), f"ReaMD failed to load: {res}"
    s.wait_until("_G.ReaMD_Test ~= nil", timeout=10, message="seam exposed")


def test_open_file_and_time_link_e2e(tmp_path):
    doc = tmp_path / "e2e_doc.md"
    doc.write_text("# Title\n\nHello **world**\n\n| A |\n|---|\n| 1 |\n",
                   encoding="utf-8")
    with _session("reamd-e2e") as s:
        _boot(s)
        # open_markdown_file through the seam: state model is the oracle
        res = s.eval(f"""
        ReaMD_Test.load_markdown_file([[{doc}]])
        local st = ReaMD_Test.state
        return {{path = st.file_path, kids = #(st.parsed_ast.children or {{}}),
                 window = reaper.JS_Window_Find("ReaMD", false) ~= nil}}""")
        assert res["path"] == str(doc)
        assert res["kids"] >= 2, f"AST children: {res['kids']}"
        assert res["window"], "ReaMD window not on screen"

        # time:// dispatch: the edit cursor MOVE is the observable effect
        assert s.eval('return ReaMD_Test.parse_time_spec("1:23")') == 83
        s.eval('reaper.SetEditCurPos(0, false, false); '
               'ReaMD_Test.handle_link_click("time://1:23"); return true')
        s.wait_until("reaper.GetCursorPosition() > 82.9", timeout=5,
                     message="edit cursor moved by time:// link")
        pos = s.eval("return reaper.GetCursorPosition()")
        assert abs(pos - 83.0) < 0.01, f"cursor at {pos}, expected 83"

        # MUTATION: a different timestamp must land elsewhere (assertion is
        # value-sensitive, not just "cursor moved")
        s.eval('ReaMD_Test.handle_link_click("time://0:10"); return true')
        s.wait_until("math.abs(reaper.GetCursorPosition() - 10.0) < 0.01",
                     timeout=5, message="cursor tracked the second timestamp")


def test_legacy_extstate_migrates_e2e(tmp_path):
    """v1.1.1: data saved by older versions under the unprefixed "ReaMD*"
    sections moves to "b4s1c_ReaMD*", and another script's key in the shared
    "ReaMD" project section survives, in memory and in the saved .rpp."""
    doc = tmp_path / "legacy_doc.md"
    doc.write_text("# Title\n\n## Intro\n\nLine\n", encoding="utf-8")
    rpp = tmp_path / "migrated.rpp"
    with _session("reamd-migrate") as s:
        # a v1.1.0 setting, present before ReaMD starts (default theme is light)
        s.eval('reaper.DeleteExtState("b4s1c_ReaMD_Config","theme",true); '
               'reaper.SetExtState("ReaMD_Config","theme","dark",true); return true')
        _boot(s)
        res = s.eval(f"""
        local json = package.loaded["json"]
        local path = package.loaded["utils"].normalize_path([[{doc}]])
        reaper.SetProjExtState(0, "ReaMD", "fragment_mapping", json.encode({{
            markdown_file = path,
            fragments = {{{{line_start = 3, line_end = 3, identifier = "Intro",
                           item_guids = {{"{{G1}}"}}}}}}}}))
        reaper.SetProjExtState(0, "ReaMD", "notes", "other script notes")
        ReaMD_Test.load_markdown_file([[{doc}]])
        local frags = package.loaded["scenario_engine"].fragment_map.fragments or {{}}
        local _, current = reaper.GetProjExtState(0, "b4s1c_ReaMD", "fragment_mapping")
        local legacy_size = reaper.GetProjExtState(0, "ReaMD", "fragment_mapping")
        local _, notes = reaper.GetProjExtState(0, "ReaMD", "notes")
        return {{ident = frags[1] and frags[1].identifier or "",
                 current = current, legacy_size = legacy_size, notes = notes,
                 theme_new = reaper.GetExtState("b4s1c_ReaMD_Config", "theme"),
                 theme_old = reaper.HasExtState("ReaMD_Config", "theme")}}""")
        assert res["ident"] == "Intro", f"legacy mapping not loaded: {res}"
        assert "Intro" in res["current"], "mapping not stored under b4s1c_ReaMD"
        assert res["legacy_size"] == 0, "legacy fragment_mapping key left behind"
        assert res["notes"] == "other script notes", \
            "migration wiped another script's data in the shared section"
        assert res["theme_new"] == "dark", f"setting not migrated: {res}"
        assert not res["theme_old"], "legacy setting left behind"

        # second channel: what actually lands in the project file
        s.eval(f"reaper.Main_SaveProjectEx(0, [[{rpp}]], 0); return true")
        s.wait_until(f"reaper.file_exists([[{rpp}]])", timeout=10,
                     message="project saved")
        # REAPER writes EXTSTATE section and key names upper-cased
        text = rpp.read_text(encoding="utf-8", errors="replace").lower()
        new_block = re.search(r"<b4s1c_reamd\n(.*?)\n\s*>", text, re.S)
        old_block = re.search(r"<reamd\n(.*?)\n\s*>", text, re.S)
        assert new_block and "fragment_mapping" in new_block.group(1), \
            "mapping missing from the prefixed section in the .rpp"
        assert old_block and "other script notes" in old_block.group(1), \
            "other script's key missing from the shared section in the .rpp"
        assert "fragment_mapping" not in old_block.group(1), \
            "legacy mapping still saved in the shared section"


def test_seam_is_inert_without_flag():
    """NEGATIVE CONTROL: without the ExtState flag the seam exposes nothing."""
    with _session("reamd-inert") as s:
        res = s.eval(f"local ok, err = pcall(dofile, [[{REAMD_MAIN}]])\n"
                     "return {ok = ok, seam = _G.ReaMD_Test ~= nil}")
        assert res["ok"]
        assert res["seam"] is False or res["seam"] is None, \
            "seam leaked without the flag"
