#!/usr/bin/env python3
"""set-dev-root.py  --  LingTeX-Word

Store the clone's LingTeX-Word folder in a template's settings.xml as the
document variable LingTeX_DevRoot, with Word quit. This is what SetDevRoot in
modImport does from inside Word; doing it here means the template in Word's
startup folder can be set up without opening it.

    python3 tools/set-dev-root.py path/to/LingTeX.dotm /path/to/LingTeX-Word

A Word file is a zip; word/settings.xml holds <w:docVars>. Element order in
settings.xml is fixed by the schema and Word rejects a file that breaks it, so
an existing docVars is edited in place, and a new one goes immediately before
the first element that follows it in the schema (rsids, mathPr, ...).
"""
import re
import sys
import zipfile
from xml.sax.saxutils import escape

VAR = "LingTeX_DevRoot"
FOLLOWERS = ["<w:rsids", "<m:mathPr", "<w:attachedSchema", "<w:themeFontLang",
             "<w:clrSchemeMapping", "<w:doNotIncludeSubdocsInStats",
             "<w:doNotAutoCompressPictures", "<w:forceUpgrade", "<w:captions",
             "<w:readModeInkLockDown", "<w:smartTagType", "<sl:schemaLibrary",
             "<w:shapeDefaults", "<w:doNotEmbedSmartTags", "<w:decimalSymbol",
             "<w:listSeparator", "</w:settings>"]


def set_var(xml, name, value):
    var = '<w:docVar w:name="%s" w:val="%s"/>' % (name, escape(value, {'"': "&quot;"}))
    m = re.search(r'<w:docVars>(.*?)</w:docVars>', xml, re.S)
    if m:
        body = re.sub(r'<w:docVar w:name="%s"[^>]*/>' % re.escape(name), "", m.group(1))
        return xml[:m.start()] + "<w:docVars>" + body + var + "</w:docVars>" + xml[m.end():]
    for tag in FOLLOWERS:
        i = xml.find(tag)
        if i != -1:
            return xml[:i] + "<w:docVars>" + var + "</w:docVars>" + xml[i:]
    raise SystemExit("set-dev-root: no </w:settings> in settings.xml")


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    path, root = sys.argv[1], sys.argv[2].rstrip("/")
    with zipfile.ZipFile(path) as z:
        items = z.infolist()
        data = {i.filename: z.read(i.filename) for i in items}
    if "word/settings.xml" not in data:
        raise SystemExit("set-dev-root: %s has no word/settings.xml" % path)
    xml = data["word/settings.xml"].decode("utf-8")
    data["word/settings.xml"] = set_var(xml, VAR, root).encode("utf-8")
    tmp = path + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for i in items:
            z.writestr(i.filename, data[i.filename])
    import os
    os.replace(tmp, path)
    print("  %s = %s  in %s" % (VAR, root, path))


if __name__ == "__main__":
    main()
