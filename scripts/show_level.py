"""Print a generated wiki level: names, looks, every line, and what each rests on."""
import json
import sys

L = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "levels/level_1_habitable_zone.json", encoding="utf-8"))
W = L["wiki"]
B = W["because"]
print("TITLE", L["title"], "|", L["pickerLabel"])
print("BRIEF", L["briefing"], B.get("briefing"))
print("DIFF", W["difficulty"], "EXIT", W["exitTo"], "MONSTER", L["monsters"][0]["name"], B.get("monster"))
for n, t in L["themes"].items():
    print("THEME", n, t, B.get("themes." + n))
for r in L["rooms"]:
    c = L["contents"][r["id"]]
    items = [i["name"] for k in ("keys", "puzzle", "food", "rest") for i in c[k]]
    print(r["id"], r["theme"], "|", r["description"], "|", items, B.get("rooms." + r["id"]))
for c in L["contents"].values():
    for k in ("keys", "puzzle", "food", "rest"):
        for i in c[k]:
            print("ITEM", i["id"], "=", i["name"], "|", i.get("clue"), B.get("items." + i["id"]))
for k, v in L["text"].items():
    print("TEXT", k, "=", v, B.get("text." + k))
if "--facts" in sys.argv:
    for f in W["facts"]:
        print(f["id"], f["topic"], f["page"], "|", f["claim"], "||", f["quote"])
