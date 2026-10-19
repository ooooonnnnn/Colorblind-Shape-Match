extends RefCounted
## Writes a minimal Excel workbook (.xlsx): one worksheet per entry, text and
## numbers only, with optional bold cells and column widths. An .xlsx file is
## a zip of XML parts, written here with ZIPPacker; it opens in Excel, Google
## Sheets and LibreOffice.
##
## Each sheet is {name: String, rows: Array of rows, widths: Array of column
## widths in characters}. A row is an Array of cells; a cell is a String, a
## number, null (left empty), or {value, bold: true} for a bold one.

const TEMP := "user://export.xlsx"  # packed here first, then copied to the chosen path
const MAIN_NS := "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
const REL_NS := "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
const PACKAGE_REL_NS := "http://schemas.openxmlformats.org/package/2006/relationships"
const STYLES := """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="%s">
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>""" % MAIN_NS
const XML_HEAD := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'


static func write(path: String, sheets: Array) -> Error:
	var zip := ZIPPacker.new()
	var err := zip.open(TEMP)
	if err != OK:
		return err
	var names := _sheet_names(sheets)
	var types := PackedStringArray()
	var listed := PackedStringArray()
	var rels := PackedStringArray()
	for i in sheets.size():
		types.append('<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' % (i + 1))
		listed.append('<sheet name="%s" sheetId="%d" r:id="rId%d"/>' % [_escape(names[i]), i + 1, i + 1])
		rels.append('<Relationship Id="rId%d" Type="%s/worksheet" Target="worksheets/sheet%d.xml"/>' % [i + 1, REL_NS, i + 1])
	rels.append('<Relationship Id="rId%d" Type="%s/styles" Target="styles.xml"/>' % [sheets.size() + 1, REL_NS])

	_add(zip, "[Content_Types].xml", XML_HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
			+ '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
			+ '<Default Extension="xml" ContentType="application/xml"/>'
			+ '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
			+ '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
			+ "".join(types) + "</Types>")
	_add(zip, "_rels/.rels", XML_HEAD + '<Relationships xmlns="%s"><Relationship Id="rId1" Type="%s/officeDocument" Target="xl/workbook.xml"/></Relationships>' % [PACKAGE_REL_NS, REL_NS])
	_add(zip, "xl/workbook.xml", XML_HEAD + '<workbook xmlns="%s" xmlns:r="%s"><sheets>%s</sheets></workbook>' % [MAIN_NS, REL_NS, "".join(listed)])
	_add(zip, "xl/_rels/workbook.xml.rels", XML_HEAD + '<Relationships xmlns="%s">%s</Relationships>' % [PACKAGE_REL_NS, "".join(rels)])
	_add(zip, "xl/styles.xml", STYLES)
	for i in sheets.size():
		_add(zip, "xl/worksheets/sheet%d.xml" % (i + 1), _sheet_xml(sheets[i]))
	zip.close()

	# Copied over rather than packed in place, so any path the save dialog
	# hands back works, a tablet's shared storage included.
	var bytes := FileAccess.get_file_as_bytes(TEMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return FileAccess.get_open_error()
	out.store_buffer(bytes)
	out.close()
	return OK


static func _add(zip: ZIPPacker, part: String, text: String) -> void:
	zip.start_file(part)
	zip.write_file(text.to_utf8_buffer())
	zip.close_file()


static func _sheet_xml(sheet: Dictionary) -> String:
	var cols := PackedStringArray()
	var widths: Array = sheet.get("widths", [])
	for i in widths.size():
		cols.append('<col min="%d" max="%d" width="%s" customWidth="1"/>' % [i + 1, i + 1, widths[i]])
	var rows := PackedStringArray()
	var rows_in: Array = sheet.rows
	for r in rows_in.size():
		var cells := PackedStringArray()
		var row: Array = rows_in[r]
		for c in row.size():
			var cell = row[c]
			var bold := false
			if cell is Dictionary:
				bold = cell.get("bold", false)
				cell = cell.get("value")
			if cell == null or (cell is String and cell.is_empty()):
				continue
			var ref := "%s%d" % [_column(c), r + 1]
			var style := ' s="1"' if bold else ""
			if cell is int or cell is float:
				cells.append('<c r="%s"%s><v>%s</v></c>' % [ref, style, str(cell)])
			else:
				cells.append('<c r="%s"%s t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % [ref, style, _escape(str(cell))])
		rows.append('<row r="%d">%s</row>' % [r + 1, "".join(cells)])
	return XML_HEAD + '<worksheet xmlns="%s">%s<sheetData>%s</sheetData></worksheet>' % [
			MAIN_NS, "<cols>%s</cols>" % "".join(cols) if not cols.is_empty() else "", "".join(rows)]


## Excel column letters: A..Z, then AA, AB, ...
static func _column(i: int) -> String:
	var name := ""
	i += 1
	while i > 0:
		var m := (i - 1) % 26
		name = char(65 + m) + name
		i = (i - 1) / 26
	return name


## Sheet names may not hold []:*?/\, are at most 31 characters, and must differ.
static func _sheet_names(sheets: Array) -> PackedStringArray:
	var names := PackedStringArray()
	for sheet in sheets:
		var name: String = str(sheet.get("name", "Sheet"))
		for bad in ["[", "]", ":", "*", "?", "/", "\\"]:
			name = name.replace(bad, ".")
		name = name.left(31)
		var unique := name
		var n := 2
		while unique in names:
			var suffix := " (%d)" % n
			unique = name.left(31 - suffix.length()) + suffix
			n += 1
		names.append(unique)
	return names


static func _escape(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
