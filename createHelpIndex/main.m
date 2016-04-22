//
//  main.m
//  createHelpIndex
//
//  Created by Mark Lilback on 4/20/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMDB.h"

NSArray<NSString*>* findJsonFiles(NSString *srcPath, NSString *destPath);
void addJsonFile(NSString *filePath, FMDatabase *db);

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		if (argc != 3) {
			NSLog(@"invalid arguments");
			abort();
		}
		NSString *srcDir = [NSString stringWithUTF8String:argv[1]];
		NSString *destDir = [NSString stringWithUTF8String:argv[2]];
		NSArray<NSString*> *files = findJsonFiles(srcDir, destDir);
		NSString *dbPath = [NSString stringWithFormat:@"%@/helpindex.db", destDir];
		[[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];
		FMDatabase *db = [FMDatabase databaseWithPath:dbPath];
		if (![db open]) {
			NSLog(@"failed to open output db");
			abort();
		}
		[db executeUpdate:@"drop table helpidx"];
		if (![db executeUpdate:@"create virtual table helpidx using fts4(package,name,title,desc, tokenize=porter)"]) {
			NSLog(@"failed to create table");
			abort();
		}
		[db executeUpdate:@"drop table helptopic"];
		if (![db executeUpdate:@"create table helptopic (package, name, title, desc)"]) {
			NSLog(@"failed to create topic table");
			abort();
		}
		for (NSString *aFile in files) {
			addJsonFile(aFile, db);
		}
		
		[db close];
	}
	return 0;
}

void
addJsonFile(NSString *filePath, FMDatabase *db)
{
	NSData *data = [NSData dataWithContentsOfFile:filePath];
	NSError *err;
	NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
	if (err) {
		NSLog(@"failed to parse '%@'", filePath);
		return;
	}
	NSString *query = @"insert into helpidx values (?, ?, ?, ?)";
	NSString *query2 = @"insert into helptopic values (?, ?, ?, ?)";
	NSArray *topics = (NSArray*)[dict objectForKey:@"help"];
	[db beginTransaction];
	for (NSDictionary *aTopic in topics) {
		[db executeUpdate:query, aTopic[@"package"], aTopic[@"name"], aTopic[@"title"], aTopic[@"desc"]];
		[db executeUpdate:query2, aTopic[@"package"], aTopic[@"name"], aTopic[@"title"], aTopic[@"desc"]];
	}
	[db commit];
}

NSArray<NSString*>*
findJsonFiles(NSString *srcPath, NSString *destPath)
{
	NSFileManager *fm = [[NSFileManager alloc] init];
	NSError *err;
	NSArray *files = [fm contentsOfDirectoryAtPath:srcPath error:&err];
	if (err) {
		NSLog(@"error reading source directory %@", err);
		abort();
	}
	NSMutableArray *paths = [NSMutableArray array];
	for (NSString *aFile in files) {
		if ([[aFile pathExtension] isEqualToString:@"json"])
			[paths addObject:[NSString stringWithFormat:@"%@/%@", srcPath, aFile]];
	}
	return paths;
}

