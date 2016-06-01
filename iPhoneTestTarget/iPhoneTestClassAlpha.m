#import <XCTest/XCTest.h>

@interface iPhoneTestClassAlpha : XCTestCase

@end

@implementation iPhoneTestClassAlpha

- (void)testAres {
    [NSThread sleepForTimeInterval: .2f];
    XCTAssert(YES, @"Passing Ares");
}

- (void)testApollo {
    [NSThread sleepForTimeInterval: .1f];
    XCTAssert(YES, @"Passing testApollo");
}

@end
