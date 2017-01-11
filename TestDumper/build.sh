#!/bin/bash
xcodebuild -project TestDumper.xcodeproj \
    -configuration Debug \
    -derivedDataPath testdumperbuild \
    -scheme TestDumper \
    -sdk iphonesimulator build
