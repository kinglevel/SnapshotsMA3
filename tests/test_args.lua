-- tests/test_args.lua — args.parse grammar coverage (D-04..D-07, D-14 / RCL-03).
-- Header shape: tests/test_boundary.lua:5 (dofile helpers, no os.exit — run_all owns it).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")
local Args = h.loadModule("args.lua")

-- ── Task 1: happy-path grammar (verb / name / kv / flags) ────────────────────

h.run("verb+name only -> intent, no fade/breakdown", function()
  local intent = Args.parse("recall Verse")
  h.assertEq(intent.verb, "recall", "verb")
  h.assertEq(intent.name, "Verse", "name")
  h.assertNil(intent.fade, "no fade")
  h.assertNil(intent.breakdown, "no breakdown")
end)

h.run("fade= coerces to number; breakdown flag -> true", function()
  local intent = Args.parse("recall Verse fade=3 breakdown")
  h.assertEq(intent.verb, "recall", "verb")
  h.assertEq(intent.name, "Verse", "name")
  h.assertEq(intent.fade, 3, "fade value")
  h.assertTrue(type(intent.fade) == "number", "fade is a number")
  h.assertTrue(intent.breakdown == true, "breakdown true")
end)

h.run("verb is case-insensitive (RECALL / Recall -> recall)", function()
  h.assertEq(Args.parse("RECALL Verse").verb, "recall", "UPPER verb")
  h.assertEq(Args.parse("Recall Verse").verb, "recall", "Mixed verb")
end)

h.run("quoted name with a space parses as one token", function()
  local intent = Args.parse('recall "Big Chorus"')
  h.assertEq(intent.verb, "recall", "verb")
  h.assertEq(intent.name, "Big Chorus", "quoted name")
end)

h.run("kv + flag parse identically in any order", function()
  local a = Args.parse("recall X breakdown fade=3")
  local b = Args.parse("recall X fade=3 breakdown")
  h.assertEq(a.verb, b.verb, "verb equal")
  h.assertEq(a.name, b.name, "name equal")
  h.assertEq(a.fade, b.fade, "fade equal")
  h.assertEq(a.fade, 3, "fade=3")
  h.assertTrue(a.breakdown == true and b.breakdown == true, "breakdown both true")
end)

h.run("store / clear verbs parse", function()
  h.assertEq(Args.parse("store MySnap").verb, "store", "store verb")
  h.assertEq(Args.parse("store MySnap").name, "MySnap", "store name")
  h.assertEq(Args.parse("clear MySnap").verb, "clear", "clear verb")
  h.assertEq(Args.parse("clear MySnap").name, "MySnap", "clear name")
end)

h.run("module attaches as Snapshots.args", function()
  h.assertTrue(Snapshots.args == Args, "Snapshots.args is the module")
end)

-- ── Task 2: fail-loud rejection contract (six stable codes, always nil intent) ─

h.run("empty arg -> nil,{code=empty} (D-14)", function()
  local intent, err = Args.parse("")
  h.assertNil(intent, "nil intent")
  h.assertEq(err.code, "empty", "empty code")
  h.assertTrue(type(err.msg) == "string", "human msg present")
end)

h.run("whitespace-only arg -> nil,{code=empty}", function()
  local intent, err = Args.parse("   ")
  h.assertNil(intent, "nil intent")
  h.assertEq(err.code, "empty", "empty code")
end)

h.run("unknown verb -> nil,{code=unknown_verb} (D-07)", function()
  local intent, err = Args.parse("frobnicate Verse")
  h.assertNil(intent, "nil intent")
  h.assertEq(err.code, "unknown_verb", "unknown_verb code")
end)

h.run("missing name -> nil,{code=missing_name}", function()
  local intent, err = Args.parse("recall")
  h.assertNil(intent, "nil intent")
  h.assertEq(err.code, "missing_name", "missing_name code")
end)

h.run("empty quoted name -> nil,{code=missing_name} (WR-01)", function()
  local intent, err = Args.parse('recall ""')
  h.assertNil(intent, "nil intent")
  h.assertEq(err.code, "missing_name", "empty name rejected")
end)

h.run("whitespace quoted name -> nil,{code=missing_name} (WR-01)", function()
  local intent, err = Args.parse('store "   "')
  h.assertNil(intent, "nil intent")
  h.assertEq(err.code, "missing_name", "blank name rejected")
end)

h.run("unknown key -> nil,{code=unknown_key}", function()
  local intent, err = Args.parse("recall Verse wibble=2")
  h.assertNil(intent, "nil intent")
  h.assertEq(err.code, "unknown_key", "unknown_key code")
end)

h.run("unknown flag -> nil,{code=unknown_flag}", function()
  local intent, err = Args.parse("recall Verse sparkle")
  h.assertNil(intent, "nil intent")
  h.assertEq(err.code, "unknown_flag", "unknown_flag code")
end)

h.run("non-numeric fade -> nil,{code=bad_fade}", function()
  local intent, err = Args.parse("recall Verse fade=abc")
  h.assertNil(intent, "nil intent")
  h.assertEq(err.code, "bad_fade", "bad_fade code")
end)

-- ── Task 3 (Plan 09-03): Args.build — the round-trip inverse of Args.parse ────
-- build(spec) MUST produce the exact string parse accepts, so parse(build(spec)) ≡ spec.

h.run("args.build round-trips through parse: store -> raw string", function()
  h.assertEq(Args.build({ verb = "store", name = "Verse" }), 'store "Verse"', "store build")
end)

h.run("args.build round-trips through parse: default verb is recall when nil", function()
  h.assertEq(Args.build({ name = "Verse" }), 'recall "Verse"', "default verb recall")
end)

h.run("args.build round-trips through parse: spaced name + fade", function()
  local intent = Args.parse(Args.build({ verb = "recall", name = "Full Band", fade = 3 }))
  h.assertEq(intent.verb, "recall", "verb")
  h.assertEq(intent.name, "Full Band", "spaced name is one token")
  h.assertEq(intent.fade, 3, "fade round-trips")
  h.assertNil(intent.breakdown, "no breakdown")
end)

h.run("args.build round-trips through parse: snap=true forces fade=0 (RCL-04)", function()
  local intent = Args.parse(Args.build({ verb = "recall", name = "Verse", snap = true, fade = 5 }))
  h.assertEq(intent.fade, 0, "snap → fade 0 overriding any fade")
end)

h.run("args.build round-trips through parse: fade %g (3.0 -> 'fade=3')", function()
  local s = Args.build({ verb = "recall", name = "V", fade = 3.0 })
  h.assertTrue(s:find("fade=3", 1, true) ~= nil, "contains fade=3")
  h.assertNil(s:find("fade=3.0", 1, true), "no trailing .0")
  h.assertEq(Args.parse(s).fade, 3, "parses back to 3")
end)

h.run("args.build round-trips through parse: fractional fade (2.5)", function()
  local intent = Args.parse(Args.build({ verb = "recall", name = "V", fade = 2.5 }))
  h.assertEq(intent.fade, 2.5, "fractional fade round-trips")
end)

h.run("args.build round-trips through parse: nil fade + snap false OMITS fade= (RCL-03)", function()
  local s = Args.build({ verb = "recall", name = "V" })
  h.assertNil(s:find("fade=", 1, true), "no fade= emitted")
  h.assertNil(Args.parse(s).fade, "parse sees no fade")
end)

h.run("args.build round-trips through parse: breakdown appended for recall", function()
  local s = Args.build({ verb = "recall", name = "X", fade = 2, breakdown = true })
  h.assertTrue(s:match("breakdown$") ~= nil, "ends with breakdown")
  local intent = Args.parse(s)
  h.assertTrue(intent.breakdown == true, "breakdown round-trips")
  h.assertEq(intent.fade, 2, "fade also present")
end)

h.run("args.build round-trips through parse: breakdown NOT appended for store", function()
  local s = Args.build({ verb = "store", name = "X", breakdown = true, fade = 4 })
  h.assertNil(s:find("breakdown", 1, true), "no breakdown for store")
  h.assertEq(s, 'store "X"', "store ignores breakdown/fade")
end)
