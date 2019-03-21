//
//  Initialize.m
//  TestDumper
//
//  Created by Mike Lewis on 8/25/15.
//  Copyright (c) 2015 Square, Inc. All rights reserved.
//

@import Dispatch;
@import Foundation;
@import XCTest;

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

// Logging
FILE *logFile;

void initializeLogFile(const char *logFilePath)
{
    logFile = fopen(logFilePath, "w");
}

void logDebug(NSString *, ...) NS_FORMAT_FUNCTION(1, 2);
void logDebug(NSString *msg, ...)
{
    assert(logFile);
    va_list varargs;
    va_start(varargs, msg);
    msg = [[NSString alloc] initWithFormat:msg arguments:varargs];
    va_end(varargs);
    fprintf(logFile, "%s\n", msg.UTF8String);
    
    NSLog(@"%@", msg);
}

void logInit()
{
    logDebug(@"Starting TestDumper...");
    logDebug(@"Environment Variables:");
    logDebug(@"%@", NSProcessInfo.processInfo.environment.description);
    logDebug(@"Command Line Arguments:");
    logDebug(@"%@", NSProcessInfo.processInfo.arguments.description);
    
    logDebug(@"--------------------------------");
}

OS_NORETURN
void logEnd(Boolean success)
{
    int exitCode = success ? EXIT_SUCCESS : EXIT_FAILURE;
    logDebug(@"EndingTestDumper...\nExiting with status %d", exitCode);
    fclose(logFile);
    exit(exitCode);
}

// Used for a structured log, just like Xctool's.
// Example: https://github.com/square/xcknife/blob/master/example/xcknife-exemplar.json-stream
static void PrintJSON(FILE *outFile, id JSONObject)
{
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:JSONObject options:0 error:&error];

    if (error) {
        fprintf(outFile, "{ \"message\" : \"Error while serializing to JSON. Check out simulator logs for details\" }");
        logDebug(@"ERROR: Error generating JSON for object: %s: %s\n",
                [[JSONObject description] UTF8String],
                [[error localizedFailureReason] UTF8String]);
        logEnd(false);
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

void enumerateTests(NSString *);

const int TEST_TARGET_LEVEL = 0;
const int TEST_CLASS_LEVEL = 1;
const int TEST_METHOD_LEVEL = 2;
FILE *noteFile;

__attribute__((constructor))
void initialize() {
    NSLog(@"Starting TestDumper");
    const char *logFilePath = [[[NSProcessInfo processInfo] arguments][3] UTF8String];
    initializeLogFile(logFilePath);
    logInit();
    NSString *testBundlePath = [[NSProcessInfo processInfo] arguments][4];
    NSString *testDumperOutputPath = NSProcessInfo.processInfo.environment[@"TestDumperOutputPath"];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:testDumperOutputPath]) {
        logDebug(@"File already exists %@. Stopping", testDumperOutputPath);
        logEnd(true);
    }

    NSString *testType = [NSString stringWithUTF8String: getenv("XCTEST_TYPE")];
    if ([testType isEqualToString: @"APPTEST"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            enumerateTests(testBundlePath);
        }];
    } else {
        enumerateTests(testBundlePath);
    }
}

void enumerateTests(NSString *testBundlePath) {
    logDebug(@"Listing all test bundles");
    for (NSBundle *bundle in NSBundle.allBundles) {
        logDebug(@"Found a test bundle named: %@", bundle.bundlePath);
    }
    logDebug(@"Finished listing all test bundles");
    
    NSBundle* testBundleObj = [NSBundle bundleWithPath:testBundlePath];
    [testBundleObj load];
    logDebug(@"test bundle loaded");
    
    logDebug(@"Listing all test bundles");
    for (NSBundle *bundle in NSBundle.allBundles) {
        logDebug(@"Found a test bundle named: %@", bundle.bundlePath);
    }
    logDebug(@"Finished listing all test bundles");
    
    NSString *testType = [NSString stringWithUTF8String: getenv("XCTEST_TYPE")];
    NSString *testTarget = [[[testBundlePath componentsSeparatedByString:@"/"] lastObject] componentsSeparatedByString:@"."][0];
    
    logDebug(@"The test target is: %@ of type %@", testTarget, testType);
    
    FILE *outFile;
    NSString *testDumperOutputPath = NSProcessInfo.processInfo.environment[@"TestDumperOutputPath"];

    if (testDumperOutputPath == nil) {
        outFile = stdout;
    } else {
        outFile = fopen(testDumperOutputPath.UTF8String, "w+");
    }

    logDebug(@"Opened %@ with fd %p", testDumperOutputPath, outFile);
    if (outFile == NULL) {
        logDebug(@"File already exists at %@. Stopping", testDumperOutputPath);
        logEnd(true);
    }
    
    PrintDumpStart(outFile, testType);
    XCTestSuite* testSuite = [XCTestSuite defaultTestSuite];
    [testSuite printTestsWithLevel:0 withTarget: testTarget withParent: nil outputFile:outFile];
    PrintDumpEnd(outFile, testType);
    fclose(outFile);
    logEnd(true);
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
                logDebug(@"Unknown test level %ld for test %@", level, t.debugDescription);

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
