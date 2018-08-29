#import <XCTest/XCTest.h>

@interface iPadTestClassFour : XCTestCase

@end

@implementation iPadTestClassFour

- (void)testIPadGru {
    [NSThread sleepForTimeInterval: .2f];
    XCTAssert(YES, @"Passing testIPadGru");
}

@end
