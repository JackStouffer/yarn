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
    yarn a;
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
    a ~= q{
Voluptate est numquam aut consequatur libero qui. Sed pariatur quisquam aspernatur quo similique iure occaecati repudiandae. Eligendi pariatur veritatis nostrum aut debitis modi at. In quis sapiente et quaerat et omnis doloribus. Minima nostrum iure adipisci consequatur.
Expedita quibusdam culpa tempora dolores quo illo sed unde. Impedit sint atque doloremque. Deleniti veritatis nulla occaecati. Nam veritatis omnis omnis necessitatibus nisi. Voluptas delectus autem et non reprehenderit quia.
    };
    return a.length;
}

auto test5()
{
    yarn a;
    a ~= q{
Voluptate est numquam aut consequatur libero qui. Sed pariatur quisquam aspernatur quo similique iure occaecati repudiandae. Eligendi pariatur veritatis nostrum aut debitis modi at. In quis sapiente et quaerat et omnis doloribus. Minima nostrum iure adipisci consequatur.
Expedita quibusdam culpa tempora dolores quo illo sed unde. Impedit sint atque doloremque. Deleniti veritatis nulla occaecati. Nam veritatis omnis omnis necessitatibus nisi. Voluptas delectus autem et non reprehenderit quia.
    };
    return a.byCodeUnit.length;
}

auto test6()
{
    Appender!(string) a;
    a ~= q{
Voluptate est numquam aut consequatur libero qui. Sed pariatur quisquam aspernatur quo similique iure occaecati repudiandae. Eligendi pariatur veritatis nostrum aut debitis modi at. In quis sapiente et quaerat et omnis doloribus. Minima nostrum iure adipisci consequatur.
Expedita quibusdam culpa tempora dolores quo illo sed unde. Impedit sint atque doloremque. Deleniti veritatis nulla occaecati. Nam veritatis omnis omnis necessitatibus nisi. Voluptas delectus autem et non reprehenderit quia.
    };
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
    Yarn!(char) y1 = "Recusandae nobis ipsam";

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
    Yarn!(char) y2 = "Recusandae nobis ipsam qui assumenda iusto iure. Consectetur nobis aliquid eius autem error fugiat veniam.";

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