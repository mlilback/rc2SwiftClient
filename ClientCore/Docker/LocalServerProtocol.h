//
//  LocalServerProtocol.h
//  SwiftClient
//
//  Created by Mark Lilback on 9/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

#ifndef LocalServerProtocol_h
#define LocalServerProtocol_h

@import Foundation;

typedef void(^SimpleServerCallback)(BOOL success, NSError * _Nullable error);

@protocol LocalServerProtocol <NSObject>

	-(void)initializeConnection:(nullable NSString*) url handler:(nonnull SimpleServerCallback) handler;
	
	-(void)checkForUpdates:(nonnull NSString*)baseUrl requiredVersion:(NSInteger)version handler:(nonnull SimpleServerCallback)handler;

@end

#endif /* LocalServerProtocol_h */
