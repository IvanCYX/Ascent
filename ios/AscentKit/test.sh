#!/bin/sh
# Runs the package tests. With Xcode selected, plain `swift test` works; with only the Command Line Tools,
# swift-testing needs its framework passed in by hand.
cd "$(dirname "$0")"
if xcode-select -p 2>/dev/null | grep -q '\.app/'; then exec swift test "$@"; fi
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
