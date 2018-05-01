module yarn;

import std.traits;
import std.range.primitives;
version(unittest) import std.stdio;

/**
A safe `string` type optimized for both small sizes and for appending
large amounts of data.

Specifically designed to not be compatible with built-in `string` types.
In order to iterate over the data contained in a `Yarn`, the iteration
method must be chosen first. This is in contrast with `string` which defaults
to iteration by code point (a.k.a auto-decoding). `Yarn` offers the
standard `std.utf` and `std.uni` range generating functions: `byCodeUnit`,
`byCodePoint`, `byChar`, `byWchar`, `byDchar`, and `byGrapheme`. Any iteration
of a `Yarn` must therefore explicitly choose the method of iteration at every
usage. There is no way to get at the underlying data other than these methods.

`Yarn` is an `OutputRange` for all `char` types.
 */
struct Yarn
{
    /**
    Params:
        r = A finite input range of any character type.
     */
    this(R)(R r)
    if (isInputRange!R && !isInfinite!R && isSomeChar!(ElementType!R))
    {
        this ~= r;
    }

    /**
    Appends the given character or input range to this `Yarn`'s data.

    Throws:
        `UTFException` on bad utf data. `OutOfMemory` when allocation fails.
     */
    ref opOpAssign(string op, Char)(Char ch) @trusted pure
    if (op == "~" && isSomeChar!(Char))
    {
        static if (is(Unqual!Char == char))
        {
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
            immutable size_t i = encode(buf, ch);
            foreach (j; 0 .. i)
            {
                this ~= buf[j];
            }
            return this;
        }
    }

    /// ditto
    ref opOpAssign(string op, S)(S s) @trusted pure
    if (op == "~" && isNarrowString!S)
    {
        if (!isBig && s.length + smallLength > smallCapacity)
        {
            convertToBig(s.length + smallLength);
        }
        else if (isBig)
        {
            extend(s.length);
        }

        alias E = Unqual!(ElementEncodingType!S);
        static if (isNarrowString!S && is(E == char))
        {
            if (isBig)
            {
                large.ptr[large.len .. large.len + s.length] = s;
                large.len += s.length;
            }
            else
            {
                small.data[smallLength .. smallLength + s.length] = s;
                small.slen += s.length;
            }

            return this;
        }
        else
        {
            foreach (E ch; s)
            {
                this ~= ch;
            }
            return this;
        }
    }

    /// ditto
    ref opOpAssign(string op, R)(R r)
    if (op == "~" && !isNarrowString!R && isInputRange!R && !isInfinite!R && isSomeChar!(ElementType!R))
    {
        static if (hasLength!R)
        {
            if (!isBig && r.length + smallLength > smallCapacity)
            {
                convertToBig(r.length + smallLength);
            }
            else if (isBig)
            {
                extend(r.length);
            }
        }
        else
        {
            if (isBig && large.capacity - large.len < 8)
            {
                // Take an educated guess.
                // Could get the walk length if it's a forward range,
                // but that assumes popping is cheap
                extend(8);
            }
        }

        for (; !r.empty; r.popFront)
        {
            this ~= r.front;
        }
        return this;
    }

    /**
    Performs the same action as `~=`.
     */
    void put(R)(R r)
    if (isSomeChar!(R) || (isInputRange!(R) && isSomeChar!(ElementType!(R))))
    {
        this ~= r;
    }

    /**
    Allocate space for `newCapacity` elements.

    Params:
        newCapacity = total amount of elements that this Yarn
        should have space for.
     */
    void reserve(size_t newCapacity) @trusted pure nothrow
    {
        if (isBig && newCapacity > large.capacity)
        {
            extend(newCapacity - large.len);
        }
        else if (!isBig && newCapacity > smallCapacity)
        {
            convertToBig(newCapacity);
        }
    }

    /**
    Returns: The data as a random access range of code units.
     */
    auto byCodeUnit() @trusted @nogc pure nothrow
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
    auto byChar() @trusted @nogc pure nothrow
    {
        return byCodeUnit;
    }

    /**
    Returns: The data as a forward range of `wchars`
     */
    auto byWchar() @trusted @nogc pure nothrow
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
    auto byDchar() @trusted pure
    {
        // custom because byUTF is not bidirectional
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

    /**
    Returns: The data as a forward range of Graphemes.
     */
    auto byGrapheme() @trusted pure
    {
        import std.uni : byGrapheme;

        if (isBig)
        {
            return large.ptr[0 .. large.len].byGrapheme;
        }
        else
        {
            return small.data[0 .. smallLength].byGrapheme;
        }
    }

    private enum smallCapacity = 31;
    private enum small_flag = 0x80, small_mask = 0x7F;

    private void setBig() @safe @nogc nothrow pure
    {
        small.slen |= small_flag;
    }

    private size_t smallLength() @property const @safe @nogc nothrow pure
    {
        return small.slen & small_mask;
    }

    private ubyte isBig() @property const @safe @nogc nothrow pure
    {
        return small.slen & small_flag;
    }

    /*
    Allocates a new array on the GC and copies the small data to it.
     */
    private void convertToBig(size_t cap = smallCapacity + 1) @trusted pure nothrow
    {
        import core.memory : GC;
        import core.stdc.string : memcpy;
        import std.algorithm.comparison : max;

        static size_t roundUpToMultipleOf(size_t s, ulong base)
        {
            assert(base);
            auto rem = s % base;
            return rem ? s + base - rem : s;
        }

        // copy stdx.allocator behavior
        immutable nbytes = roundUpToMultipleOf(
            cap * char.sizeof,
            max(double.alignof, real.alignof)
        );

        immutable size_t k = smallLength;
        char* p = cast(char*) GC.malloc(nbytes, GC.BlkAttr.NO_SCAN | GC.BlkAttr.APPENDABLE);

        memcpy(p, small.data.ptr, k);
        large.ptr = p;
        large.len = k;
        large.capacity = nbytes / char.sizeof;
        setBig();
    }

    /*
    Allocates space for n extra elements. If capacity can hold n more
    elements does nothing.
     */
    private void extend(size_t n) @trusted pure nothrow
    {
        import core.checkedint : mulu;
        import core.memory : GC;

        assert(isBig);
        immutable reqlen = large.len + n;

        if (large.capacity >= reqlen)
            return;

        bool overflow;
        const nbytes = mulu(reqlen, char.sizeof, overflow);
        if (overflow) assert(0, "New size of Yarn overflowed.");

        large.ptr = cast(char*) GC.realloc(
            large.ptr,
            nbytes,
            GC.BlkAttr.NO_SCAN | GC.BlkAttr.APPENDABLE
        );
        large.capacity = reqlen;
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

@safe pure unittest
{
    import std.algorithm.iteration : map;
    import std.algorithm.comparison : equal;
    import std.internal.test.dummyrange : DummyRange, ReturnBy, Length, RangeType, ReferenceForwardRange;
    import std.range : repeat;

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

    auto r1 = map!(a => cast(char) (a + 47))(DummyRange!(ReturnBy.Value, Length.No, RangeType.Input)());
    Yarn c = Yarn(r1);
    assert(c.byCodeUnit.equal("0123456789"));
    auto r2 = map!(a => cast(char) (a + '0'))(new ReferenceForwardRange!int(0.repeat(30)));
    c ~= r2.save;
    assert(c.byCodeUnit.equal("0123456789000000000000000000000000000000"));
    c ~= r2.save;
    assert(c.byCodeUnit.equal("0123456789000000000000000000000000000000000000000000000000000000000000"));

    auto r3 = map!(a => cast(char) (a + 47))(DummyRange!(ReturnBy.Value, Length.Yes, RangeType.Forward)());
    Yarn d = Yarn(r3.save);
    d ~= r3.save;
    d ~= r3.save;
    d ~= r3.save;
    d ~= r3.save;
    assert(d.byCodeUnit.equal("01234567890123456789012345678901234567890123456789"));
}

// test encoding on ctor and append
@safe pure unittest
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

    auto d2 = y4.byDchar;
    auto d3 = d2.save;
    d2.popFront;
    d2.popFront;
    assert(d3.equal("𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾"));
}

@safe pure unittest
{
    import std.algorithm.comparison : equal;
    import std.string : assumeUTF;
    import std.uni : byGrapheme;

    Yarn y1 = Yarn("𐐷𐐸𐐺𐐾");

    ubyte[] s1 = [0xF0, 0x90, 0x90, 0xB7, 0xF0, 0x90, 0x90, 0xB8,
                  0xF0, 0x90, 0x90, 0xBA, 0xF0, 0x90, 0x90, 0xBE];
    assert(y1.byChar.equal(s1.assumeUTF));

    ushort[] s2 = [0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E];
    assert(y1.byWchar.equal(s2.assumeUTF));

    uint[] s3 = [0x10437, 0x10438, 0x1043A, 0x1043E];
    assert(y1.byDchar.equal(s3.assumeUTF));

    assert(y1.byGrapheme.equal("𐐷𐐸𐐺𐐾".byGrapheme));

    Yarn y2 = Yarn("𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾");
    ushort[] s4 = [
        0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E,
        0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E,
        0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E,
        0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E
    ];
    assert(y2.byWchar.equal(s4.assumeUTF));
    assert(y2.byGrapheme.equal("𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾".byGrapheme));
}

pure unittest
{
    Yarn y1;
    assert(!y1.isBig);
    // does nothing, as it's < smallCapacity
    y1.reserve(10);
    assert(!y1.isBig);
    y1.reserve(50);
    assert(y1.isBig);
    // not exact as it's more effectient to allocate more
    // in many cases
    assert(y1.large.capacity >= 50);
    // should do nothing
    y1.extend(20);
    assert(y1.large.capacity >= 50);

    y1.reserve(100);
    assert(y1.large.capacity >= 100);
}
