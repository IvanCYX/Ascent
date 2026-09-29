#!/bin/sh
# Runs the AscentCore tests with the Command Line Tools' swift-testing (no Xcode needed).
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
cd "$(dirname "$0")" && swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
