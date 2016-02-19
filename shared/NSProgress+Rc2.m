//
//  NSProgress+Rc2.m
//  SwiftClient
//
//  Created by Mark Lilback on 2/18/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

#import "NSProgress+Rc2.h"
#import <objc/runtime.h>
#import "KVObserver.h"

NSString* CompletionHandlerKey = @"rc2.completionHandler";
NSString* FractionTokenKey = @"rc.fractionToken";

@interface ProgressKVOProxy : NSObject
@property (nonatomic, nullable, weak) NSProgress *progress;
@property (nonatomic, strong) NSMutableSet *completionBlocks;
-(instancetype)initWithProgress:(NSProgress*)prog;
@end

@implementation ProgressKVOProxy
-(instancetype)initWithProgress:(NSProgress*)prog
{
	if ((self = [super init]))  {
		self.progress = prog;
		self.completionBlocks = [NSMutableSet set];
		[self.progress addObserver:self forKeyPath:@"completedUnitCount" options:NSKeyValueObservingOptionNew context:&CompletionHandlerKey];
	}
	return self;
}

-(void)dealloc
{
	[self.progress removeObserver:self forKeyPath:@"completedUnitCount"];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
	if (context == &CompletionHandlerKey && [keyPath isEqualToString:@"completedUnitCount"])
	{
		NSLog(@"fractionComplete changed %1.4f", [object fractionCompleted]);
		double fraction = [object fractionCompleted];
		if (fraction >= 1.0) {
			NSLog(@"calling progress completion handlers");
			for (dispatch_block_t block in self.completionBlocks) {
				dispatch_async(dispatch_get_main_queue(), block);
			}
			[self.completionBlocks removeAllObjects];
		}
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

-(void)addCompletionHandler:( void (^ _Nonnull )())handler
{
	dispatch_block_t block = [handler copy];
	[self.completionBlocks addObject:block];
}

@end

@implementation  NSProgress(Rc2)

-(NSError*)rc2_error
{
	return self.userInfo[@"rc2.error"];
}

-(void)setRc2_error:(NSError * _Nullable)error
{
	[self setUserInfoObject:error forKey:@"rc2.error"];
}

-(void)rc2_complete:(nullable NSError*) error
{
	[self setRc2_error:error];
	self.completedUnitCount = self.totalUnitCount;
}

-(ProgressKVOProxy*)rc2_proxy
{
	ProgressKVOProxy *proxy = self.userInfo[CompletionHandlerKey];
	if (nil == proxy) {
		proxy = [[ProgressKVOProxy alloc] initWithProgress:self];
		[self setUserInfoObject:proxy forKey:CompletionHandlerKey];
	}
	return proxy;
}

-(void)rc2_addCompletionHandler:( void (^ _Nonnull )())handler
{
	[[self rc2_proxy] addCompletionHandler:handler];
}

@end
