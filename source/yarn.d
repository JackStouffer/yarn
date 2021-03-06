module yarn;

import std.traits;
import std.range.primitives;
version(unittest) import std.stdio;

/// Default yarn type.
alias yarn = Yarn!(immutable char);

/**
A safe `string` type optimized for both small sizes and for appending
large amounts of data.

Specifically designed to not be compatible with built-in `string` types.
In order to iterate over the data contained in a `Yarn`, the iteration
method must be chosen first. This is in contrast with `string` which defaults
to iteration by code point (a.k.a auto-decoding). `Yarn` offers the
standard `std.utf` and `std.uni` range generating functions: `byCodeUnit`,
`byCodePoint`, `byChar`, `byWchar`, `byDchar`, and `byGrapheme`.

Any iteration or equality comparison of a `Yarn` must therefore explicitly choose
the method of iteration at every usage. There is no way to get at the underlying
data other than these methods.

`Yarn` is an `OutputRange` for all `char` types.
 */
struct Yarn(C)
if (isSomeChar!(C))
{
    private alias UC = Unqual!(C);

    /**
    Construct a `Yarn` from a finite character range.

    Params:
        r = A finite input range of any character type.
     */
    this(R)(R r)
    if (isInputRange!R && !isInfinite!R && isSomeChar!(ElementType!R))
    {
        this ~= r;
    }

    /**
    Reassign the current data to the given range.

    Note:
        Does not manually free the existing GC array.
     */
    ref opAssign(R)(R r)
    if (isInputRange!R && !isInfinite!R && isSomeChar!(ElementType!R))
    {
        static if (isMutable!C)
        {
            reset();
            this ~= r;
        }
        else
        {
            // allocate a new array and let the old one be collected
            convertToBig(r.length);
            this ~= r;
        }
    }

    /**
    Appends the given character or finite character input range to the existing
    data.

    Throws:
        `UTFException` on bad utf data. `OutOfMemory` when allocation fails.
     */
    ref opOpAssign(string op, Char)(Char ch) @trusted pure
    if (op == "~" && isSomeChar!(Char))
    {
        static if (is(Unqual!Char == UC))
        {
            if (!isBig)
            {
                if (small.slen == smallCapacity)
                {
                    convertToBig();
                }
                else
                {
                    small.data[length] = ch;
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
            UC[4 / UC.sizeof] buf;
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
    if (op == "~" && isSomeString!S)
    {
        if (!isBig && s.length + length > smallCapacity)
        {
            convertToBig(s.length + length);
        }
        else if (isBig)
        {
            extend(s.length);
        }

        alias E = Unqual!(ElementEncodingType!S);
        static if (is(E == UC))
        {
            if (isBig)
            {
                large.ptr[large.len .. large.len + s.length] = s;
                large.len += s.length;
            }
            else
            {
                small.data[length .. length + s.length] = s;
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
    if (op == "~" && !isSomeString!R && isInputRange!R && !isInfinite!R && isSomeChar!(ElementType!R))
    {
        static if (hasLength!R)
        {
            if (!isBig && r.length + length > smallCapacity)
            {
                convertToBig(r.length + length);
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
    Allocate space for at least `newCapacity` elements.

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

    static if (isMutable!C)
    {
        /**
        Set the Yarn back to small-size optimization mode and clear the existing data.

        Disabled when `C` is a non-mutable type, as it may overwrite immutable
        data.

        Note:
            Does not manually free the GC array if it exists.
         */
        void reset() @nogc pure nothrow
        {
            small.slen = 0;
            small.data = smallEmpty;
        }
    }

    /**
    Returns: The data as a random access range of code units.
     */
    auto byCodeUnit() @trusted @nogc pure nothrow
    {
        import std.utf : byCodeUnit;

        auto t = Range!(typeof(this), C)(this, 0, length());
        return t.byCodeUnit;
    }

    /**
    Returns:
        The data as a forward range of `chars`. If `is(Unqual!C == char)`,
        the range will be random access.
     */
    auto byChar() @trusted @nogc pure nothrow
    {
        import std.utf : byChar;

        auto t = Range!(typeof(this), C)(this, 0, length());
        return t.byChar;
    }

    /**
    Returns:
        The data as a forward range of `wchars`. If `is(Unqual!C == wchar)`,
        the range will be random access.
     */
    auto byWchar() @trusted @nogc pure nothrow
    {
        import std.utf : byWchar;

        auto t = Range!(typeof(this), C)(this, 0, length());
        return t.byWchar;
    }

    /**
    Returns:
        The data as a forward range of `dchar`. If `is(Unqual!C == dchar)`,
        the range will be random access.
     */
    auto byDchar() @trusted pure nothrow
    {
        import std.utf : byDchar;

        auto t = Range!(typeof(this), C)(this, 0, length());
        return t.byDchar;
    }

    /**
    Returns: The data as a forward range of Graphemes.
     */
    //auto byGrapheme() @system pure
    //{
    //    import std.uni : byGrapheme;

    //    auto t = Range!(typeof(this), C)(this, 0, length());
    //    return t.byGrapheme;
    //}

    private enum smallCapacity = 31 / C.sizeof;
    private enum small_flag = 0x80, small_mask = 0x7F;
    static if (C.sizeof == 1)
        private enum char[smallCapacity] smallEmpty = [
            '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
            '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
            '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
        ];
    else static if (C.sizeof == 2)
        private enum wchar[smallCapacity] smallEmpty = [
            '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
            '\0', '\0', '\0', '\0', '\0'
        ];
    else static if (C.sizeof == 4)
        private enum dchar[smallCapacity] smallEmpty = [
            '\0', '\0', '\0', '\0', '\0', '\0', '\0'
        ];

    private void setBig() @safe @nogc nothrow pure
    {
        small.slen |= small_flag;
    }

    private size_t length() @property const @trusted @nogc nothrow pure
    {
        if (isBig)
            return large.len;
        else
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
            auto rem = s % base;
            return rem ? s + base - rem : s;
        }

        // copy stdx.allocator behavior
        enum alignof = max(double.alignof, real.alignof);
        immutable nbytes = roundUpToMultipleOf(cap * C.sizeof, alignof);

        immutable size_t k = length;
        UC* p = cast(UC*) GC.malloc(nbytes, GC.BlkAttr.NO_SCAN | GC.BlkAttr.APPENDABLE);

        static if (C.sizeof == 1)
        {
            memcpy(p, small.data.ptr, k);
        }
        else
        {
            for (int i; i < k; i++)
            {
                p[i] = small.data[i];
            }
        }

        if (!isBig)
        {
            setBig();
        }
        large.ptr = p;
        large.len = k;
        large.capacity = nbytes / C.sizeof;
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
        const nbytes = mulu(reqlen, C.sizeof, overflow);
        if (overflow) assert(0, "New size of Yarn overflowed.");

        large.ptr = cast(UC*) GC.realloc(
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
            UC[smallCapacity] data;
            ubyte slen;
        }

        private static struct Large
        {
            UC* ptr;
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
            UC[smallCapacity] data;
        }

        private static struct Large
        {
            size_t padding;
            size_t len;
            size_t capacity;
            UC* ptr;
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
    import std.algorithm.comparison : equal;
    import std.conv : to;
    import std.meta : AliasSeq;
    import std.range : retro;
    //import std.uni : byGrapheme;

    foreach (T; AliasSeq!(char, immutable char, wchar, immutable wchar, dchar, immutable dchar))
    {
        auto start = to!(T[])("test");
        Yarn!(T) y1 = start;
        assert(y1.byCodeUnit.equal(start));
        assert(y1.byCodeUnit[].equal(start));
        assert(y1.byCodeUnit[0 .. 2].equal(start[0 .. 2]));
        assert(y1.byCodeUnit[0] == 't');
        assert(y1.byCodeUnit.retro.equal(start.retro));
        assert(y1.byChar.equal("test"));
        assert(y1.byWchar.equal("test"w));
        assert(y1.byDchar.equal("test"d));
        //assert(y1.byGrapheme.equal("test".byGrapheme));

        y1 ~= " test test test";
        y1 ~= " test test test"w;
        y1 ~= " test test test"d;
        assert(y1.byCodeUnit.equal(to!(T[])("test test test test test test test test test test")));
        assert(y1.byCodeUnit[].equal(to!(T[])("test test test test test test test test test test")));
        assert(y1.byCodeUnit.retro.equal(to!(T[])("test test test test test test test test test test").retro));
        assert(y1.byCodeUnit[0 .. 2].equal("te"));
        assert(y1.byCodeUnit[1] == 'e');
        assert(y1.byChar.equal("test test test test test test test test test test"));
        assert(y1.byWchar.equal("test test test test test test test test test test"w));
        assert(y1.byDchar.equal("test test test test test test test test test test"d));

        // test construction conversion to large
        Yarn!(T) y2 = to!(T[])("test test test test test test test test test test test");
        assert(y2.byChar.equal("test test test test test test test test test test test"));
    }
}

@safe pure unittest
{
    import std.algorithm.iteration : map;
    import std.algorithm.comparison : equal;
    import std.internal.test.dummyrange : DummyRange, ReturnBy, Length, RangeType, ReferenceForwardRange;
    import std.range : repeat;

    auto r1 = map!(a => cast(char) (a + 47))(DummyRange!(ReturnBy.Value, Length.No, RangeType.Input)());
    yarn c = yarn(r1);
    assert(c.byCodeUnit.equal("0123456789"));
    auto r2 = map!(a => cast(char) (a + '0'))(new ReferenceForwardRange!int(0.repeat(30)));
    c ~= r2.save;
    assert(c.byCodeUnit.equal("0123456789000000000000000000000000000000"));
    c ~= r2.save;
    assert(c.byCodeUnit.equal("0123456789000000000000000000000000000000000000000000000000000000000000"));

    auto r3 = map!(a => cast(char) (a + 47))(DummyRange!(ReturnBy.Value, Length.Yes, RangeType.Forward)());
    yarn d = yarn(r3.save);
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

    wstring w = "øōôòœõ";
    yarn y1 = w;
    assert(y1.byDchar.equal("øōôòœõ"));
    yarn y2;
    y2 ~= w;
    assert(y2.byDchar.equal("øōôòœõ"));

    dstring d = "𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾";
    yarn y3 = d;
    assert(y3.byDchar.equal("𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾"));
    yarn y4;
    y4 ~= d;
    assert(y4.byDchar.equal("𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾"));

    auto d2 = y4.byDchar;
    auto d3 = d2.save;
    d2.popFront;
    d2.popFront;
    assert(d3.equal("𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾"));
}

@safe pure unittest
{
    import std.algorithm.iteration : map;
    import std.algorithm.comparison : equal;
    import std.string : assumeUTF;
    //import std.uni : byGrapheme;

    yarn y1 = "𐐷𐐸𐐺𐐾";

    ubyte[] s1 = [0xF0, 0x90, 0x90, 0xB7, 0xF0, 0x90, 0x90, 0xB8,
                  0xF0, 0x90, 0x90, 0xBA, 0xF0, 0x90, 0x90, 0xBE];
    assert(y1.byChar.equal(s1.map!(a => cast(char) a)));

    ushort[] s2 = [0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E];
    assert(y1.byWchar.equal(s2.assumeUTF));

    uint[] s3 = [0x10437, 0x10438, 0x1043A, 0x1043E];
    assert(y1.byDchar.equal(s3.assumeUTF));

    //assert(y1.byGrapheme.equal("𐐷𐐸𐐺𐐾".byGrapheme));

    yarn y2 = "𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾";
    ushort[] s4 = [
        0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E,
        0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E,
        0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E,
        0xD801, 0xDC37, 0xD801, 0xDC38, 0xD801, 0xDC3A, 0xD801, 0xDC3E
    ];
    assert(y2.byWchar.equal(s4.assumeUTF));
    //assert(y2.byGrapheme.equal("𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾𐐷𐐸𐐺𐐾".byGrapheme));
}

@system pure unittest
{
    import std.algorithm.comparison : equal;

    Yarn!(char) y1;
    assert(!y1.isBig);
    // does nothing, as it's < smallCapacity
    y1.reserve(10);
    assert(!y1.isBig);
    y1.reserve(50);
    assert(y1.isBig);
    // not exact as it's more efficient to allocate more
    // in many cases
    assert(y1.large.capacity >= 50);
    // should do nothing
    y1.extend(20);
    assert(y1.large.capacity >= 50);

    y1.reserve(100);
    assert(y1.large.capacity >= 100);

    y1.reset();
    assert(!y1.isBig);
    y1.reserve(50);
    assert(y1.isBig);

    y1 = "test";
    assert(!y1.isBig);
    assert(y1.byCodeUnit.equal("test"));
}

// test for iterator invalidation
@system pure unittest
{
    import std.algorithm.comparison : equal;

    yarn y1 = "test";
    auto r1 = y1.byCodeUnit;
    y1 ~= " test test test test test test test test";
    assert(y1.isBig);
    assert(r1.equal("test"));
    auto r2 = y1.byCodeUnit;
    assert(r2.equal("test test test test test test test test test"));

    Yarn!(wchar) y2 = "test";
    auto r3 = y2.byChar;
    y2 ~= " test test test test test test test test";
    assert(r3.equal("test"));
}

/*
Custom range type that copies that data/pointer of a Yarn in
order to avoid iterator invalidation.
 */
private struct Range(T, C)
{
    T yarnData;
    size_t a, b;

    this(ref T data, size_t start, size_t end)
    {
        yarnData = data;
        a = start;
        b = end;
    }

    static if (isMutable!C)
    {
        ref inout(C) front() @trusted inout
        {
            assert(!empty, "Attempting to get the front of an empty " ~ T.stringof);
            if (yarnData.isBig)
                return yarnData.large.ptr[a];
            else
                return yarnData.small.data[a];
        }

        ref inout(C) back() @trusted inout
        {
            assert(!empty, "Attempting to get the back of an empty " ~ T.stringof);
            if (yarnData.isBig)
                return yarnData.large.ptr[b - 1];
            else
                return yarnData.small.data[b - 1];
        }

        ref inout(C) opIndex(size_t i) @trusted inout
        {
            assert(a + i < b);
            if (yarnData.isBig)
                return yarnData.large.ptr[a + i];
            else
                return yarnData.small.data[a + i];
        }
    }
    else
    {
        inout(C) front() @trusted inout
        {
            assert(!empty, "Attempting to get the front of an empty " ~ T.stringof);
            if (yarnData.isBig)
                return yarnData.large.ptr[a];
            else
                return yarnData.small.data[a];
        }

        inout(C) back() @trusted inout
        {
            assert(!empty, "Attempting to get the back of an empty " ~ T.stringof);
            if (yarnData.isBig)
                return yarnData.large.ptr[b - 1];
            else
                return yarnData.small.data[b - 1];
        }

        inout(C) opIndex(size_t i) @trusted inout
        {
            assert(a + i < b, "Index out of bounds on a " ~ T.stringof);
            if (yarnData.isBig)
                return yarnData.large.ptr[a + i];
            else
                return yarnData.small.data[a + i];
        }
    }

    void popFront() @safe @nogc pure nothrow
    {
        assert(!empty, "Attempting to popFront an empty " ~ T.stringof);
        ++a;
    }

    void popBack() @safe @nogc pure nothrow
    {
        assert(!empty, "Attempting to popBack an empty " ~ T.stringof);
        --b;
    }

    auto save() @safe pure nothrow
    {
        return this;
    }

    bool empty() @property @safe pure nothrow const
    {
        return a >= b;
    }

    size_t length() @property @safe pure nothrow const
    {
        return b - a;
    }
    alias opDollar = length;

    auto opSlice() @safe pure nothrow
    {
        return typeof(this)(yarnData, a, b);
    }

    auto opSlice(size_t i, size_t j) @safe pure nothrow
    {
        assert(i <= j && a + j <= b, "Slice index out of bounds on a " ~ T.stringof);
        return typeof(this)(yarnData, a + i, a + j);
    }
}
