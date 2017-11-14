//
//  SearchBarField.m
//  Rc2Client
//
//  Created by Mark Lilback on 2/14/17.
//  Copyright © 2017 Rc2. All rights reserved.
//

#import "SearchBarField.h"

@interface NSSearchFieldCell (ApplePrivate)
//- (void)setCentersPlaceholder:(BOOL)fp8;
//- (BOOL)centersPlaceholder;
- (void)setCenteredLook:(BOOL)fp8;
@end

@implementation SearchBarField

- (void) awakeFromNib
{
	[super awakeFromNib];
//	NSSearchFieldCell *myCell = (NSSearchFieldCell*)self.cell;
//	id img = myCell.cancelButtonCell.image;
//	[myCell setCenteredLook:NO];
//	myCell.cancelButtonCell.image = img;
}
@end
