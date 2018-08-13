//
//  Initialize.m
//  TestDumper
//
//  Created by Mike Lewis on 8/25/15.
//  Copyright (c) 2015 Square, Inc. All rights reserved.
//

@import Dispatch;
@import XCTest;




@class NSSet, NSString, NSURL, NSUUID;

@interface XCTestConfiguration : NSObject <NSSecureCoding>
{
    NSURL *_testBundleURL;
    NSSet *_testsToSkip;
    NSSet *_testsToRun;
    BOOL _reportResultsToIDE;
    NSUUID *_sessionIdentifier;
    NSString *_pathToXcodeReportingSocket;
    BOOL _disablePerformanceMetrics;
    BOOL _treatMissingBaselinesAsFailures;
    NSURL *_baselineFileURL;
    NSString *_targetApplicationPath;
    NSString *_targetApplicationBundleID;
    NSString *_productModuleName;
    BOOL _reportActivities;
    BOOL _testsMustRunOnMainThread;
}

+ (id)configurationWithContentsOfFile:(id)arg1;
+ (id)activeTestConfiguration;
+ (void)setActiveTestConfiguration:(id)arg1;
+ (BOOL)supportsSecureCoding;
@property BOOL testsMustRunOnMainThread; // @synthesize testsMustRunOnMainThread=_testsMustRunOnMainThread;
@property BOOL reportActivities; // @synthesize reportActivities=_reportActivities;
@property(copy) NSString *productModuleName; // @synthesize productModuleName=_productModuleName;
@property(copy) NSString *targetApplicationBundleID; // @synthesize targetApplicationBundleID=_targetApplicationBundleID;
@property(copy) NSString *targetApplicationPath; // @synthesize targetApplicationPath=_targetApplicationPath;
@property BOOL treatMissingBaselinesAsFailures; // @synthesize treatMissingBaselinesAsFailures=_treatMissingBaselinesAsFailures;
@property BOOL disablePerformanceMetrics; // @synthesize disablePerformanceMetrics=_disablePerformanceMetrics;
@property BOOL reportResultsToIDE; // @synthesize reportResultsToIDE=_reportResultsToIDE;
@property(copy) NSURL *baselineFileURL; // @synthesize baselineFileURL=_baselineFileURL;
@property(copy) NSString *pathToXcodeReportingSocket; // @synthesize pathToXcodeReportingSocket=_pathToXcodeReportingSocket;
@property(copy) NSUUID *sessionIdentifier; // @synthesize sessionIdentifier=_sessionIdentifier;
@property(copy) NSSet *testsToSkip; // @synthesize testsToSkip=_testsToSkip;
@property(copy) NSSet *testsToRun; // @synthesize testsToRun=_testsToRun;
@property(copy) NSURL *testBundleURL; // @synthesize testBundleURL=_testBundleURL;
- (BOOL)isEqual:(id)arg1;
- (unsigned long long)hash;
- (id)description;
- (BOOL)writeToFile:(id)arg1;
- (void)encodeWithCoder:(id)arg1;
- (id)initWithCoder:(id)arg1;
- (id)init;
- (void)dealloc;

@end



@interface XCTestSuite (DumpAdditions)

- (void)printTestsWithLevel:(NSInteger)level withTarget:(NSString*) target withParent:(NSString*) parent  outputFile:(FILE *)outputFile;

@end

#include <dlfcn.h>


// Used for a structured log, just like Xctool's.
// Example: https://github.com/square/xcknife/blob/master/example/xcknife-exemplar.json-stream
static void PrintJSON(FILE *outFile, id JSONObject)
{
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:JSONObject options:0 error:&error];

    if (error) {
        fprintf(outFile, "{ \"message\" : \"Error while serializing to JSON. Check out simulator logs for details\" }");
        NSLog(@"ERROR: Error generating JSON for object: %s: %s\n",
                [[JSONObject description] UTF8String],
                [[error localizedFailureReason] UTF8String]);
        exit(1);
    }

    fwrite([data bytes], 1, [data length], outFile);
    fprintf(outFile, "\n");
}

static void PrintDumpStart(FILE *outFile, NSString *testType) {
    PrintJSON(outFile, @{@"message" : @"Starting Test Dumper",
                         @"testType" : testType,
                         @"event": @"begin-test-suite"});
}

static void PrintDumpEnd(FILE *outFile, NSString *testType) {
    PrintJSON(outFile, @{@"message" : @"Completed Test Dumper",
                         @"testType" : testType,
                         @"event": @"end-action"});
}

static void PrintTestTarget(FILE *outFile, NSString *targetName, NSString *bundleName) {
    PrintJSON(outFile, @{@"event" : @"begin-ocunit", @"bundleName" : bundleName, @"targetName" : targetName});
}

static void PrintTestClass(FILE *outFile, NSString *testClass) {
    PrintJSON(outFile, @{@"className" : testClass,
                         @"test" : @"1",
                         @"event" : @"end-test",
                         @"totalDuration" : @"0"});
}

void enumerateTests();

const int TEST_TARGET_LEVEL = 0;
const int TEST_CLASS_LEVEL = 1;
const int TEST_METHOD_LEVEL = 2;
FILE *noteFile;

static void debugLog(NSString* message) {
    fprintf(noteFile, message.UTF8String);
    fprintf(noteFile, "\n");
}
__attribute__((constructor))
void initialize() {
    noteFile = fopen("/tmp/testdumper.log", "w");
    fprintf(noteFile, "Starting test dumper!\n");
    NSLog(@"Starting TestDumper");
    NSString *testDumperOutputPath = NSProcessInfo.processInfo.environment[@"TestDumperOutputPath"];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:testDumperOutputPath]) {
        NSLog(@"File already exists %@. Stopping", testDumperOutputPath);
        exit(0);
    }
    NSString *testType = [NSString stringWithUTF8String: getenv("XCTEST_TYPE")];

    if ([testType isEqualToString: @"APPTEST"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            enumerateTests();
        }];
    } else {
        enumerateTests();
    }
}

void enumerateTests() {
    debugLog(@"printing arguments");
    for (NSString* argument in NSProcessInfo.processInfo.arguments) {
        if ([argument hasSuffix:@".xctest"]) {
            debugLog(argument);
        }
    }

    debugLog(@"Listing all test bundles");
    for (NSBundle *bundle in NSBundle.allBundles) {
        NSString *string = [@"Found a test bundle named: " stringByAppendingString:bundle.bundlePath];
        debugLog(string);
    }
    debugLog(@"Finished listing all test bundles");
    
    NSString *testBundle = [[[NSProcessInfo processInfo] arguments] lastObject];
    NSBundle* testBundleObj = [NSBundle bundleWithPath:testBundle];
    [testBundleObj load];
    debugLog(@"test bundle loaded");
    
    debugLog(@"Listing all test bundles");
    for (NSBundle *bundle in NSBundle.allBundles) {
        NSString *string = [@"Found a test bundle named: " stringByAppendingString:bundle.bundlePath];
        debugLog(string);
    }
    debugLog(@"Finished listing all test bundles");
    
    //XCTestConfiguration *config = [[XCTestConfiguration alloc] init];
    NSString *testType = [NSString stringWithUTF8String: getenv("XCTEST_TYPE")];
    //NSString *testTarget = [NSString stringWithUTF8String: getenv("XCTEST_TARGET")];
    NSString *testTarget = [[[testBundle componentsSeparatedByString:@"/"] lastObject] componentsSeparatedByString:@"."][0];
    
    debugLog(@"The test target is:");
    debugLog(testTarget);
    if ([testType isEqualToString: @"APPTEST"]) {
        debugLog(@"IS APPTEST");
        //        config.testBundleURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.environment[@"XCInjectBundle"]];
        //        config.targetApplicationPath = NSProcessInfo.processInfo.environment[@"XCInjectBundleInto"];
        //
        //        NSString *configPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%ul.xctestconfiguration", arc4random()]];
        //
        //        NSLog(@"Writing config to %@", configPath);
        //
        //        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:config];
        //
        //        [data writeToFile:configPath atomically:true];
        //
        //        setenv("XCTestConfigurationFilePath", configPath.UTF8String, YES);
        
        //dlopen(getenv("IDE_INJECTION_PATH"), RTLD_GLOBAL);
        
        debugLog(@"not doing dlopen anymore");
    }
    
    FILE *outFile;
    NSString *testDumperOutputPath = NSProcessInfo.processInfo.environment[@"TestDumperOutputPath"];
    
    if (testDumperOutputPath == nil) {
        outFile = stdout;
    } else {
        outFile = fopen(testDumperOutputPath.UTF8String, "w+");
    }
    
    NSLog(@"Opened %@ with fd %p", testDumperOutputPath, outFile);
    if (outFile == NULL) {
        debugLog(@"File already exists. Stopping");
        NSLog(@"File already exists %@. Stopping", testDumperOutputPath);
        exit(0);
    }
    
    PrintDumpStart(outFile, testType);
    XCTestSuite* testSuite = [XCTestSuite defaultTestSuite];
    [testSuite printTestsWithLevel:0 withTarget: testTarget withParent: nil outputFile:outFile];
    PrintDumpEnd(outFile, testType);
    fclose(outFile);
    exit(0);
}


// This test enumerates the Xctest classes and targets, in the json-stream format. We only enumerate the first test method,
// since xcknife does use test method level information (ref: https://github.com/square/xcknife)
@implementation XCTestSuite (DumpAdditions)

- (void)printTestsWithLevel:(NSInteger)level withTarget:(NSString*) target withParent:(NSString*) parent  outputFile:(FILE *)outputFile;
{

    for (XCTest *t in self.tests) {
        switch (level) {
            case TEST_TARGET_LEVEL :
                PrintTestTarget(outputFile, target, t.name);
                break;
            case TEST_METHOD_LEVEL:
                PrintTestClass(outputFile, parent);
                break;
            case TEST_CLASS_LEVEL:
                // nothing to do here
                break;
            default:
                NSLog(@"Uknown level %ld", level);

        }
        if (level == TEST_METHOD_LEVEL) {
            break;
        }
        if ([t isKindOfClass:[XCTestSuite class]]) {
            [(XCTestSuite *)t printTestsWithLevel: (level + 1) withTarget: target withParent: t.name outputFile:outputFile];
        }
    }
}

@end
