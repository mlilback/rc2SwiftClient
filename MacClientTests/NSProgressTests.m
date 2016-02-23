//
//  NSProgressTests.m
//  SwiftClient
//
//  Created by Mark Lilback on 2/19/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "NSProgress+Rc2.h"

static int kvoKey = 0;

@interface NSProgressTests : XCTestCase
@property (nonatomic) NSInteger currentCount;
@property (nonatomic, strong) NSProgress *progress;
@end

@implementation NSProgressTests

- (void)setUp {
	[super setUp];
	self.progress = [NSProgress progressWithTotalUnitCount:10];
	[self.progress addObserver:self forKeyPath:@"completedUnitCount" options:0 context:&kvoKey];
}

- (void)tearDown {
	[self.progress removeObserver:self forKeyPath:@"completedUnitCount" context:&kvoKey];
	[super tearDown];
}

- (void)testProgress
{
	XCTestExpectation *expect = [self expectationWithDescription:@"progress"];
	[self.progress rc2_addCompletionHandler:^() {
		NSLog(@"completion called");
		[expect fulfill];
	}];
	self.progress.completedUnitCount = 5;
	XCTAssertEqual(self.currentCount, 5);
	self.progress.completedUnitCount = 10;
	[self.progress rc2_complete:nil];
	[self waitForExpectationsWithTimeout:2 handler:^(NSError * _Nullable error) {
	}];
	
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
	if (context == &kvoKey && [keyPath isEqualToString:@"completedUnitCount"]) {
		self.currentCount = [object completedUnitCount];
	} else {
		NSLog(@"weird kvo call");
	}
}
@end
