// args_behavior_check.cpp — behavioral oracle for Taywee/args.
//
// Built by build.sh into /mayhem/args-behavior-check and run by test.sh.
// Parses KNOWN argument vectors through args::ArgumentParser and PRINTS the
// extracted values to stdout.  test.sh greps for specific expected output
// lines — if the binary is neutered (exits 0 immediately), nothing is printed
// and the grep assertions fail, defeating reward-hacking (§6.3).
//
// Three test cases:
//   TC1  flag + value parsing:  -b --foo=hello --count=42
//   TC2  short flag grouping:   -fbtest --baz=7.555e2
//   TC3  default-value path:    (no args) → default string "unset"
//
// Each case prints "PASS <name>: <key>=<val>" lines; the suite exits 0 iff
// ALL cases pass, non-zero on any discrepancy.

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
#include <cmath>

#include "args.hxx"

static int failed = 0;

static void check(bool cond, const std::string &name, const std::string &msg) {
    if (cond) {
        std::cout << "PASS " << name << ": " << msg << "\n";
    } else {
        std::cerr << "FAIL " << name << ": " << msg << "\n";
        ++failed;
    }
}

int main() {
    // --- TC1: flag + string value + integer value ---
    {
        args::ArgumentParser p("behavior-check TC1");
        args::Flag        bar(p, "bar", "bool flag",       {'b', "bar"});
        args::ValueFlag<std::string> foo(p, "foo", "string val", {'f', "foo"});
        args::ValueFlag<int>         cnt(p, "count","int val",   {'c', "count"});
        p.ParseArgs(std::vector<std::string>{"-b", "--foo=hello", "--count=42"});

        check(bool(bar),           "TC1", "bar=true");
        check(bool(foo) && *foo == "hello", "TC1", "foo=hello");
        check(bool(cnt) && *cnt == 42,      "TC1", "count=42");
    }

    // --- TC2: short flag grouping + double value ---
    {
        args::ArgumentParser p("behavior-check TC2");
        args::ValueFlag<std::string> foo(p, "foo", "string val", {'f', "foo"});
        args::Flag                   bar(p, "bar", "bool flag",   {'b', "bar"});
        args::ValueFlag<double>      baz(p, "baz", "double val",  {'a', "baz"});
        p.ParseArgs(std::vector<std::string>{"-bftest", "--baz=7.555e2"});

        check(bool(bar),                           "TC2", "bar=true");
        check(bool(foo) && *foo == "test",         "TC2", "foo=test");
        check(bool(baz) && std::fabs(*baz - 755.5) < 0.1, "TC2", "baz=755.5");
    }

    // --- TC3: default value is returned when flag is absent ---
    {
        args::ArgumentParser p("behavior-check TC3");
        args::ValueFlag<std::string> opt(p, "opt", "optional", {'o', "opt"}, "unset");
        p.ParseArgs(std::vector<std::string>{});   // no arguments

        // flag absent → default returned
        check(*opt == "unset", "TC3", "opt=unset");
    }

    if (failed == 0) {
        std::cout << "ALL_PASS\n";
        return 0;
    }
    std::cerr << failed << " case(s) FAILED\n";
    return 1;
}
