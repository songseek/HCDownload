/*
 * HCDownloadViewController.m
 * HCDownload
 *
 * Created by Árpád Goretity on 25/07/2012.
 * Licensed under the 3-clause BSD License
 */

#import <QuartzCore/QuartzCore.h>
#import "HCDownloadViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <Gremlin/Gremlin.h>

/*
 * User info keys for internal use
 */
#define kHCDownloadKeyURL @"URL"
#define kHCDownloadKeyStartTime @"startTime"
#define kHCDownloadKeyTotalSize @"totalSize"
#define kHCDownloadKeyConnection @"connection"
#define kHCDownloadKeyFileHandle @"fileHandle"
#define kHCDownloadKeyUserInfo @"userInfo"

/*
 * Private methods
 */
@interface HCDownloadViewController () <GremlinListener,UIActionSheetDelegate>
- (void)removeURL:(NSURL *)url;
- (void)removeURLAtIndex:(NSInteger)index;
- (void)setupCell:(HCDownloadCell *)cell withAttributes:(NSDictionary *)attr;
- (void)cancelDownloadingURLAtIndex:(NSInteger)index;
@end

@implementation HCDownloadViewController

@synthesize downloadDirectory;
@synthesize delegate;

static HCDownloadViewController *sharedInstance = nil;

/* @name Singleton Methods */

+(HCDownloadViewController *)sharedInstance
{
	static dispatch_once_t pred;
	dispatch_once(&pred, ^{
        
        sharedInstance = [[self alloc] init];
	}
	              );
    
	return sharedInstance;
}


- (id)init
{
	return [self initWithStyle:UITableViewStylePlain];
}

- (id)initWithStyle:(UITableViewStyle)style
{
	if ((self = [super initWithStyle:style]))
    {
        [Gremlin registerNotifications:self];
		downloads = [[NSMutableArray alloc] init];
        files = [[NSMutableArray alloc] init];
		self.downloadDirectory = @"/var/mobile/media/Downloads";
		self.title = NSLocalizedString(@"Downloads", nil);
	}
	return self;
}

-(void)viewDidLoad
{
    [super viewDidLoad];
    [self enumerateDownloadsDirectory];
}

- (void)dealloc
{
	// Cancel all downloads in progress
	[self.tableView beginUpdates];
	while (downloads.count > 0) {
		[self removeURLAtIndex:0];
	}

	[self.tableView endUpdates];

	[downloads release];
	self.downloadDirectory = nil;
    
    [files removeAllObjects];
    [files release];
    
	[super dealloc];
}

/* Refresh list of files in save directory */
-(void)enumerateDownloadsDirectory
{
	NSDirectoryEnumerator *dirEnum = [[ NSFileManager defaultManager ] enumeratorAtPath:self.downloadDirectory];
    
	NSString *file;
    [self.tableView beginUpdates];
	while (file = [dirEnum nextObject])
	{
        
		BOOL isDirectory;
		if (![file hasPrefix:@"."] &&
            [[NSFileManager defaultManager] fileExistsAtPath:[self.downloadDirectory stringByAppendingPathComponent:file] isDirectory:&isDirectory] &&
            [[[file pathExtension] lowercaseString] isEqualToString:@"mp3"])
		{
            
			if (isDirectory)
			{
				NSMutableDictionary *dir = [[NSMutableDictionary alloc] initWithObjects:[NSArray arrayWithObjects:
                                                                                         [self.downloadDirectory stringByAppendingPathComponent:file],
                                                                                         [NSNumber numberWithBool:TRUE],
                                                                                         nil]
                                                                                forKeys:[NSArray arrayWithObjects:
                                                                                         @"file",
                                                                                         @"isDir",
                                                                                         nil]];
				[files addObject:dir];
				[dirEnum skipDescendents];
			}
			else
			{
				NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:
                                                [self.downloadDirectory stringByAppendingPathComponent:file]
                                                                                                error:nil];
				NSMutableDictionary *tFile = [[NSMutableDictionary alloc] initWithObjects:[NSArray arrayWithObjects:
                                                                                           [self.downloadDirectory stringByAppendingPathComponent:file],
                                                                                           [fileAttributes objectForKey:NSFileSize],
                                                                                           [NSNumber numberWithBool:NO],
                                                                                           nil]
                                                                                  forKeys:[NSArray arrayWithObjects:
                                                                                           @"file",
                                                                                           @"size",
                                                                                           @"isDir", nil]];
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:files.count inSection:1];
                [files addObject: tFile];
                [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationBottom];
			}
		}
	}
     [self.tableView endUpdates];
    
	//NSSortDescriptor *aSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"file" ascending:YES selector:@selector(caseInsensitiveCompare:)];
	//[files sortUsingDescriptors:[NSArray arrayWithObject:aSortDescriptor]];
    
	//[self.tableView reloadData];
    
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o
{
	return o = UIInterfaceOrientationPortrait;
}

- (NSInteger)numberOfDownloads
{
	return downloads.count;
}

- (void)close
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

-(void)updateTabBarBadgeValue
{
    [self.tabBarItem setBadgeValue:[NSString stringWithFormat:@"%i", downloads.count]];
}

- (void)downloadURL:(NSURL *)url userInfo:(NSDictionary *)userInfo
{
	NSURLRequest *rq = [NSURLRequest requestWithURL:url];
	NSURLConnection *conn = [NSURLConnection connectionWithRequest:rq delegate:self];

	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	[dict setObject:url forKey:kHCDownloadKeyURL];
	[dict setObject:conn forKey:kHCDownloadKeyConnection];
	if (userInfo != nil) {
		[dict setObject:userInfo forKey:kHCDownloadKeyUserInfo];
	}

	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:downloads.count inSection:0];
	[downloads addObject:dict];
	NSArray *paths = [NSArray arrayWithObject:indexPath];
	[self.tableView insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationRight];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    [self updateTabBarBadgeValue];
}

- (void)cancelDownloadingURLAtIndex:(NSInteger)index;
{
	NSMutableDictionary *dict = [downloads objectAtIndex:index];
	NSDictionary *userInfo = [[dict objectForKey:kHCDownloadKeyUserInfo] retain];
	NSURL *url = [[dict objectForKey:kHCDownloadKeyUserInfo] retain];
	[self removeURLAtIndex:index];

	if ([self.delegate respondsToSelector:@selector(downloadController:failedDownloadingURL:withError:userInfo:)]) {
		NSError *error = [NSError errorWithDomain:kHCDownloadErrorDomain code:kHCDownloadErrorCodeCancelled userInfo:nil];
		[self.delegate downloadController:self failedDownloadingURL:url withError:error userInfo:userInfo];
	}

	[userInfo release];
	[url release];
}

- (void)removeURL:(NSURL *)url
{
	NSInteger index = -1;
	NSDictionary *d;
	for (d in downloads) {
		NSURL *otherUrl = [d objectForKey:kHCDownloadKeyURL];
		if ([otherUrl isEqual:url]) {
			index = [downloads indexOfObject:d];
			break;
		}
	}

	if (index != -1) {
		[self removeURLAtIndex:index];
	}
}

- (void)removeURLAtIndex:(NSInteger)index
{
	NSDictionary *dict = [downloads objectAtIndex:index];

	NSURLConnection *conn = [dict objectForKey:kHCDownloadKeyConnection];
	[conn cancel];

	NSFileHandle *fileHandle = [dict objectForKey:kHCDownloadKeyFileHandle];
	[fileHandle closeFile];

	[downloads removeObjectAtIndex:index];
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
	NSArray *paths = [NSArray arrayWithObject:indexPath];
	[self.tableView deleteRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationRight];
	
	if (downloads.count == 0) {
		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	}
    
    [self updateTabBarBadgeValue];
}


- (void)setupFileCell:(UITableViewCell *)cell withAttributes:(NSDictionary *)dict
{
    NSString *filePath =  [dict objectForKey:@"file"];
    cell.textLabel.text = [filePath lastPathComponent];
    
    double size = [[dict objectForKey:@"size"] doubleValue]/1048576.00f;
    [[cell detailTextLabel] setText:[NSString stringWithFormat:@"%.02f Mb",size]];
}

- (void)setupCell:(HCDownloadCell *)cell withAttributes:(NSDictionary *)dict
{
	NSDictionary *userInfo = [dict objectForKey:kHCDownloadKeyUserInfo];
	NSString *title =  [userInfo objectForKey:kHCDownloadKeyTitle];
	if (title == nil) title = [dict objectForKey:kHCDownloadKeyFileName];
	if (title == nil) title = NSLocalizedString(@"Downloading...", nil);
	cell.textLabel.text = title;
	cell.imageView.image = [userInfo objectForKey:kHCDownloadKeyImage];

	// Calculate the progress
	NSFileHandle *fileHandle = [dict objectForKey:kHCDownloadKeyFileHandle];
	if (fileHandle != nil) {
		unsigned long long downloaded = [fileHandle offsetInFile];
		NSDate *startTime = [dict objectForKey:kHCDownloadKeyStartTime];
		unsigned long long total = [[dict objectForKey:kHCDownloadKeyTotalSize] unsignedLongLongValue];

		NSTimeInterval dt = -1 * [startTime timeIntervalSinceNow];
		float speed = downloaded / dt;
		unsigned long long remaining = total - downloaded;
		int remainingTime = (int)(remaining / speed);
		int hours = remainingTime / 3600;
		int minutes = (remainingTime - hours * 3600) / 60;
		int seconds = remainingTime - hours * 3600 - minutes * 60;

		float downloadedF, totalF;
		char prefix;
		if (total >= 1024 * 1024 * 1024) {
			downloadedF = (float)downloaded / (1024 * 1024 * 1024);
			totalF = (float)total / (1024 * 1024 * 1024);
			prefix = 'G';
		} else if (total >= 1024 * 1024) {
			downloadedF = (float)downloaded / (1024 * 1024);
			totalF = (float)total / (1024 * 1024);
			prefix = 'M';
		} else if (total >= 1024) {
			downloadedF = (float)downloaded / 1024;
			totalF = (float)total / 1024;
			prefix = 'k';
		} else {
			downloadedF = (float)downloaded;
			totalF = (float)total;
			prefix = '\0';
		}

		// float speedNorm = downloadedF / dt;
		NSString *subtitle = [[NSString alloc] initWithFormat:@"%.2f of %.2f %cB, %02d:%02d:%02d remaining\n \n",
			downloadedF, totalF, prefix, hours, minutes, seconds];
		cell.detailTextLabel.text = subtitle;
		cell.progress = downloadedF / totalF;
		[subtitle release];
	} else {
		cell.detailTextLabel.text = nil;
	}
}

// UITableViewDelegate, UITableViewDataSource

-(NSInteger)countForSection:(NSInteger)section
{
    switch (section) {
        case 0:
            return downloads.count;
            break;
        default:
            return files.count;
            break;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self countForSection:section];
	
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0)
    {
        HCDownloadCell *cell = (HCDownloadCell *)[tableView dequeueReusableCellWithIdentifier:kHCDownloadCellID];
        if (cell == nil) {
            cell = [HCDownloadCell cell];
        }
        
        NSMutableDictionary *dict = [downloads objectAtIndex:indexPath.row];
        [self setupCell:cell withAttributes:dict];
        
        return cell;
    }
    
    UITableViewCell *cell = (UITableViewCell *)[tableView dequeueReusableCellWithIdentifier:kHCFileCellID];
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kHCFileCellID];
	}
    
	NSMutableDictionary *dict = [files objectAtIndex:indexPath.row];
	[self setupFileCell:cell withAttributes:dict];
    
	return cell;
	
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	cell.imageView.layer.cornerRadius = 7.5f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return kHCDownloadCellHeight;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Handle delete action initiated by the user
	if (style == UITableViewCellEditingStyleDelete)
    {
		if (indexPath.section == 0)
        {
			[self cancelDownloadingURLAtIndex:indexPath.row];
		}
        else if (indexPath.section == 1)
        {
            [tableView beginUpdates];
            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            
            NSDictionary *dict = [files objectAtIndex:indexPath.row];
            NSString *filePath = [dict objectForKey:@"file"];
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            [fileManager removeItemAtPath:filePath error:nil];
            [files removeObjectAtIndex:indexPath.row];
            [tableView endUpdates];
        }
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    
	if(section == 0)
    {
        return @"Transfers";
    }
	else
	{
		return self.downloadDirectory;
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if(indexPath.section == 1)
	{
		selectedRow = indexPath.row;
		NSDictionary *dict = [files objectAtIndex:indexPath.row];
        NSString *filePath = [dict valueForKey:@"file"];
        if ([[[filePath lowercaseString] pathExtension] isEqualToString:@"mp3"])
        {
            UIActionSheet *playSheet = [[UIActionSheet alloc] initWithTitle:@"Options" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Play",@"Add To iPod",nil];
            
            [playSheet setActionSheetStyle:UIActionSheetStyleBlackTranslucent];
            [playSheet showInView:[[SharedDelegate tabBarController] view]];
        }
	}
}

// NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)conn didReceiveResponse:(NSURLResponse *)resp
{
	// Search for the connection in all downloads
	NSMutableDictionary *dict;
	for (dict in downloads) {
		NSURLConnection *otherConn = [dict objectForKey:kHCDownloadKeyConnection];
		if ([otherConn isEqual:conn]) { // found the connection
			// If no default filename is provided, use the suggested one
			NSDictionary *userInfo = [dict objectForKey:kHCDownloadKeyUserInfo];
			NSString *fileName = [userInfo objectForKey:kHCDownloadKeyFileName];
			if (fileName == nil) {
				fileName = [resp suggestedFilename];
			}
			
			// Create the file to be written
			NSString *path = [self.downloadDirectory stringByAppendingPathComponent:fileName];
			[[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
			NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
			[dict setObject:fileName forKey:kHCDownloadKeyFileName];
			[dict setObject:fileHandle forKey:kHCDownloadKeyFileHandle];

			long long length = [resp expectedContentLength];
			if (length != NSURLResponseUnknownLength) {
				NSNumber *totalSize = [NSNumber numberWithUnsignedLongLong:(unsigned long long)length];
				[dict setObject:totalSize forKey:kHCDownloadKeyTotalSize];
			}

			// Set the start time in order to be able to calculate
			// an approximate remaining time
			[dict setObject:[NSDate date] forKey:kHCDownloadKeyStartTime];

			// Notify the delegate
			if ([self.delegate respondsToSelector:@selector(downloadController:startedDownloadingURL:userInfo:)]) {
				NSURL *url = [dict objectForKey:kHCDownloadKeyURL];
				[self.delegate downloadController:self startedDownloadingURL:url userInfo:userInfo];
			}

			// Refresh the table view
			[self.tableView reloadData];
			break;
		}
	}
}

- (void)connection:(NSURLConnection *)conn didReceiveData:(NSData *)data
{
	NSMutableDictionary *dict;
	for (dict in downloads) {
		NSURLConnection *otherConn = [dict objectForKey:kHCDownloadKeyConnection];
		if ([otherConn isEqual:conn]) {
			NSFileHandle *fileHandle = [dict objectForKey:kHCDownloadKeyFileHandle];
			[fileHandle writeData:data];
		
			// Update the corresponding table view cell
			NSInteger row = [downloads indexOfObject:dict];
			NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
			HCDownloadCell *cell = (HCDownloadCell *)[self.tableView cellForRowAtIndexPath:indexPath];
			
			[self setupCell:cell withAttributes:dict];
			
			// Notify the delegate
			if ([self.delegate respondsToSelector:@selector(downloadController:dowloadedFromURL:progress:userInfo:)]) {
				NSURL *url = [dict objectForKey:kHCDownloadKeyURL];
				NSDictionary *userInfo = [dict objectForKey:kHCDownloadKeyUserInfo];
				unsigned long long totalSize = [(NSNumber *)[dict objectForKey:kHCDownloadKeyTotalSize] unsignedLongLongValue];
				unsigned long long downloadSize = [fileHandle offsetInFile];
				float progress = (float)downloadSize / totalSize;
				[self.delegate downloadController:self dowloadedFromURL:url progress:progress userInfo:userInfo];
			}
			break;
		}
	}
}

- (void)connectionDidFinishLoading:(NSURLConnection *)conn
{
	NSInteger index = -1;
	NSMutableDictionary *d = nil;
	NSMutableDictionary *dict;
	
	// Search for the download context dictionary
	for (dict in downloads) {
		NSURLConnection *otherConn = [dict objectForKey:kHCDownloadKeyConnection];
		if ([otherConn isEqual:conn]) {
			d = [dict retain];
			index = [downloads indexOfObject:dict];
			break;
		}
	}

	// Clen up
	if (index != -1) {
		[self removeURLAtIndex:index];
		if ([self.delegate respondsToSelector:@selector(downloadController:finishedDownloadingURL:toFile:userInfo:)]) {
			NSString *fileName = [d objectForKey:kHCDownloadKeyFileName];
			NSURL *url = [d objectForKey:kHCDownloadKeyURL];
			NSDictionary *userInfo = [d objectForKey:kHCDownloadKeyUserInfo];
			[self.delegate downloadController:self finishedDownloadingURL:url toFile:fileName userInfo:userInfo];
		}
        [self enumerateDownloadsDirectory];
	}

	[d release];
}

- (void)connection:(NSURLConnection *)conn didFailLoadWithError:(NSError *)error
{
	NSInteger index = -1;
	NSMutableDictionary *d = nil;
	NSMutableDictionary *dict;
	
	// Search for the download context dictionary
	for (dict in downloads) {
		NSURLConnection *otherConn = [dict objectForKey:kHCDownloadKeyConnection];
		if ([otherConn isEqual:conn]) {
			d = [dict retain];
			index = [downloads indexOfObject:dict];
			break;
		}
	}

	// Clean up
	if (index != -1) {
		[self removeURLAtIndex:index];
		NSURL *url = [[d objectForKey:kHCDownloadKeyURL] retain];
		NSDictionary *userInfo = [d objectForKey:kHCDownloadKeyUserInfo];

		if ([self.delegate respondsToSelector:@selector(downloadController:failedDownloadingURL:withError:userInfo:)]) {
			[self.delegate downloadController:self failedDownloadingURL:url withError:error userInfo:userInfo];
		}
	}

	[d release];
}

#pragma makr - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (selectedRow <= ([files count]-1))
    {
        //@"Play",@"Add To iPod"
        NSDictionary *dict = [files objectAtIndex:selectedRow];
        NSString *filePath = [dict valueForKey:@"file"];
        if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"Play"])
        {
            //To-Do switch to modal AVController....I got lazy
            MPMoviePlayerViewController *audioPlayer = [[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL fileURLWithPath:filePath]];
            [[SharedDelegate tabBarController] presentMoviePlayerViewControllerAnimated:audioPlayer];
            
        } else if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"Add To iPod"])
        {
            [self importFileAtPath:filePath];
        }
    }
}

#pragma mark - iPod Import
-(void)importFileAtPath:(NSString *)songPath
{
    [Gremlin importFileAtPath:songPath];
}

- (void)gremlinImportWasSuccessful:(NSDictionary*)info
{
    NSLog(@"Gremlin import successful: %@", info);
}
- (void)gremlinImport:(NSDictionary*)info didFailWithError:(NSError*)error
{
     NSLog(@"Gremlin import failed: %@ withError: %@", info, error);
}

- (NSString *)iconImageName {
	return @"manage.png";
}
@end
