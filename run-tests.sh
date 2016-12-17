#!/bin/bash
XC_DESTINATION='platform=iOS Simulator,name=iPad Air,OS=9.2'

xcodebuild -project XCKnifeExemplar.xcodeproj \
    -configuration Debug \
    -derivedDataPath derivedDataPath \
    -scheme XCKnifeExemplar \
    -sdk iphonesimulator \
    -destination "$XC_DESTINATION" \
    test-without-building
