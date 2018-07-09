#!/bin/bash
rm -rf derivedDataPath

XC_DESTINATION='platform=iOS Simulator,name=iPad Air,OS=11.2'

xcodebuild -project XCKnifeExemplar.xcodeproj \
    -configuration Debug \
    -derivedDataPath derivedDataPath \
    -scheme XCKnifeExemplar \
    -sdk iphonesimulator \
    -destination "$XC_DESTINATION" \
    build-for-testing
