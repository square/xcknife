#!/bin/bash
rm -rf TestDumper.dylib testdumperbuild
xcodebuild -project TestDumper.xcodeproj \
    -configuration Release \
    -derivedDataPath testdumperbuild \
    -scheme TestDumper \
    -sdk iphonesimulator build
