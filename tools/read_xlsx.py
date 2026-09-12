# -*- coding: utf-8 -*-
## 零依赖 xlsx 读取器：解 ZIP + 解析 XML，输出所有工作表的非空单元格。
## 用法：python tools/read_xlsx.py <路径.xlsx>
import sys
import re
import zipfile
import xml.etree.ElementTree as ET

NS_MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
NS_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"


def read_sheet(path: str) -> None:
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in root.findall(f"{NS_MAIN}si"):
            shared.append("".join(t.text or "" for t in si.iter(f"{NS_MAIN}t")))

    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    rid_to_target = {rel.get("Id"): rel.get("Target") for rel in rels}

    for sheet in wb.find(f"{NS_MAIN}sheets"):
        name = sheet.get("name")
        target = rid_to_target.get(sheet.get(f"{NS_REL}id"), "")
        spath = target.lstrip("/") if target.startswith("/") else "xl/" + target
        print(f"\n===== SHEET: {name} =====")
        sroot = ET.fromstring(z.read(spath))
        merges = sroot.find(f"{NS_MAIN}mergeCells")
        if merges is not None:
            refs = [m.get("ref") for m in merges]
            print(f"[合并单元格 {len(refs)} 处]: " + ", ".join(refs[:50]) + ("…" if len(refs) > 50 else ""))
        for row in sroot.iter(f"{NS_MAIN}row"):
            cells = []
            for c in row.findall(f"{NS_MAIN}c"):
                ref = c.get("r") or ""
                t = c.get("t")
                v = c.find(f"{NS_MAIN}v")
                isel = c.find(f"{NS_MAIN}is")
                if t == "s" and v is not None:
                    val = shared[int(v.text)]
                elif t == "inlineStr" and isel is not None:
                    val = "".join(tt.text or "" for tt in isel.iter(f"{NS_MAIN}t"))
                elif v is not None:
                    val = v.text or ""
                else:
                    val = ""
                if val.strip() != "":
                    cells.append(f"{ref}={val.strip()}")
            if cells:
                print(f"R{row.get('r')}: " + " | ".join(cells))


if __name__ == "__main__":
    read_sheet(sys.argv[1])
