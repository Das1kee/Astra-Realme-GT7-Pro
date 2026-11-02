import html.parser
import re
import sys

P = r"D:\DSH\Astra\src\webroot"

css = open(P + r"\app.css", encoding="utf-8").read()
print("css braces: %d %d %s" % (css.count("{"), css.count("}"),
                                "balanced" if css.count("{") == css.count("}") else "UNBALANCED"))

h = open(P + r"\index.html", encoding="utf-8").read()
js = open(P + r"\app.js", encoding="utf-8").read()


class Checker(html.parser.HTMLParser):
    VOID = {"meta", "link", "br", "img", "input", "path", "circle", "rect", "line", "use"}

    def __init__(self):
        super().__init__()
        self.stack = []
        self.err = []

    def handle_starttag(self, tag, attrs):
        if tag in self.VOID:
            return
        self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag in self.VOID:
            return
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()
        elif tag in self.stack:
            while self.stack and self.stack.pop() != tag:
                pass
        else:
            self.err.append("stray </%s>" % tag)


c = Checker()
c.feed(h)
print("html unclosed:", c.stack[:10], "stray:", c.err[:5])

ids_html = set(re.findall(r'id="([^"]+)"', h))
ids_js = set(re.findall(r'\$\("#([A-Za-z0-9_-]+)"\)', js))
print("js ids missing in html:", sorted(ids_js - ids_html))

data_keys = set(re.findall(r'data-k="([A-Z_]+)"', h))
print("switch keys:", sorted(data_keys))
