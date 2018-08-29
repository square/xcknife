#import <XCTest/XCTest.h>

@interface iPhoneTestClassGama : XCTestCase

@end

@implementation iPhoneTestClassGama

- (void)testPoseidon {
    [NSThread sleepForTimeInterval: .3f];
    XCTAssert(YES, @"Passing testPoseidon");
}

@end
