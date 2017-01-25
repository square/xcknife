#!/bin/bash
xcodebuild -project TestDumper.xcodeproj \
    -configuration Release \
    -derivedDataPath testdumperbuild \
    -scheme TestDumper \
    -sdk iphonesimulator build
