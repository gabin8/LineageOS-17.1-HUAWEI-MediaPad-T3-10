#!/usr/bin/env python3
"""Vendor ABI audit (handoff 5, Phase 2): check every ELF in a vendor tree against a system's libs.

  vendor-abi-audit.py <vendor root> <system root> [--shim LIB:SHIM ...] [--json OUT]
  vendor-abi-audit.py --diff <baseline.json> <new.json>

<system root> is a directory holding lib/ and lib64/ (an extracted /system, or
out/target/product/<dev>/system); flattened APEX libs under <system root>/apex/*/lib{,64}[/bionic]
are searched too. For each vendor ELF it resolves DT_NEEDED transitively (system, then APEX, then
the vendor lib dir: the legacy, namespace-less linker search order) and reports
  - missing_libs:   NEEDED libraries found nowhere
  - unresolved:     undefined non-weak dynamic symbols not defined anywhere in the ELF's own
                    NEEDED closure, split into
                      elsewhere: defined by some other library (a dlopen()ed HAL may still get it
                                 from its host process's global scope at runtime)
                      nowhere:   defined by no library at all: a hard failure if it is called
--shim LIB:SHIM adds SHIM's symbols to LIB's closure (TARGET_LD_SHIM_LIBS).
Needs GNU readelf.
"""
import json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

SYM_RE = re.compile(r'^\s*\d+:\s+[0-9a-fA-F]+\s+\S+\s+(\w+)\s+(\w+)\s+\w+\s+(\S+)\s+(\S+)')


def is_elf(path):
    try:
        with open(path, 'rb') as f:
            head = f.read(5)
        return head[:4] == b'\x7fELF' and head[4] in (1, 2)
    except OSError:
        return False


def elf_class(path):
    with open(path, 'rb') as f:
        return 64 if f.read(5)[4] == 2 else 32


def read_elf(path):
    dyn = subprocess.run(['readelf', '-dW', path], capture_output=True, text=True).stdout
    needed = re.findall(r'\(NEEDED\)\s+Shared library: \[([^\]]+)\]', dyn)
    syms = subprocess.run(['readelf', '--dyn-syms', '-W', path], capture_output=True, text=True).stdout
    defined, undef = set(), set()
    for line in syms.splitlines():
        m = SYM_RE.match(line)
        if not m:
            continue
        typ, bind, ndx, name = m.groups()
        name = name.split('@')[0]
        if not name or typ in ('SECTION', 'FILE'):
            continue
        if ndx == 'UND':
            if bind == 'GLOBAL':
                undef.add(name)
        elif bind in ('GLOBAL', 'WEAK', 'UNIQUE'):
            defined.add(name)
    return {'needed': needed, 'defined': defined, 'undef': undef, 'bits': elf_class(path)}


def lib_dirs(root, bits):
    sub = 'lib64' if bits == 64 else 'lib'
    dirs = [os.path.join(root, sub)]
    apex = os.path.join(root, 'apex')
    if os.path.isdir(apex):
        for a in sorted(os.listdir(apex)):
            for d in (os.path.join(apex, a, sub), os.path.join(apex, a, sub, 'bionic')):
                if os.path.isdir(d):
                    dirs.append(d)
    return dirs


def audit(vendor, system, shims):
    elves = []
    for dp, _, files in os.walk(vendor):
        for fn in files:
            p = os.path.join(dp, fn)
            if not os.path.islink(p) and is_elf(p):
                elves.append(p)
    # legacy (namespace-less) linker order: /system/${LIB} (+ APEX), then /vendor/${LIB}. The EMUI
    # vendor ships its own older libcutils/libutils/...; the system copies win.
    search = {b: lib_dirs(system, b) + [os.path.join(vendor, 'lib64' if b == 64 else 'lib')]
              for b in (32, 64)}
    libs = {}  # (bits, name) -> path
    for b, dirs in search.items():
        for d in dirs:
            if not os.path.isdir(d):
                continue
            for fn in os.listdir(d):
                p = os.path.join(d, fn)
                if (b, fn) not in libs and os.path.isfile(p) and is_elf(p) and elf_class(p) == b:
                    libs[(b, fn)] = p
    paths = sorted(set(elves) | set(libs.values()))
    with ThreadPoolExecutor(os.cpu_count()) as ex:
        info = dict(zip(paths, ex.map(read_elf, paths)))
    anydef = {32: {}, 64: {}}
    for (b, name), p in libs.items():
        for s in info[p]['defined']:
            anydef[b].setdefault(s, name)
    shim_of = {}
    for spec in shims:
        lib, shim = spec.split(':', 1)
        shim_of.setdefault(lib, []).append(shim)
    report = {}
    for p in elves:
        e, b = info[p], info[p]['bits']
        seen, queue, missing, closure_def = set(), list(e['needed']), [], set(e['defined'])
        for s in shim_of.get(os.path.basename(p), []):
            queue.append(s)
        while queue:
            n = queue.pop()
            if n in seen:
                continue
            seen.add(n)
            lp = libs.get((b, n))
            if not lp:
                missing.append(n)
                continue
            closure_def |= info[lp]['defined']
            queue += info[lp]['needed'] + shim_of.get(n, [])
        unres = sorted(e['undef'] - closure_def)
        rel = os.path.relpath(p, vendor)
        if missing or unres:
            report[rel] = {
                'missing_libs': sorted(missing),
                'elsewhere': {s: anydef[b][s] for s in unres if s in anydef[b]},
                'nowhere': [s for s in unres if s not in anydef[b]],
            }
    return {'elves': len(elves), 'system_libs': sum(1 for (b, _), p in libs.items()
                                                    if not p.startswith(os.path.abspath(vendor))),
            'report': report}


def summary(r):
    rep = r['report']
    print(f"{r['elves']} vendor ELFs; {len(rep)} with problems: "
          f"{sum(1 for v in rep.values() if v['missing_libs'])} missing libs, "
          f"{sum(1 for v in rep.values() if v['nowhere'])} with symbols defined nowhere, "
          f"{sum(1 for v in rep.values() if v['elsewhere'])} resolved only outside their NEEDED closure")


def diff(a, b):
    ra, rb = a['report'], b['report']
    for k in sorted(rb):
        old, new = ra.get(k, {'missing_libs': [], 'elsewhere': {}, 'nowhere': []}), rb[k]
        ml = sorted(set(new['missing_libs']) - set(old['missing_libs']))
        nw = sorted(set(new['nowhere']) - set(old['nowhere']))
        el = sorted(set(new['elsewhere']) - set(old['elsewhere']))
        if ml or nw or el:
            print(k)
            if ml: print('  NEW missing libs:', ' '.join(ml))
            if nw: print('  NEW symbols defined nowhere:', ' '.join(nw))
            if el: print('  NEW symbols outside closure:', ' '.join(f"{s}({new['elsewhere'][s]})" for s in el))


if __name__ == '__main__':
    a = sys.argv[1:]
    if a and a[0] == '--diff':
        diff(json.load(open(a[1])), json.load(open(a[2])))
        sys.exit(0)
    shims = [a[i + 1] for i, x in enumerate(a) if x == '--shim']
    out = a[a.index('--json') + 1] if '--json' in a else None
    pos = [x for i, x in enumerate(a) if not x.startswith('--') and (i == 0 or a[i - 1] not in ('--shim', '--json'))]
    r = audit(os.path.abspath(pos[0]), os.path.abspath(pos[1]), shims)
    summary(r)
    if out:
        json.dump(r, open(out, 'w'), indent=1, sort_keys=True)
