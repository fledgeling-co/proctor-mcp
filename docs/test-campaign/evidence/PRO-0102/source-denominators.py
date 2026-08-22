# Live denominator probe for CASE-0426, CASE-0427, CASE-0428.
# Re-runs the exact expressions the three checks in selftest.py stand on and
# prints, for each, the population it judged and the finding drawn from it.
import importlib.util, json, os

ROOT = "/Users/lukerhodes/Dev/fledgeling-plugins"
SCRIPTS = os.path.join(ROOT, "plugins/reckon/skills/reckon/scripts")
spec = importlib.util.spec_from_file_location("reckon", os.path.join(SCRIPTS, "reckon.py"))
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)

# --- CASE-0426 · selftest.py check 13, "every class is produced by a real fixture"
produced = set()
FIXTURES = (
    ({"present": True, "header": {}, "cases": [], "flows": [], "components": [],
      "requirements": [{"id": "REQ-1", "text": "x", "evidence": "contradicted"}],
      "surfaces": [{"id": "SURF-1", "title": "orphan", "slug": "o"}],
      "defects": [{"id": "DEF-1", "title": "d", "status": "open"},
                  {"id": "DEF-2", "title": "d2", "status": "fixed"},
                  {"id": "DEF-3", "title": "d3", "status": "wontfix"}]},
     [{"id": "BRIEF-1", "file": "f.md", "path": "p", "title": "t", "text": "no ids",
       "status": "", "generated_by": None, "source_ids": []}], []),
    ({"present": True, "header": {},
      "cases": [{"id": "CASE-1", "surface": "SURF-1", "state": "s", "status": "pass",
                 "oracle": "effect-witness"},
                {"id": "CASE-2", "surface": "SURF-1", "state": "s", "status": "blocked",
                 "oracle": "outcome"}],
      "flows": [], "components": [],
      "requirements": [{"id": "REQ-1", "text": "x", "evidence": "observed"}],
      "surfaces": [{"id": "SURF-1", "title": "claimed", "slug": "c"}], "defects": []},
     [{"id": "BRIEF-2", "file": "g.md", "path": "p", "title": "t", "text": "REQ-1 and SURF-1",
       "status": "", "generated_by": None, "source_ids": []},
      {"id": "BRIEF-3", "file": "h.md", "path": "p", "title": "t", "text": "REQ-404",
       "status": "", "generated_by": None, "source_ids": []}],
     [{"brief": "BRIEF-2", "target": "REQ-1", "method": "cited", "confidence": 1.0},
      {"brief": "BRIEF-2", "target": "SURF-1", "method": "cited", "confidence": 1.0},
      {"brief": "BRIEF-3", "target": "REQ-404", "method": "cited", "confidence": 1.0}]),
)
for camp, briefs, edges in FIXTURES:
    produced |= {r["class"] for r in R.classify(briefs, camp, edges, False)}
unreachable = sorted(set(R.CLASSES) - produced)
print("CASE-0426  check 13 'every class is produced by a real fixture'")
print("  population judged : %d class(es) in reckon.CLASSES -> %s"
      % (len(R.CLASSES), ", ".join(R.CLASSES)))
print("  finding           : %d unreachable -> %s" % (len(unreachable), unreachable or "none"))
print("  examined          : %d" % len(R.CLASSES))

# --- CASE-0427 · selftest.py check 14, first assertion
plugin_json = os.path.join(ROOT, "plugins", "reckon", ".claude-plugin", "plugin.json")
market_json = os.path.join(ROOT, ".claude-plugin", "marketplace.json")
with open(plugin_json, encoding="utf-8") as fh:
    mine = json.load(fh)["version"]
with open(market_json, encoding="utf-8") as fh:
    market = json.load(fh)["plugins"]
listed = [x for x in market if x["name"] == "reckon"][0]["version"]
declarations = [("plugins/reckon/.claude-plugin/plugin.json:version", mine),
                (".claude-plugin/marketplace.json:plugins[reckon].version", listed)]
drift = len({v for _, v in declarations}) - 1
print()
print("CASE-0427  check 14 first assertion 'the manifest and the marketplace agree'")
print("  population judged : %d version declaration(s) reckon publishes" % len(declarations))
for where, v in declarations:
    print("                      %s = %s" % (where, v))
print("  finding           : %d disagreement(s)" % drift)
print("  examined          : %d" % len(declarations))
print("  not the denominator: %d plugin entries exist in marketplace.json; the check reads one."
      % len(market))

# --- CASE-0428 · selftest.py check 14, second assertion
parts = tuple(int(x) for x in mine.split(".")[:3])
print()
print("CASE-0428  check 14 second assertion 'the published version carries these repairs'")
print("  population judged : 1 published version string -> plugin.json:version = %s" % mine)
print("  finding           : %d below the 1.1.0 floor" % (0 if parts >= (1, 1, 0) else 1))
print("  examined          : 1")
