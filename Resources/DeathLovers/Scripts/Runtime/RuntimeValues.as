//
// Created by Codex on 17.11.2026.
//

namespace RuntimeValues
{
    JsonValue@ StringValue(const String &in value)
    {
        JsonValue result;
        result.SetString(value);
        return result.Clone();
    }

    JsonValue@ NumberValue(double value)
    {
        JsonValue result;
        result.SetNumber(value);
        return result.Clone();
    }

    JsonValue@ IntValue(int64 value)
    {
        JsonValue result;
        result.SetInt(value);
        return result.Clone();
    }

    JsonValue@ BoolValue(bool value)
    {
        JsonValue result;
        result.SetBool(value);
        return result.Clone();
    }

    JsonValue@ Object()
    {
        JsonValue result;
        result.MakeObject();
        return result.Clone();
    }

    JsonValue@ Array()
    {
        JsonValue result;
        result.MakeArray();
        return result.Clone();
    }

    void PutString(JsonValue@ target, const String &in key, const String &in value)
    {
        target.Set(key, StringValue(value));
    }

    void PutNumber(JsonValue@ target, const String &in key, double value)
    {
        target.Set(key, NumberValue(value));
    }

    bool Space(uint ch)
    {
        return ch == 32 || ch == 9 || ch == 10 || ch == 13;
    }

    bool Digit(uint ch)
    {
        return ch >= 48 && ch <= 57;
    }

    String Trim(const String &in text)
    {
        uint first = 0;
        uint last = text.length();
        while (first < last && Space(text.byteAt(first)))
        {
            ++first;
        }
        while (last > first && Space(text.byteAt(last - 1)))
        {
            --last;
        }
        return text.substring(first, last - first);
    }

    bool Starts(const String &in text, const String &in prefix)
    {
        return text.length() >= prefix.length() && text.substring(0, prefix.length()) == prefix;
    }

    uint Find(const String &in text, uint ch, uint begin)
    {
        for (uint i = begin; i < text.length(); ++i)
        {
            if (text.byteAt(i) == ch)
            {
                return i;
            }
        }
        return text.length();
    }

    float Number(const String &in text)
    {
        String value = text;
        if (Starts(value, "+"))
        {
            value = value.substring(1, value.length() - 1);
        }
        JsonValue parsed;
        if (!parsed.Parse(value))
        {
            return 0;
        }
        return float(parsed.GetNumber());
    }

    JsonValue@ Tail(JsonValue@ list, uint first)
    {
        JsonValue@ result = Array();
        for (uint i = first; i < list.GetCount(); ++i)
        {
            result.Append(list.At(i));
        }
        return result;
    }

    String Index(uint value)
    {
        return IntValue(value).ToJson();
    }

    String Text(JsonValue@ value, const String &in key)
    {
        return value.Has(key) && value.Get(key).GetKind() == JsonValueKind::String ? value.Get(key).GetString() : "";
    }
}
