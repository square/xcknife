#import <XCTest/XCTest.h>

@interface CommonTestClass : XCTestCase

@end

@implementation CommonTestClass

- (void)testCommonOne {
    [NSThread sleepForTimeInterval: .1f];
    XCTAssert(YES, @"Passing testCommonOne");
}

- (void)testCommonTwo {
    [NSThread sleepForTimeInterval: .2f];
    XCTAssert(YES, @"Passing testCommonTwo");
}

- (void)testCommonThree {
    [NSThread sleepForTimeInterval: .3f];
    XCTAssert(YES, @"Passing testCommonThree");
}

@end
