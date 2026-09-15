"""Read enum constants from an MSFT-format type library (.tlb/.olb), read-only.

The same values the VBA editor's Object Browser shows, hidden members included,
without opening PowerPoint.  Office for Mac keeps its type libraries in
  /Applications/Microsoft PowerPoint.app/Contents/SharedSupport/Type Libraries/
(Microsoft PowerPoint.tlb, mso.tlb, Microsoft Word.tlb, VbaEN6.tlb, ...).

  python3 msft_enums.py "<library>.tlb" out.json [EnumName ...]

writes every enum to out.json and prints the named ones.  Checked against the
Object Browser on PowerPoint 16.112 for Mac (ppSaveAsOpenXMLPresentationMacroEnabled
= 16, ppSaveAsOpenXMLTemplateMacroEnabled = 20, ppSaveAsBMP = 25).
Layout follows Wine's typelib.c (MSFT_Header, segment directory, MSFT_TypeInfoBase,
MSFT_DoVars, MSFT_ReadValue, MSFT_ReadName)."""
import json, struct, sys

def i32(b, o): return struct.unpack_from('<i', b, o)[0]
def u16(b, o): return struct.unpack_from('<H', b, o)[0]

def read(path):
    b = open(path, 'rb').read()
    if b[:4] != b'MSFT':
        raise SystemExit(f'{path}: not an MSFT type library (magic {b[:4]!r})')
    varflags, ntypes = i32(b, 0x14), i32(b, 0x20)
    pos = 0x54 + (4 if varflags & 0x100 else 0) + 4 * ntypes
    seg = [(i32(b, pos + 16 * k), i32(b, pos + 16 * k + 4)) for k in range(15)]
    tinfo_off, name_off, cust_off = seg[0][0], seg[7][0], seg[11][0]

    def name(off):
        if off < 0: return None
        n = i32(b, name_off + off + 8) & 0xff
        return b[name_off + off + 12: name_off + off + 12 + n].decode('latin-1')

    def value(off):
        if off < 0:                       # packed inline
            vt = (off & 0x7c000000) >> 26
            v = off & 0x3ffffff
            return v, vt
        vt = u16(b, cust_off + off)
        if vt in (3, 22):   return i32(b, cust_off + off + 2), vt   # VT_I4, VT_INT
        if vt in (2,):      return struct.unpack_from('<h', b, cust_off + off + 2)[0], vt
        if vt in (19, 23):  return struct.unpack_from('<I', b, cust_off + off + 2)[0], vt
        return None, vt

    enums = {}
    for t in range(ntypes):
        base = tinfo_off + t * 0x64
        kind = i32(b, base) & 0xf
        if kind != 0:                     # TKIND_ENUM
            continue
        memoffset, celement = i32(b, base + 4), i32(b, base + 0x18)
        cfuncs, cvars = celement & 0xffff, (celement >> 16) & 0xffff
        tname = name(i32(b, base + 0x34))
        infolen = i32(b, memoffset)
        recoffset = memoffset + 4
        consts = []
        for i in range(cvars):
            noff = i32(b, memoffset + infolen + (2 * cfuncs + cvars + i + 1) * 4)
            reclen = i32(b, recoffset) & 0xff
            # record: Info, DataType, Flags, VarKind(u16), vardescsize(u16), OffsValue
            varkind = u16(b, recoffset + 12)
            offsvalue = i32(b, recoffset + 16)
            v, vt = value(offsvalue) if varkind == 2 else (None, None)   # VAR_CONST
            consts.append((name(noff), v))
            recoffset += reclen
        enums[tname] = consts
    return enums

if __name__ == '__main__':
    path, out = sys.argv[1], sys.argv[2]
    enums = read(path)
    json.dump(enums, open(out, 'w'), indent=1)
    print(f'{len(enums)} enums written to {out}')
    for want in sys.argv[3:]:
        for en, cs in enums.items():
            if en and want.lower() in en.lower():
                print(f'== {en}')
                for n, v in sorted(cs, key=lambda c: (c[1] is None, c[1])):
                    print(f'   {v!s:>6}  {n}')
