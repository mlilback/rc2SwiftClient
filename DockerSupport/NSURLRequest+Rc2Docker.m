//
//  NSURLRequest+Rc2Docker.m
//  SwiftClient
//
//  Created by Mark Lilback on 10/29/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

#import "NSURLRequest+Rc2Docker.h"

static NSString * const chunkedKey = @"rc2_chunked_response";

@implementation  NSURLRequest (Rc2Docker)
- (BOOL) rc2_chunkedResponse
{
	id val = [NSURLProtocol propertyForKey:chunkedKey inRequest:self];
	if ([val respondsToSelector:@selector(boolValue)]) {
		return [val boolValue];
	}
	return NO;
}

- (void) setRc2_chunkedResponse:(BOOL)isChunked
{
	if (![self isKindOfClass:[NSMutableURLRequest class]]) {
		NSLog(@"setChunkedResponse called on non-mutable URLRequest");
		exit(1);
	}
	NSMutableURLRequest *req = (NSMutableURLRequest*)self;
	[NSURLProtocol setProperty:[NSNumber numberWithBool:isChunked] forKey: chunkedKey inRequest:req];
	NSLog(@"set prop");
	assert(self.rc2_chunkedResponse == isChunked);
}
@end
