#import <XCTest/XCTest.h>

@interface iPhoneTestClassDelta : XCTestCase

@end

@implementation iPhoneTestClassDelta

- (void)testApollo {
    [NSThread sleepForTimeInterval: .1f];
    XCTAssert(YES, @"Passing testApollo");
}

@end
