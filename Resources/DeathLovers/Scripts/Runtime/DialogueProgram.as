//
// Created by Codex on 17.11.2026.
//

#include "RuntimeValues.as"
#include "NovelState.as"

class DialogueProgram
{
    String plain;
    Vector<DialogueToken> tokens;
    Vector<DialogueSpan> spans;
    uint tokenCount = 0;
    uint spanCount = 0;
    String diagnostic;
    bool noWait = false;

    bool Punctuation(uint ch)
    {
        return ch == 46 || ch == 44 || ch == 59 || ch == 58 || ch == 33 || ch == 63;
    }

    String AutoWaits(const String &in source)
    {
        String text;
        for (uint i = 0; i < source.length(); ++i)
        {
            if (i + 3 <= source.length() && source.substring(i, 3) == "…")
            {
                text = text + "...";
                i += 2;
            }
            else
            {
                text = text + source.substring(i, 1);
            }
        }
        String result;
        bool inside = false;
        for (uint i = 0; i < text.length(); ++i)
        {
            uint ch = text.byteAt(i);
            if (ch == 123)
            {
                inside = true;
            }
            if (ch == 125)
            {
                inside = false;
            }
            result = result + text.substring(i, 1);
            if (inside || !Punctuation(ch))
            {
                continue;
            }
            if (ch == 46 && i > 0 && i + 1 < text.length() && RuntimeValues::Digit(text.byteAt(i - 1)) && RuntimeValues::Digit(text.byteAt(i + 1)))
            {
                continue;
            }
            uint j = i + 1;
            bool hasWait = false;
            while (j < text.length())
            {
                if (RuntimeValues::Space(text.byteAt(j)))
                {
                    ++j;
                    continue;
                }
                if (text.byteAt(j) == 123)
                {
                    uint close = RuntimeValues::Find(text, 125, j);
                    if (close == text.length())
                    {
                        break;
                    }
                    String tag = RuntimeValues::Trim(text.substring(j + 1, close - j - 1));
                    if (tag == "w" || RuntimeValues::Starts(tag, "w="))
                    {
                        hasWait = true;
                        break;
                    }
                    j = close + 1;
                    continue;
                }
                break;
            }
            bool group = (i > 0 && Punctuation(text.byteAt(i - 1))) || (i + 1 < text.length() && Punctuation(text.byteAt(i + 1)));
            if (!hasWait && (group || j < text.length()))
            {
                result = result + "{w=0.25}";
            }
        }
        return result;
    }

    float Parameter(const String &in tag, const String &in key, float fallback)
    {
        for (uint i = 0; i + key.length() <= tag.length(); ++i)
        {
            if (tag.substring(i, key.length()) == key)
            {
                uint begin = i + key.length();
                uint end = RuntimeValues::Find(tag, 58, begin);
                return RuntimeValues::Number(tag.substring(begin, end - begin));
            }
        }
        return fallback;
    }

    void Token(const String &in kind, uint index, float value, float cps)
    {
        if (tokenCount >= tokens.size())
        {
            tokens.resize(tokenCount + 1);
        }
        DialogueToken@ token = tokens[tokenCount++];
        token.kind = kind;
        token.index = index;
        token.value = value;
        token.cps = cps;
    }

    void Compile(const String &in source, bool autoWait)
    {
        plain = "";
        diagnostic = "";
        noWait = false;
        tokenCount = 0;
        spanCount = 0;
        tokens.reserve(source.length());
        spans.reserve(16);
        String text = autoWait ? AutoWaits(source) : source;
        uint visible = 0;
        float cps = 1;
        for (uint i = 0; i < text.length();)
        {
            if (text.byteAt(i) == 123)
            {
                uint close = RuntimeValues::Find(text, 125, i);
                if (close == text.length())
                {
                    diagnostic = "Unclosed text tag";
                    return;
                }
                String tag = text.substring(i + 1, close - i - 1);
                uint equal = RuntimeValues::Find(tag, 61, 0);
                String name = tag.substring(0, equal);
                if (tag == "w")
                {
                    Token("input", visible, 0, cps);
                }
                else if (RuntimeValues::Starts(tag, "w="))
                {
                    Token("pause", visible, RuntimeValues::Number(tag.substring(2, tag.length() - 2)), cps);
                }
                else if (tag == "nw")
                {
                    noWait = true;
                }
                else if (RuntimeValues::Starts(tag, "/"))
                {
                    String closing = tag.substring(1, tag.length() - 1);
                    bool found = false;
                    for (int j = int(spanCount) - 1; j >= 0; --j)
                    {
                        DialogueSpan@ span = spans[uint(j)];
                        if (!span.closed && span.name == closing)
                        {
                            span.end = visible;
                            span.closed = true;

                            found = true;
                            break;
                        }
                    }
                    if (!found)
                    {
                        diagnostic = diagnostic + " Ignored extra closing tag: " + tag;
                    }
                }
                else
                {
                    if (name != "b" && name != "i" && name != "u" && name != "s" && name != "size" && name != "alpha" && name != "cps" && name != "shader")
                    {
                        diagnostic = diagnostic + " Unsupported tag: " + tag;
                    }
                    if (spanCount >= spans.size())
                    {
                        spans.resize(spanCount + 1);
                    }
                    DialogueSpan@ span = spans[spanCount];
                    span.name = name;
                    span.tag = tag;
                    span.begin = visible;
                    span.end = 0;
                    span.closed = false;
                    float currentSize = 33;
                    for (uint j = 0; j < spanCount; ++j)
                    {
                        DialogueSpan@ open = spans[j];
                        if (!open.closed && open.name == "size")
                        {
                            String sizeTag = open.tag;
                            currentSize += RuntimeValues::Number(sizeTag.substring(5, sizeTag.length() - 5));
                        }
                    }
                    float delta = name == "size" ? RuntimeValues::Number(tag.substring(5, tag.length() - 5)) : 0;
                    span.relativeSize = currentSize > 0 ? (currentSize + delta) / currentSize : 1;
                    ++spanCount;
                }
                cps = 1;
                for (uint j = 0; j < spanCount; ++j)
                {
                    DialogueSpan@ span = spans[j];
                    if (span.name == "cps" && !span.closed)
                    {
                        String value = span.tag;
                        if (RuntimeValues::Starts(value, "cps=*"))
                        {
                            cps *= RuntimeValues::Number(value.substring(5, value.length() - 5));
                        }
                    }
                }
                i = close + 1;
                continue;
            }
            uint bytes = text.byteAt(i) < 128 ? 1 : text.byteAt(i) < 224 ? 2 : text.byteAt(i) < 240 ? 3 : 4;
            plain = plain + text.substring(i, bytes);
            uint count = plain.graphemeCount();
            if (count > visible)
            {
                visible = count;
                Token(RuntimeValues::Space(text.byteAt(i)) ? "space" : "glyph", visible, 0, cps);
            }
            i += bytes;
        }
        for (uint j = 0; j < spanCount; ++j)
        {
            DialogueSpan@ span = spans[j];
            if (!span.closed)
            {
                span.end = visible;
            }
        }
    }

    void Paint(TextMesh@ target)
    {
        target.SetText(plain);
        for (uint i = 0; i < spanCount; ++i)
        {
            DialogueSpan@ span = spans[i];
            String name = span.name;
            String tag = span.tag;
            TextStyle style;
            style.begin = uint(span.begin);
            style.end = uint(span.end);
            if (style.begin >= style.end || name == "cps")
            {
                continue;
            }
            style.bold = name == "b";
            style.italic = name == "i";
            style.underline = name == "u";
            style.strike = name == "s";
            if (name == "size")
            {
                style.relativeSize = float(span.relativeSize);
            }
            if (RuntimeValues::Starts(tag, "alpha=*"))
            {
                style.color.w = RuntimeValues::Number(tag.substring(7, tag.length() - 7));
            }
            if (RuntimeValues::Starts(tag, "shader=wave"))
            {
                style.customData0.x = Parameter(tag, "u__amplitude=", 5);
                style.customData0.y = Parameter(tag, "u__frequency=", 2);
                style.customData0.z = Parameter(tag, "u__wavelength=", 20);
            }
            if (RuntimeValues::Starts(tag, "shader=shake"))
            {
                style.customData1.x = Parameter(tag, "u__amplitude=", 1.5f);
                style.customData1.y = Parameter(tag, "u__speed=", 50);
            }
            target.AddStyle(style);
        }
    }
}
