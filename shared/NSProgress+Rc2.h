//
//  NSProgress+Rc2.h
//  SwiftClient
//
//  Created by Mark Lilback on 2/18/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSProgress(Rc2)
@property (nonatomic, nullable, readonly) NSError *rc2_error;

//sets the error and sets the completedUnitCount equal to the totalUnitCount, which should fire a KVO for fractionCompleted
-(void)rc2_complete:(nullable NSError*) error;

-(void)rc2_addCompletionHandler:( void (^ _Nonnull )())handler;
@end
