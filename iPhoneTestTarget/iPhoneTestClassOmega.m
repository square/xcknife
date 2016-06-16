#import <XCTest/XCTest.h>

@interface iPhoneTestClassOmega : XCTestCase

@end

@implementation iPhoneTestClassOmega

- (void)testZeus {
    [NSThread sleepForTimeInterval: .1f];
    XCTAssert(YES, @"Passing testZeus");
}

@end
