//
//  NSData+Hash.m
//  Networking
//
//  Created by Mark Lilback on 6/22/17.
//  Copyright © 2017 Rc2. All rights reserved.
//

#import "NSData+Hash.h"
#import <CommonCrypto/CommonHMAC.h>

@implementation NSData (Hash)
- (NSData *)sha1hash {
	
	NSData *keyData = [@"SampleSecretKey012345678" dataUsingEncoding:NSUTF8StringEncoding];
	NSMutableData *hMacOut = [NSMutableData dataWithLength:CC_SHA1_DIGEST_LENGTH];
	
	CCHmac(kCCHmacAlgSHA1,
		   keyData.bytes, keyData.length,
		   self.bytes,    self.length,
		   hMacOut.mutableBytes);
	
	return [hMacOut copy];
}

- (NSData *)sha256 {
	
	NSData *keyData = [@"SampleSecretKey012345678" dataUsingEncoding:NSUTF8StringEncoding];
	NSMutableData *hMacOut = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
	
	CCHmac(kCCHmacAlgSHA256,
		   keyData.bytes, keyData.length,
		   self.bytes,    self.length,
		   hMacOut.mutableBytes);
	
	return [hMacOut copy];
}
@end
