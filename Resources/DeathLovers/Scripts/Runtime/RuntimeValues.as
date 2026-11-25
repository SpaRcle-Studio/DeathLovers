//
// Created by Codex on 17.11.2026.
//

namespace RuntimeValues
{
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
        uint i = 0;
        bool negative = false;
        if (i < text.length() && (text.byteAt(i) == 43 || text.byteAt(i) == 45))
        {
            negative = text.byteAt(i++) == 45;
        }
        double value = 0;
        uint digits = 0;
        while (i < text.length() && Digit(text.byteAt(i)))
        {
            value = value * 10 + text.byteAt(i++) - 48;
            ++digits;
        }
        if (i < text.length() && text.byteAt(i) == 46)
        {
            ++i;
            double factor = 0.1;
            while (i < text.length() && Digit(text.byteAt(i)))
            {
                value += (text.byteAt(i++) - 48) * factor;
                factor *= 0.1;
                ++digits;
            }
        }
        if (digits == 0)
        {
            return 0;
        }
        if (i < text.length() && (text.byteAt(i) == 101 || text.byteAt(i) == 69))
        {
            ++i;
            bool inverse = false;
            if (i < text.length() && (text.byteAt(i) == 43 || text.byteAt(i) == 45))
            {
                inverse = text.byteAt(i++) == 45;
            }
            uint exponent = 0;
            uint begin = i;
            while (i < text.length() && Digit(text.byteAt(i)))
            {
                exponent = exponent * 10 + text.byteAt(i++) - 48;
                if (exponent > 308)
                {
                    return 0;
                }
            }
            if (begin == i)
            {
                return 0;
            }
            for (uint power = 0; power < exponent; ++power)
            {
                value *= inverse ? 0.1 : 10.0;
            }
        }
        return i == text.length() ? float(negative ? -value : value) : 0;
    }

    String Index(uint value)
    {
        if (value == 0)
        {
            return "0";
        }
        String result;
        while (value > 0)
        {
            result = "0123456789".substring(value % 10, 1) + result;
            value /= 10;
        }
        return result;
    }

    String Text(JsonValueView@ value, const String &in key)
    {
        return value.Has(key) && value.Get(key).GetKind() == JsonValueKind::String ? value.Get(key).GetString() : "";
    }

    Value@ FromJson(JsonValueView@ source)
    {
        Value result;
        if (source.GetKind() == JsonValueKind::String)
        {
            String text = source.GetString();
            result.set(text);
        }
        else if (source.GetKind() == JsonValueKind::Integer)
        {
            int64 integer = source.GetInt();
            result.set(integer);
        }
        else if (source.GetKind() == JsonValueKind::Boolean)
        {
            bool boolean = source.GetBool();
            result.set(boolean);
        }
        else if (source.GetKind() == JsonValueKind::Number)
        {
            double number = source.GetNumber();
            result.set(number);
        }
        return result;
    }

    bool SameType(Value@ left, Value@ right)
    {
        bool boolean;
        int64 integer;
        double number;
        String text;
        return (left.get(boolean) && right.get(boolean)) ||
            (left.get(integer) && right.get(integer)) || (left.get(number) && right.get(number)) ||
            (left.get(text) && right.get(text));
    }

    bool Equal(Value@ left, Value@ right)
    {
        bool aBool, bBool;
        int64 aInt, bInt;
        double aNumber, bNumber;
        String aText, bText;
        if (left.get(aBool) && right.get(bBool))
        {
            return aBool == bBool;
        }
        if (left.get(aInt) && right.get(bInt))
        {
            return aInt == bInt;
        }
        if (left.get(aNumber) && right.get(bNumber))
        {
            double difference = aNumber - bNumber;
            return difference > -0.000001 && difference < 0.000001;
        }
        return left.get(aText) && right.get(bText) && aText == bText;
    }
}
