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
        import core.memory : pureRealloc;

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
            bool overflow;
            large.capacity = addu(large.capacity, grow, overflow);
            auto nelems = mulu(3, addu(large.capacity, 1, overflow), overflow);

            if (overflow)
            {
                assert(0);
            }

            large.ptr = cast(char*) pureRealloc(large.ptr, nelems);

            if (large.ptr is null)
            {
                onOutOfMemoryError();
            }
        }
        large.ptr[large.len++] = ch;
        return this;
    }

    ///
    ref opOpAssign(string op, Input)(Input inp)
    if (op == "~" && isInputRange!Input && isSomeChar!(ElementType!Input))
    {
        foreach (ch; inp)
        {
            this ~= ch;
        }
        return this;
    }

    bool opEquals(string rhs)
    {
        if (isBig)
        {
            return large.ptr[0 .. large.len] == rhs;
        }

        return small.data[0 .. small.slen] == rhs;
    }

    size_t length() @property
    {
        return isBig ? large.len : small.slen & 0x7F;
    }

    version(X86_64)
        enum smallCapacity = 31;
    else
        enum smallCapacity = 15;

    enum small_flag = 0x80, small_mask = 0x7F;
    enum grow = 40;

    void setBig() @nogc nothrow pure
    {
        small.slen |= small_flag;
    }

    @property size_t smallLength() const @nogc nothrow pure
    {
        return small.slen & small_mask;
    }

    @property ubyte isBig() const @nogc nothrow pure
    {
        return small.slen & small_flag;
    }

    void convertToBig()
    {
        import core.exception : onOutOfMemoryError;
        import core.memory : pureMalloc;

        static assert(grow.max / 3 - 1 >= grow);

        enum nbytes = 3 * (grow + 1);
        immutable size_t k = smallLength;
        char* p = cast(char*) pureMalloc(nbytes);

        if (p is null)
            onOutOfMemoryError();

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

    static struct Large
    {
        char* ptr;
        size_t capacity;
        size_t len;
        size_t padding_;
    }

    static struct Small
    {
        ubyte slen;
        char[smallCapacity] data;
    }

    union
    {
        Large large;
        Small small;
    }

    string toString()
    {
        import std.exception : assumeUnique;
        if (isBig)
        {
            return large.ptr[0 .. large.len].assumeUnique;
        }
        return small.data[0 .. small.slen].assumeUnique;
    }
}

unittest
{
    auto a = Yarn("test");
    assert(a == "test");

    a ~= " test";
    assert(a == "test test");

    a ~= " test test test test test";
    assert(a == "test test test test test test test");
}