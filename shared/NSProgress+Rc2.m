//
//  NSProgress+Rc2.m
//  SwiftClient
//
//  Created by Mark Lilback on 2/18/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

#import "NSProgress+Rc2.h"
#import <objc/runtime.h>
#import "PMKVObserver/PMKVObserver.h"

NSString* CompletionHandlerKey = @"rc2.completionHandler";
NSString* FractionTokenKey = @"rc.fractionToken";

@interface ProgressKVOProxy : NSObject
@property (nonatomic, nullable, weak) NSProgress *progress;
@property (nonatomic, strong) NSMutableSet *completionBlocks;
-(instancetype)initWithProgress:(NSProgress*)prog;
@end

typedef  void (^ _Nonnull ProgressCompleteCallback)();

@implementation ProgressKVOProxy
-(instancetype)initWithProgress:(NSProgress*)prog
{
	if ((self = [super init]))  {
		self.progress = prog;
		self.completionBlocks = [NSMutableSet set];
	}
	return self;
}

-(void)progressComplete
{
	for (ProgressCompleteCallback block in self.completionBlocks) {
		dispatch_async(dispatch_get_main_queue(), ^{
			block(self);
		});
	}
	[self.completionBlocks removeAllObjects];
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
	[[self rc2_proxy] progressComplete];
}

-(ProgressKVOProxy*)rc2_proxy
{
	ProgressKVOProxy *proxy = objc_getAssociatedObject(self, &CompletionHandlerKey);
	if (nil == proxy) {
		proxy = [[ProgressKVOProxy alloc] initWithProgress:self];
		objc_setAssociatedObject(self, &CompletionHandlerKey, proxy, OBJC_ASSOCIATION_RETAIN);
	}
	return proxy;
}

-(void)rc2_addCompletionHandler:(ProgressCompleteCallback)handler
{
	[[self rc2_proxy] addCompletionHandler:handler];
}

@end
