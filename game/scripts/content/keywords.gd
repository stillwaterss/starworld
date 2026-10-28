extends RefCounted
## Clue words in what people say (the lamps, the lighthouse, letters, constellations,
## places): mark() wraps them in BBCode so a RichTextLabel shows them bold and coloured.
## Longest first, so "飞艇的心" wins over "飞艇".
const WORDS := [
	"一盏，两盏，三盏", "一盏一盏", "飞艇的心", "蓝色信箱", "一闪三下", "灯塔岛", "归家座", "花铃座", "星舟座", "水漂座", "灯塔座",
	"萤火座", "门扉座", "风铃座", "信封座", "东北小岛", "西北小岛", "东边小岛", "南边小岛",
	"夜光花", "小夜灯", "望远镜", "星光", "灯芯", "灯塔", "飞艇", "星图", "信箱", "风铃", "天灯",
	"炉火", "树屋", "窗台", "四十年",
]

static func mark(text: String, color := "#ffcf6e") -> String:
	var safe := text.replace("[", "[lb]")
	var out := ""
	var i := 0
	while i < safe.length():
		var hit := ""
		for word in WORDS:
			if safe.substr(i, word.length()) == word:
				hit = word
				break
		if hit == "":
			out += safe[i]
			i += 1
		else:
			out += "[color=%s][b]%s[/b][/color]" % [color, hit]
			i += hit.length()
	return out
