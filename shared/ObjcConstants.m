//
//  ObjcConstants.h
//  SwiftClient
//
//  Created by Mark Lilback on 7/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

#import "ObjcConstants.h"

//#define FOO "$HOCKEY_IDENTIFIER"
//#define STRINGIZE(x) #x
//#define STRINGIZE2(x) STRINGIZE(x)
//#define FOOLITERAL @ STRINGIZE2(FOO)

#if HOCKEYAPP_ENABLED
NSString* const kHockeyAppIdentifier = HOCKEY_IDENTIFIER;
#else
NSString* const kHockeyAppIdentifier = @"";
#endif

