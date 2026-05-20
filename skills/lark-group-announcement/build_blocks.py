"""Build docx-block JSON for Lark group announcements.

Usage:
    from build_blocks import heading2, heading3, para, bullet, ordered, text_run, payload
    children = [
        heading2("讨论主题"),
        para([text_run("一句话定义...")]),
        bullet([text_run("PRD：", bold=True), text_run("方案文档", link="https://...")]),
    ]
    print(payload(children))  # JSON string ready for `lark-cli api POST ... --data ...`

The URL inside `link` is percent-encoded automatically — pass plain URLs.
"""
import json
import urllib.parse


def text_run(content, link=None, bold=False, italic=False, underline=False, inline_code=False):
    style = {}
    if link:
        style["link"] = {"url": urllib.parse.quote(link, safe="")}
    if bold: style["bold"] = True
    if italic: style["italic"] = True
    if underline: style["underline"] = True
    if inline_code: style["inline_code"] = True
    el = {"text_run": {"content": content}}
    if style:
        el["text_run"]["text_element_style"] = style
    return el


def _block(block_type, type_name, elements):
    return {"block_type": block_type, type_name: {"elements": elements, "style": {}}}


def heading2(text):  return _block(4, "heading2", [text_run(text)])
def heading3(text):  return _block(5, "heading3", [text_run(text)])
def para(elements):  return _block(2, "text", elements)
def bullet(elements): return _block(12, "bullet", elements)
def ordered(elements): return _block(13, "ordered", elements)


def payload(children, index=-1):
    """Return a JSON string ready to pass as --data to the children POST endpoint."""
    return json.dumps({"children": children, "index": index}, ensure_ascii=False)


if __name__ == "__main__":
    # quick smoke test
    children = [
        heading2("Hello"),
        para([text_run("link: "), text_run("here", link="https://example.com/?q=测试", bold=True)]),
        bullet([text_run("a"), text_run(" b", italic=True)]),
    ]
    print(payload(children))
