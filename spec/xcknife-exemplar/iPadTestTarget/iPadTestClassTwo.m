#import <XCTest/XCTest.h>

@interface iPadTestClassTwo : XCTestCase

@end

@implementation iPadTestClassTwo

- (void)testIPadSjc {
    [NSThread sleepForTimeInterval: 5.0f];
    XCTAssert(YES, @"Passing testIPadSjc");
}

@end
