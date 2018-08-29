#import <XCTest/XCTest.h>

@interface iPadTestClassOne : XCTestCase

@end

@implementation iPadTestClassOne

- (void)testIPadIad {
    [NSThread sleepForTimeInterval: 1.0f];
    XCTAssert(YES, @"Passing testIPadIad");
}

@end
