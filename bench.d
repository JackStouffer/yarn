import std.stdio;
import std.conv;
import std.range;
import std.traits;
import std.array;
import std.algorithm;
import std.datetime.stopwatch;
import core.time;
import std.random;
import std.utf;
import yarn;

enum testCount = 2_000_000;

auto test1()
{
    string a;
    a ~= "Recusandae nobis ipsam";
    return a.length;
}

auto test2()
{
    Yarn a;
    a ~= "Recusandae nobis ipsam";
    return a.byCodeUnit.length;
}

auto test3()
{
    Appender!(string) a;
    a ~= "Recusandae nobis ipsam";
    return a.data.length;
}

auto test4()
{
    string a;
    a ~= "Recusandae nobis ipsam qui assumenda iusto iure. Consectetur nobis aliquid eius autem error fugiat veniam.";
    return a.length;
}

auto test5()
{
    Yarn a;
    a ~= "Recusandae nobis ipsam qui assumenda iusto iure. Consectetur nobis aliquid eius autem error fugiat veniam.";
    return a.byCodeUnit.length;
}

auto test6()
{
    Appender!(string) a;
    a ~= "Recusandae nobis ipsam qui assumenda iusto iure. Consectetur nobis aliquid eius autem error fugiat veniam.";
    return a.data.length;
}

void main()
{
    size_t res;
    auto result = to!Duration(benchmark!(() => res = test1())(testCount)[0]);
    auto result2 = to!Duration(benchmark!(() => res = test2())(testCount)[0]);
    auto result3 = to!Duration(benchmark!(() => res = test3())(testCount)[0]);

    writeln("\nSmall String Append\n============================================");
    writeln("string", "\t\t", result);
    writeln("yarn", "\t\t", result2);
    writeln("Appender", "\t", result3);

    result = to!Duration(benchmark!(() => res = test4())(testCount)[0]);
    result2 = to!Duration(benchmark!(() => res = test5())(testCount)[0]);
    result3 = to!Duration(benchmark!(() => res = test6())(testCount)[0]);

    writeln("\nLarge String Append\n============================================");
    writeln("string", "\t\t", result);
    writeln("yarn", "\t\t", result2);
    writeln("Appender", "\t", result3);

    writeln("\nSmall String Sort\n============================================");
    auto sw = StopWatch(AutoStart.no);
    char[] s1 = "Recusandae nobis ipsam".dup;
    Yarn y1 = Yarn("Recusandae nobis ipsam");

    sw.reset();
    sw.start();
    s1.byCodeUnit.sort();
    sw.stop();

    writeln("string", "\t\t", sw.peek());

    sw.reset();
    sw.start();
    y1.byCodeUnit.sort();
    sw.stop();

    writeln("yarn", "\t\t", sw.peek());

    writeln("\nLarge String Sort\n============================================");
    char[] s2 = "Recusandae nobis ipsam qui assumenda iusto iure. Consectetur nobis aliquid eius autem error fugiat veniam.".dup;
    Yarn y2 = Yarn("Recusandae nobis ipsam qui assumenda iusto iure. Consectetur nobis aliquid eius autem error fugiat veniam.");

    sw.reset();
    sw.start();
    s2.byCodeUnit.sort();
    sw.stop();
    
    writeln("string", "\t\t", sw.peek());

    sw.reset();
    sw.start();
    y2.byCodeUnit.sort();
    sw.stop();
    
    writeln("yarn", "\t\t", sw.peek());

    writeln("\nignore this", res); // confuse optimizer
}