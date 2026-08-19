#!/usr/bin/env python3
"""Assemble proctor-surfaces.html from its parts and the compiled TUI frames.

The frames are read from the JSON the tui-design compiler produced, never
re-drawn: each row is run-length encoded into spans carrying the exact fg, bg
and bold the compiler resolved, so what the page shows is what the compiler
measured.
"""
import html
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
TUI = os.path.join(HERE, "tui")
OUT = os.path.join(HERE, "proctor-surfaces.html")

SCREENS = [
    ("run", "Run pane", "The pane a supervisor watches. Six states, because a "
     "supervision surface that only holds the ideal one is a surface that lies "
     "at exactly the moment somebody looks at it.",
     [("run-empty", "Empty · nothing running"),
      ("run-loading", "Loading · connecting"),
      ("run-ideal", "Ideal · acting"),
      ("run-partial", "Partial · paused by a person"),
      ("run-error", "Error · agent unreachable"),
      ("run-done", "Done · finished")]),
    ("queue", "Queue pane", "Three lanes, and the model stated above them. Reads "
     "never join the line, process-directed actuation contends per app, and "
     "synthetic events contend globally.",
     [("queue-ideal", "Ideal · contended")]),
    ("readiness", "Readiness pane", "Grants and the five lanes, each derived from "
     "the grants and the located tools rather than reported separately.",
     [("readiness-ideal", "Ideal · one lane out")]),
    ("history", "History pane", "The folded run projection. Selection is reverse "
     "video rather than a coloured fill, so it survives NO_COLOR, a pipe, and an "
     "unhelpful terminal theme.",
     [("history-ideal", "Ideal · six runs"),
      ("history-empty", "Empty · nothing recorded")]),
    ("switches", "Switches pane", "Eight switches with their live value, where "
     "each value came from, and when a change reaches the agent. Read-only here.",
     [("switches-ideal", "Ideal · eight switches")]),
]
SIZES = ["100x30", "80x24"]


def render_frame(path):
    """Run-length encode a compiled frame into spans."""
    frame = json.load(open(path))
    out = []
    for row in frame["cells"]:
        runs, cur, buf = [], None, []
        for cell in row:
            key = (cell.get("fg"), cell.get("bg"), bool(cell.get("bold")),
                   bool(cell.get("reverse")), bool(cell.get("dim")))
            if key != cur:
                if buf:
                    runs.append((cur, "".join(buf)))
                cur, buf = key, []
            buf.append(cell.get("ch", " "))
        if buf:
            runs.append((cur, "".join(buf)))
        parts = []
        for (fg, bg, bold, reverse, dim), text in runs:
            esc = html.escape(text)
            if reverse:
                fg, bg = bg or "#14161B", fg or "#E9EAED"
            style = []
            if fg:
                style.append("color:%s" % fg)
            if bg and bg != frame["roles"].get("surface", {}).get("bg"):
                style.append("background:%s" % bg)
            if dim:
                style.append("opacity:.72")
            tag = "b" if bold else "span"
            if style:
                parts.append('<%s style="%s">%s</%s>' % (tag, ";".join(style), esc, tag))
            elif bold:
                parts.append("<b>%s</b>" % esc)
            else:
                parts.append(esc)
        out.append('<span class="ln">%s</span>' % "".join(parts))
    return "\n".join(out), frame["cols"], frame["rows"]


def tui_section():
    blocks = []
    for key, label, note, states in SCREENS:
        subs = []
        for stem, state_label in states:
            frames = []
            for size in SIZES:
                body, cols, rows = render_frame(os.path.join(TUI, "%s-%s.json" % (stem, size)))
                frames.append(
                    '<div class="term-frame" data-size="{size}">'
                    '<div class="term-wrap"><div class="term-bar">'
                    '<div class="lights"><i class="light r"></i><i class="light y"></i>'
                    '<i class="light g"></i></div>'
                    '<div class="title">proctor tui &middot; {size}</div></div>'
                    '<div class="term">{body}</div></div>'
                    '<div class="term-meta">'
                    '<span>compiled frame &middot; <code>{stem}-{size}.json</code></span>'
                    '<span>{cols}&times;{rows} cells</span>'
                    '<span>both gate suites clean</span>'
                    '</div></div>'.format(size=size, body=body, stem=stem, cols=cols, rows=rows))
            subs.append(
                '<div class="sub" data-state="{stem}" data-state-label="{lab}">'
                '<div class="canvas plain">{frames}</div></div>'.format(
                    stem=stem, lab=html.escape(state_label), frames="".join(frames)))
        blocks.append(
            '<section class="pane" data-platform="tui" data-surface="{key}" '
            'data-label="{label}" data-title="TUI &middot; {label}" data-note="{note}">'
            '{subs}</section>'.format(key=key, label=html.escape(label),
                                      note=html.escape(note), subs="".join(subs)))
    return "\n".join(blocks)


PARTS = os.path.join(HERE, "parts")


def part(name):
    return open(os.path.join(PARTS, name)).read()


def main():
    """Deterministic: parts in, one file out. Re-running rebuilds rather than
    appending, so the parts stay the source and the page stays the output."""
    css_tail = """
/* TUI size switching */
.term-frame { display: none; width: max-content; max-width: 100%; }
body[data-tui-size="100x30"] .term-frame[data-size="100x30"],
body[data-tui-size="80x24"]  .term-frame[data-size="80x24"] { display: block; }
#tui-size { display: none; }
body[data-platform="tui"] #tui-size { display: inline-flex; }
"""
    body = "\n".join([part("body-head.html"), part("mac-1.html"),
                      part("mac-2.html"), part("mac-3.html")])
    body += "\n" + tui_section() + "\n"
    body += part("cli.html") + part("cover.html") + part("js.html")

    doc = (part("head.html").rstrip() + "\n" + part("style-2.css") + css_tail
           + "</style>\n</head>\n<body>\n" + body + "\n</body>\n</html>\n")
    open(OUT, "w").write(doc)
    print("wrote %s  (%.0f KB)" % (OUT, len(doc) / 1024))


if __name__ == "__main__":
    main()
