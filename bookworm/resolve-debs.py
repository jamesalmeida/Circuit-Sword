import gzip, lzma, re, sys
def parse(data, base):
    pk = {}
    for block in data.split("\n\n"):
        f = {}
        for line in block.splitlines():
            if line and not line[0].isspace() and ":" in line:
                k, v = line.split(":", 1); f[k] = v.strip()
        if "Package" in f:
            f["base"] = base
            pk.setdefault(f["Package"], f)  # first wins (rpi repo listed first)
            for prov in re.split(r",\s*", f.get("Provides", "")):
                if prov: pk.setdefault("virt:" + prov.split()[0], f)
    return pk
w = sys.argv[1]
pk = parse(gzip.open(w + "/rpi-Packages.gz", "rt").read(), "http://archive.raspberrypi.com/debian/")
for k, v in parse(lzma.open(w + "/raspbian-Packages.xz", "rt").read(), "http://raspbian.raspberrypi.com/raspbian/").items():
    pk.setdefault(k, v)
want = sys.argv[2:]; seen = {}; todo = list(want)
while todo:
    n = todo.pop()
    f = pk.get(n) or pk.get("virt:" + n)
    if not f: print("MISSING", n, file=sys.stderr); continue
    if f["Package"] in seen: continue
    if f.get("Priority") in ("required", "important") or f.get("Essential") == "yes": continue
    seen[f["Package"]] = f
    for dep in re.split(r",\s*", f.get("Depends", "") + ("," + f["Pre-Depends"] if f.get("Pre-Depends") else "")):
        if dep.strip(): todo.append(dep.split("|")[0].split()[0].split(":")[0])
tot = 0
for p, f in sorted(seen.items()):
    tot += int(f["Size"]); print(f["base"] + f["Filename"])
print("TOTAL_MB %.1f COUNT %d" % (tot / 1e6, len(seen)), file=sys.stderr)
