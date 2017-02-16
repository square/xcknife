#!/bin/bash
rm -rf TestDumper.dylib testdumperbuild
xcodebuild -project TestDumper.xcodeproj \
    -configuration Debug \
    -derivedDataPath testdumperbuild \
    -scheme TestDumper \
    -sdk iphonesimulator build ONLY_ACTIVE_ARCH=NO
