#import <XCTest/XCTest.h>

@interface iPhoneTestClassBeta : XCTestCase

@end

@implementation iPhoneTestClassBeta

- (void)testArtemis {
    [NSThread sleepForTimeInterval: .2f];
    XCTAssert(YES, @"Passing testArtemis");
}

@end
