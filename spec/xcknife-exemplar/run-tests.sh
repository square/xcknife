#!/bin/bash
XC_DESTINATION='platform=iOS Simulator,name=iPad Air (3rd generation),OS=13.6'

xcodebuild -project XCKnifeExemplar.xcodeproj \
    -configuration Debug \
    -derivedDataPath derivedDataPath \
    -scheme XCKnifeExemplar \
    -sdk iphonesimulator \
    -destination "$XC_DESTINATION" \
    test-without-building
