//
// Created by Codex on 17.11.2026.
//

#include "RuntimeValues.as"

class DialogueProgram
{
    String plain;
    JsonValue@ tokens;
    JsonValue@ spans;
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
        JsonValue@ token = RuntimeValues::Object();
        RuntimeValues::PutString(token, "kind", kind);
        token.Set("index", RuntimeValues::IntValue(index));
        RuntimeValues::PutNumber(token, "value", value);
        RuntimeValues::PutNumber(token, "cps", cps);
        tokens.Append(token);
    }

    void Compile(const String &in source, bool autoWait)
    {
        plain = "";
        diagnostic = "";
        noWait = false;
        @tokens = RuntimeValues::Array();
        @spans = RuntimeValues::Array();
        JsonValue@ stack = RuntimeValues::Array();
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
                    for (int j = int(stack.GetCount()) - 1; j >= 0; --j)
                    {
                        JsonValue@ span = stack.At(uint(j));
                        if (!span.Get("closed").GetBool() && span.Get("name").GetString() == closing)
                        {
                            span.Set("end", RuntimeValues::IntValue(visible));
                            span.Set("closed", RuntimeValues::BoolValue(true));
                            stack.SetAt(uint(j), span);
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
                    JsonValue@ span = RuntimeValues::Object();
                    RuntimeValues::PutString(span, "name", name);
                    RuntimeValues::PutString(span, "tag", tag);
                    span.Set("begin", RuntimeValues::IntValue(visible));
                    span.Set("end", RuntimeValues::IntValue(0));
                    span.Set("closed", RuntimeValues::BoolValue(false));
                    float currentSize = 33;
                    for (uint j = 0; j < stack.GetCount(); ++j)
                    {
                        JsonValue@ open = stack.At(j);
                        if (!open.Get("closed").GetBool() && open.Get("name").GetString() == "size")
                        {
                            String sizeTag = open.Get("tag").GetString();
                            currentSize += RuntimeValues::Number(sizeTag.substring(5, sizeTag.length() - 5));
                        }
                    }
                    float delta = name == "size" ? RuntimeValues::Number(tag.substring(5, tag.length() - 5)) : 0;
                    RuntimeValues::PutNumber(span, "relativeSize", currentSize > 0 ? (currentSize + delta) / currentSize : 1);
                    stack.Append(span);
                }
                cps = 1;
                for (uint j = 0; j < stack.GetCount(); ++j)
                {
                    JsonValue@ span = stack.At(j);
                    if (span.Get("name").GetString() == "cps" && !span.Get("closed").GetBool())
                    {
                        String value = span.Get("tag").GetString();
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
        for (uint j = 0; j < stack.GetCount(); ++j)
        {
            JsonValue@ span = stack.At(j);
            if (!span.Get("closed").GetBool())
            {
                span.Set("end", RuntimeValues::IntValue(visible));
            }
            spans.Append(span);
        }
    }

    void Paint(TextMesh@ target)
    {
        target.SetText(plain);
        for (uint i = 0; i < spans.GetCount(); ++i)
        {
            JsonValue@ span = spans.At(i);
            String name = span.Get("name").GetString();
            String tag = span.Get("tag").GetString();
            TextStyle style;
            style.begin = uint(span.Get("begin").GetInt());
            style.end = uint(span.Get("end").GetInt());
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
                style.relativeSize = float(span.Get("relativeSize").GetNumber());
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
