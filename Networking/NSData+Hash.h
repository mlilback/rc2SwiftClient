//
//  NSData+Hash.h
//  Networking
//
//  Created by Mark Lilback on 6/22/17.
//  Copyright © 2017 Rc2. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (Hash)
- (NSData * _Nonnull)sha1hash;
- (NSData * _Nonnull)sha256;
@end
