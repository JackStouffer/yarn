module yarn;

import std.traits;
import std.range.primitives;
import std.stdio;

/**
 * Custom `string` type optimized for both small sizes and for appending
 * large amounts of data.
 */
struct Yarn
{
    ///
    this(C)(const(C)[] chars)
    if (isSomeChar!C)
    {
        this ~= chars;
    }

    /**
     * Appends.
     *
     * Throws:
     *     UTFException on bad utf data.
     *     OutOfMemory when allocation fails.
     */
    ref opOpAssign(string op, Char)(Char ch)
    if (op == "~" && isSomeChar!(Char))
    {
        static if (is(Unqual!Char == char))
        {
            import core.checkedint : addu, mulu;
            import core.memory : GC;

            if (!isBig)
            {
                if (small.slen == smallCapacity)
                {
                    convertToBig();
                }
                else
                {
                    small.data[smallLength] = ch;
                    small.slen++;
                    return this;
                }
            }

            assert(isBig);
            if (large.len == large.capacity)
            {
                extend(1);
            }
            large.ptr[large.len++] = ch;
            return this;
        }
        else
        {
            import std.utf : encode;
            char[4] buf;
            size_t i = encode(buf, ch);
            return opOpAssign!("~")(buf[0 .. i]);
        }
    }

    /// ditto
    ref opOpAssign(string op, R)(R r)
    if (op == "~" && isInputRange!R && isSomeChar!(ElementType!R))
    {
        static if (hasLength!R || isNarrowString!R)
        {
            if (!isBig && r.length + small.slen > smallCapacity)
            {
                convertToBig();
            }
            else if (isBig)
            {
                reserve(r.length);
            }
        }
        else
        {
            if (isBig)
            {
                // Take an educated guess.
                // Could get the walk length if it's a forward range,
                // but that assumes popping is cheap
                extend(8);
            }
        }

        foreach (ch; r)
        {
            this ~= ch;
        }
        return this;
    }

    ///
    void put(R)(R r)
    if (isSomeChar!(R) || (isInputRange!(R) && isSomeChar!(ElementType!(R))))
    {
        this ~= r;
    }

    /**
    Allocate space for `newCapacity` elements.
     */
    void reserve(size_t newCapacity)
    {
        if (isBig && newCapacity > large.capacity)
            extend(newCapacity - large.len);
    }

    /**
    Returns: The data as a random access range of code units.
     */
    auto byCodeUnit()
    {
        import std.utf : byCodeUnit;

        if (isBig)
        {
            return large.ptr[0 .. large.len].byCodeUnit;
        }
        else
        {
            return small.data[0 .. smallLength].byCodeUnit;
        }
    }

    /**
    Returns: The data as a random access range of code units.
     */
    auto byChar()
    {
        return byCodeUnit;
    }

    /**
    Returns: The data as a forward range of `wchars`
     */
    auto byWchar()
    {
        import std.utf : byWchar;

        if (isBig)
        {
            return large.ptr[0 .. large.len].byWchar;
        }
        else
        {
            return small.data[0 .. smallLength].byWchar;
        }
    }

    /**
    Returns: The data as a bidirectional range of code points.
     */
    auto byDchar()
    {
        // custom because byUTF is bidirectional
        static struct Result(R)
        {
            R data;

            auto front() { return data.front; }
            void popFront() { data.popFront; }
            bool empty() { return data.empty; }
            auto back() { return data.back; }
            void popBack() { data.popBack; }
            auto save() { return Result!(R)(data.save); }
        }

        if (isBig)
        {
            return Result!(char[])(large.ptr[0 .. large.len]);
        }
        else
        {
            return Result!(char[])(small.data[0 .. smallLength]);
        }
    }

    private enum smallCapacity = 31;
    private enum small_flag = 0x80, small_mask = 0x7F;

    private void setBig() @safe @nogc nothrow pure
    {
        small.slen |= small_flag;
    }

    private size_t smallLength() @property const @nogc nothrow pure
    {
        return small.slen & small_mask;
    }

    private ubyte isBig() @property const @nogc nothrow pure
    {
        return small.slen & small_flag;
    }

    /*
    Allocates a new array on the GC and copies the small data to it.
     */
    private void convertToBig()
    {
        import core.memory : GC;

        immutable nbytes = (smallLength + 1) * char.sizeof;
        immutable size_t k = smallLength;
        char* p = cast(char*) GC.malloc(nbytes, blockAttribute!(char));

        for (int i = 0; i < k; i++)
        {
            p[i] = small.data[i];
        }

        large.ptr = p;
        large.len = k;
        large.capacity = smallLength + 1;
        setBig();
    }

    /*
    Allocates space for n extra elements. If capacity can hold n more
    elements does nothing.
     */
    private void extend(size_t n)
    {
        import core.checkedint : mulu;
        import core.memory : GC;
        import core.stdc.string : memcpy;

        assert(isBig);
        immutable len = large.len;
        immutable reqlen = len + n;

        if (large.capacity >= reqlen)
            return;

        immutable u = GC.extend(large.ptr, n * char.sizeof, (reqlen - len) * char.sizeof);
        if (u)
        {
            // extend worked, update the capacity
            large.capacity = u / char.sizeof;
            return;
        }

        // didn't work, must reallocate
        bool overflow;
        const nbytes = mulu(reqlen, char.sizeof, overflow);
        if (overflow) assert(0);

        auto bi = GC.qalloc(nbytes, blockAttribute!char);
        large.capacity = bi.size / char.sizeof;
        if (len)
            memcpy(bi.base, large.ptr, len * char.sizeof);
        large.ptr = cast(char*) bi.base;
        large.len = len;
    }

    version(LittleEndian)
    {
        private static struct Small
        {
            char[smallCapacity] data;
            ubyte slen;
        }

        private static struct Large
        {
            char* ptr;
            size_t capacity;
            size_t len;
            size_t padding;
        }

        private union
        {
            Large large;
            Small small;
        }
    }
    else
    {
        private static struct Small
        {
            ubyte slen;
            char[smallCapacity] data;
        }

        private static struct Large
        {
            size_t padding;
            size_t len;
            size_t capacity;
            char* ptr;
        }

        private union
        {
            Small small;
            Large large;
        }
    }
}

unittest
{
    import std.algorithm.comparison : equal;

    auto a = Yarn("test");
    assert(a.byCodeUnit.equal("test"));

    a ~= " test";
    assert(a.byCodeUnit.equal("test test"));

    a ~= " test test test test test";
    a ~= " test test test test test";
    a ~= " test test test test test";
    assert(a.byCodeUnit.equal("test test test test test test test test test test test test test test test test test"));

    // test construction with a string that triggers conversion to large
    auto b = Yarn("000000000000000000000000000000000000000000000000");
    assert(b.byCodeUnit.equal("000000000000000000000000000000000000000000000000"));
}

// test encoding on ctor and append
unittest
{
    import std.algorithm.comparison : equal;
    import std.range : retro;

    wstring w = "øōôòœõ";
    Yarn y1 = Yarn(w);
    assert(y1.byDchar.equal("øōôòœõ"));
    Yarn y2;
    y2 ~= w;
    assert(y2.byDchar.equal("øōôòœõ"));

    dstring d = "𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾";
    Yarn y3 = Yarn(d);
    assert(y3.byDchar.equal("𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾"));
    Yarn y4;
    y4 ~= d;
    assert(y4.byDchar.equal("𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾"));
    assert(y4.byDchar.retro.equal("𐐾𐐺𐐸𐐷𐐾𐐺𐐸𐐷𐐾𐐺𐐸𐐷𐐾𐐺𐐸𐐷"));
}

unittest
{
    import std.algorithm.comparison : equal;
    import std.string : assumeUTF;

    Yarn y1 = Yarn("𐐷𐐸𐐺𐐾");

    ubyte[] s1 = [0xF0, 0x90, 0x90, 0xB7, 0xF0, 0x90, 0x90, 0xB8,
                  0xF0, 0x90, 0x90, 0xBA, 0xF0, 0x90, 0x90, 0xBE];
    assert(y1.byChar.equal(s1.assumeUTF));

    ushort[] s2 = [0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E];
    assert(y1.byWchar.equal(s2.assumeUTF));

    uint[] s3 = [0x10437, 0x10438, 0x1043A, 0x1043E];
    assert(y1.byDchar.equal(s3.assumeUTF));
}

/*
Returns the proper allocation attribute for T
 */
private template blockAttribute(T)
{
    import core.memory;
    static if (hasIndirections!(T) || is(T == void))
    {
        enum blockAttribute = 0;
    }
    else
    {
        enum blockAttribute = GC.BlkAttr.NO_SCAN;
    }
}
