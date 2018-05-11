# Yarn

Yarn is `@safe` `string` type optimized for both small sizes and for appending
large amounts of data. Uses the GC for all allocations.

Specifically designed to not be drop-in compatible with built-in `string` types.
In order to iterate over the data contained in a `Yarn`, the iteration
method must be chosen first. This is in contrast with `string` which defaults
to iteration by code point (a.k.a auto-decoding). `Yarn` offers the
standard `std.utf` and `std.uni` range generating functions: `byCodeUnit`,
`byCodePoint`, `byChar`, `byWchar`, and `byDchar`.

Any iteration or equality comparison of a `Yarn` must therefore explicitly choose
the method of iteration at every usage. There is no way to get at the underlying
data other than these methods.

## Benchmark

```
$ ldc2 -O -release -enable-cross-module-inlining -flto=full bench.d source/yarn.d && ./bench                                                        [11:08:37]

Small String Append
============================================
string      351 ms and 612 μs
yarn        14 ms, 64 μs, and 5 hnsecs
Appender    221 ms, 495 μs, and 4 hnsecs

Large String Append
============================================
string      276 ms, 31 μs, and 1 hnsec
yarn        164 ms, 5 μs, and 4 hnsecs
Appender    260 ms and 627 μs

Small String Sort
============================================
string      8 μs
yarn        3 μs

Large String Sort
============================================
string      2 μs and 5 hnsecs
yarn        8 μs and 1 hnsec
```

## Examples

```d
import std.algorithm.comparison : equal;

yarn y = "Hello, World!"; // yarn is an alias to Yarn!(immutable char)
assert(y.byCodeUnit.equal("Hello, World!"));
assert(y.byWchar.equal("Hello, World!"w));

y ~= "String append.";
y ~= "Wide string append."w; // auto encodes to the correct type

// at the end of scope, the data on the GC is not manually freed
```

```d
yarn y;

y.reserve(100); // allocate memory for at least 100 elements ahead of assignment
y ~= "String append."; // much faster for ranges of unknown length
```

```d
Yarn!(wchar) y;
y.put("Hello, World!"); // offers Output Range interface

auto r = y.byCodeUnit;
y ~= "String";
assert(y.byWchar.equal("Hello, World!"w)); // no range invalidation on appends

// mutable char Yarns can be reset
y.reset();
assert(y.byCodeUnit.empty);
```

## Docs

### yarn

Default yarn type.

```d
alias yarn = Yarn!(immutable(char)).Yarn;
```

### Yarn

```d
struct Yarn(C) if (isSomeChar!C);
```

A safe string type optimized for both small sizes and for appending large amounts of data.

`Yarn` is an `OutputRange` for all `char` types.

##### Note On Invalid Data

Unlike `string`, `Yarn` will not throw when iterating over invalid UTF data.

The only time a `UTFException` will be thrown is when encoding a character into
a different character width, e.g. putting a `wchar` or a `dchar` into a `Yarn!(char)`.

#### `this`

##### Declaration

```d
this(R)(R r) if (isInputRange!R && !isInfinite!R && isSomeChar!(ElementType!R));
```
Construct a Yarn from a finite character range.

##### Parameters:
`R r`  = A finite input range of any character type.

#### `opAssign`

##### Declaration

```d
ref auto opAssign(R)(R r) if (isInputRange!R && !isInfinite!R && isSomeChar!(ElementType!R));
```

Reassign the current data to the given range.

##### Note:
Does not manually free the existing GC array.

#### `opOpAssign`

##### Declaration

```d
pure ref @trusted auto opOpAssign(string op, Char)(Char ch) if (op == "~" && isSomeChar!Char); 
pure ref @trusted auto opOpAssign(string op, S)(S s) if (op == "~" && isSomeString!S); 
ref auto opOpAssign(string op, R)(R r) if (op == "~" && !isSomeString!R && isInputRange!R && !isInfinite!R && isSomeChar!(ElementType!R));
```

Appends the given character or finite character input range to the existing data.

##### Throws
`UTFException` on bad utf data. `OutOfMemory` when allocation fails.

#### `put`

##### Declaration

```d
void put(R)(R r) if (isSomeChar!R || isInputRange!R && isSomeChar!(ElementType!R));
```

Performs the same action as `~=`.

#### `reserve`

##### Declaration

```d
pure nothrow @trusted void reserve(size_t newCapacity);
```

Allocate space for at least newCapacity elements.

##### Parameters

`size_t newCapacity` = total amount of elements that this Yarn should have space for.

#### `reset`

##### Declaration

```d
pure nothrow @nogc void reset();
```

Set the Yarn back to small-size optimization mode and clear the existing data.

Disabled when `C` is a non-mutable type, as it may overwrite `immutable` data.

##### Note:

Does not manually free the GC array if it exists.

#### `byCodeUnit`

##### Declaration

```d
pure nothrow @nogc @trusted auto byCodeUnit();
```

##### Returns:

The data as a random access range of code units.

#### `byChar`

##### Declaration

```d
pure nothrow @nogc @trusted auto byChar();
```

##### Returns:

The data as a forward range of `char`s. If `is(Unqual!C == char)`, the range will be random access.

#### `byWchar`

##### Declaration

```d
pure nothrow @nogc @trusted auto byWchar();
```

##### Returns:

The data as a forward range of `wchar`s. If `is(Unqual!C == wchar)`, the range
will be random access.

#### `byDchar`

##### Declaration

```d
pure nothrow @trusted auto byDchar();
```

##### Returns:
The data as a forward range of `dchar`s. If `is(Unqual!C == dchar)`, the range
will be random access.
