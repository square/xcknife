#import <XCTest/XCTest.h>

@interface iPhoneTestClassAlpha : XCTestCase

@end

@implementation iPhoneTestClassAlpha

- (void)testAres {
    [NSThread sleepForTimeInterval: .2f];
    XCTAssert(YES, @"Passing Ares");
}

@end
