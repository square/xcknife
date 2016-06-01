#!/bin/bash
XC_DESTINATION='platform=iOS Simulator,name=iPad Air,OS=9.2'
xctool -project XCKnifeExemplar.xcodeproj -configuration Debug -derivedDataPath derivedDataPath -scheme XCKnifeExemplar -sdk iphonesimulator -destination "$XC_DESTINATION" -reporter pretty -reporter json-stream:xcknife-exemplar-historical-data.json-stream run-tests
