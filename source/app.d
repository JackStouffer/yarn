module yarn;

import std.traits;
import std.range.primitives;
import std.stdio;

/**
 * Small size optimized string.
 */
struct Yarn
{
    ///
    this(C)(const(C)[] chars)
    if (isSomeChar!C)
    {
        this ~= chars;
    }

    ///
    ref opOpAssign(string op)(char ch)
    if (op == "~")
    {
        import core.exception : onOutOfMemoryError;
        import core.memory : GC;

        if (!isBig)
        {
            if (small.slen == smallCapacity)
            {
                convertToBig();
            }
            else
            {
                small.data[small.slen] = ch;
                small.slen++;
                return this;
            }
        }

        assert(isBig);
        if (large.len == large.capacity)
        {
            import core.checkedint : addu, mulu;
            import core.stdc.string : memcpy;
            bool overflow;
            large.capacity = addu(large.capacity, grow, overflow);
            auto nelems = mulu(large.capacity, char.sizeof, overflow);
            if (overflow)
            {
                assert(0);
            }

            large.ptr = cast(char*) GC.realloc(large.ptr, nelems, blockAttribute!(char));
        }
        large.ptr[large.len++] = ch;
        return this;
    }

    ///
    ref opOpAssign(string op, R)(R r)
    if (op == "~" && isInputRange!R && isSomeChar!(ElementType!R))
    {
        static if (hasLength!R || isNarrowString!R)
        {
            if (!isBig && r.length + small.slen > smallCapacity)
            {
                convertToBig();
            }
        }

        foreach (ch; r)
        {
            this ~= ch;
        }
        return this;
    }

    ///
    bool opEquals(string rhs)
    {
        if (isBig)
        {
            return large.ptr[0 .. large.len] == rhs;
        }

        return small.data[0 .. small.slen] == rhs;
    }

    ///
    string toString()
    {
        import std.exception : assumeUnique;
        if (isBig)
        {
            return large.ptr[0 .. large.len].assumeUnique;
        }
        return small.data[0 .. small.slen].assumeUnique;
    }

    private enum smallCapacity = 31;
    private enum small_flag = 0x80, small_mask = 0x7F;
    private enum grow = 40;

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

    private void convertToBig()
    {
        import core.memory : GC;

        static assert(grow.max / 3 - 1 >= grow);

        enum nbytes = 3 * (grow + 1);
        immutable size_t k = smallLength;
        char* p = cast(char*) GC.malloc(nbytes, blockAttribute!(char));

        for (int i = 0; i < k; i++)
        {
            p[i] = small.data[i];
        }

        // now we can overwrite small array data
        large.ptr = p;
        large.len = k;
        assert(grow > large.len);
        large.capacity = grow;
        setBig();
    }

    private static struct Large
    {
        char* ptr;
        size_t capacity;
        size_t len;
        size_t padding;
    }

    version(LittleEndian)
    {
        private static struct Small
        {
            char[smallCapacity] data;
            ubyte slen;
        }
    }
    else
    {
        private static struct Small
        {
            ubyte slen;
            char[smallCapacity] data;
        }
    }

    private union
    {
        Large large;
        Small small;
    }
}

unittest
{
    auto a = Yarn("test");
    assert(a == "test");

    a ~= " test";
    assert(a == "test test");

    a ~= " test test test test test";
    a ~= " test test test test test";
    a ~= " test test test test test";
    assert(a == "test test test test test test test test test test test test test test test test test");

    // test construction with a string that triggers conversion to large
    auto b = Yarn("000000000000000000000000000000000000000000000000");
    assert(b == "000000000000000000000000000000000000000000000000");
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
