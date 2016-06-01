#import <XCTest/XCTest.h>

@interface CommonTestTarget : XCTestCase

@end

@implementation CommonTestTarget

- (void)testCommonOne {
    [NSThread sleepForTimeInterval: .1f];
    XCTAssert(YES, @"Passing");
}

- (void)testCommonTwo {
    [NSThread sleepForTimeInterval: .2f];
    XCTAssert(YES, @"Passing");
}

- (void)testCommonThree {
    [NSThread sleepForTimeInterval: 5.0f];
    XCTAssert(YES, @"Passing");
}

@end
