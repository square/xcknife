#import <XCTest/XCTest.h>

@interface iPadTestClassThree : XCTestCase

@end

@implementation iPadTestClassThree

- (void)testIPadNrt {
    [NSThread sleepForTimeInterval: .5f];
    XCTAssert(YES, @"Passing testIPadNrt");
}

@end
