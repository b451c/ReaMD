"""ReaProof-authored E2E (U7): drives ReaMD inside a real, isolated REAPER via
the permanent D26 test seam (ExtState ReaMD_Test/enable=1 set BEFORE dofile).
Needs the ReaProof platform: set REAPROOF_HOME or keep ../../ReaProof.
Run: PYTHONPATH=$REAPROOF_HOME/src pytest Tests/test_e2e_reaproof.py -q
COVERS = ['open_markdown_file', 'link_click_dispatch']
"""
import os
import sys
from pathlib import Path

REAPROOF = Path(os.environ.get("REAPROOF_HOME",
                               Path(__file__).resolve().parents[2] / "ReaProof"))
sys.path.insert(0, str(REAPROOF / "src"))

import pytest

from reaproof.runner.session import ReaperSession

pytestmark = [pytest.mark.reaper, pytest.mark.slow]

REAMD_MAIN = Path(__file__).resolve().parents[1] / "Main" / "ReaMD.lua"


def _boot(s):
    s.eval('reaper.SetExtState("ReaMD_Test","enable","1",false); return true')
    res = s.eval(f"local ok, err = pcall(dofile, [[{REAMD_MAIN}]])\n"
                 "return {ok = ok, err = tostring(err)}")
    assert res and res.get("ok"), f"ReaMD failed to load: {res}"
    s.wait_until("_G.ReaMD_Test ~= nil", timeout=10, message="seam exposed")


def test_open_file_and_time_link_e2e(tmp_path):
    doc = tmp_path / "e2e_doc.md"
    doc.write_text("# Title\n\nHello **world**\n\n| A |\n|---|\n| 1 |\n",
                   encoding="utf-8")
    with ReaperSession("reamd-e2e") as s:
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


def test_seam_is_inert_without_flag():
    """NEGATIVE CONTROL: without the ExtState flag the seam exposes nothing."""
    with ReaperSession("reamd-inert") as s:
        res = s.eval(f"local ok, err = pcall(dofile, [[{REAMD_MAIN}]])\n"
                     "return {ok = ok, seam = _G.ReaMD_Test ~= nil}")
        assert res["ok"]
        assert res["seam"] is False or res["seam"] is None, \
            "seam leaked without the flag"
