//
//  ObjcConstants.h
//  Rc2Client
//
//  Created by Mark Lilback on 7/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

#ifndef ObjcConstants_h
#define ObjcConstants_h

#import <Foundation/Foundation.h>

#ifdef HOCKEYAPP_ENABLED
extern NSString* const kHockeyAppIdentifier;
#else
extern NSString* const kHockeyAppIdentifier;
#endif


#endif /* ObjcConstants_h */
