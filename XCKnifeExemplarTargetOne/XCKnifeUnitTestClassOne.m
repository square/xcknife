//
//  XCKnifeUnitTestClassOne.m
//  XCKnifeExemplar
//
//  Created by Daniel Ribeiro on 5/30/16.
//  Copyright © 2016 XCknife. All rights reserved.
//

#import <XCTest/XCTest.h>

@interface XCKnifeUnitTestClassOne : XCTestCase

@end

@implementation XCKnifeUnitTestClassOne

- (void)testMethodOne {
    XCTAssert(YES, @"Passing testMethodOne");
}

@end
