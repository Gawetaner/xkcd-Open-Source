//
//  ImageManager.m
//  xkcd Open Source
//
//  Created by Mike on 3/14/17.
//  Copyright © 2017 Mike Amaral. All rights reserved.
//

#import "ImageManager.h"

#import "OrderedDictionary.h"

static NSUInteger kImageCacheLimit = 100;

@interface ImageManager ()

@property (nonatomic, strong) NSString *documentsDirectoryPath;

@property (nonatomic, strong) NSFileManager *fileManager;

@property (nonatomic, strong) MutableOrderedDictionary *imageCache;

@property (nonatomic, strong) NSOperationQueue *downloadQueue;

@end

@implementation ImageManager

- (instancetype)init {
    self = [super init];

    if (!self) {
        return nil;
    }

    // Create a new queue we'll use for the download operations.
    self.downloadQueue = [NSOperationQueue new];
    self.downloadQueue.maxConcurrentOperationCount = 10;

    // Get our documents directory path.
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    self.documentsDirectoryPath = paths.firstObject;

    // Create our file manager.
    self.fileManager = [NSFileManager defaultManager];

    // Create our image cache, which is simply a mutable ordered dictionary.
    // We use an ordered dictionary to be able to utilize the key/value pairing
    // of a dictionary coupled with the ordered nature of an array to enforce
    // a FIFO queue.
    self.imageCache = [MutableOrderedDictionary dictionary];

    return self;
}

- (nullable UIImage *)loadImageWithFilename:(NSString *)filename
                                  urlString:(NSString *)urlString
                            downloadHandler:(void (^)(UIImage * nullable))handler {
    // #1 - Load from cache.
    UIImage *cachedImage = self.imageCache[filename];
    if (cachedImage) {
        NSLog(@"Image found in cache with filename: %@", filename);
        return cachedImage;
    }

    // #2 - Load from disk.
    UIImage *imageOnDisk = [self loadImageFromDiskWithFilename:filename];
    if (imageOnDisk) {
        NSLog(@"Image found on disk with filename: %@", filename);
        return imageOnDisk;
    }

    // #3 - Download from URL.
    NSLog(@"Image not in cache and not on disk. Attempting to download now...");
    [self downloadAndStoreImageFromURLString:urlString filename:filename handler:handler];

    return nil;
}

- (void)cancelDownloadHandlerForFilename:(nullable NSString *)filename {
    if (filename.length == 0) {
        return;
    }

    for (NSBlockOperation *operation in self.downloadQueue.operations) {
        if ([operation.name isEqualToString:filename]) {
            NSLog(@"Canceling operation for filename: %@", filename);
            [operation cancel];
            return;
        }
    }
}

- (UIImage *)loadImageFromDiskWithFilename:(NSString *)filename {
    NSString *path = [self.documentsDirectoryPath stringByAppendingPathComponent:filename];

    if ([self.fileManager fileExistsAtPath:path]) {
        NSData *dataFromDisk = [self.fileManager contentsAtPath:path];
        UIImage *imageFromDisk = [UIImage imageWithData:dataFromDisk];

        if (imageFromDisk) {
            [self updateCacheWithFilename:filename image:imageFromDisk];
            return imageFromDisk;
        }
    }

    return nil;
}

- (void)downloadAndStoreImageFromURLString:(NSString *)urlString filename:(NSString *)filename handler:(void (^)(UIImage * nullable))handler {
    __block NSBlockOperation *downloadOperation = [NSBlockOperation blockOperationWithBlock:^{
        NSURL *url = [NSURL URLWithString:urlString];
        NSData *dataFromServer = [NSData dataWithContentsOfURL:url];

        if (dataFromServer) {
            UIImage *imageFromServer = [UIImage imageWithData:dataFromServer];

            if (imageFromServer) {
                NSLog(@"Image downloaded.");

                // Dispatch the handler on the main thread only if our operation wasn't cancelled.
                if (![downloadOperation isCancelled]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        handler(imageFromServer);
                    });
                }

                [self updateCacheWithFilename:filename image:imageFromServer];
            }

            NSString *path = [self.documentsDirectoryPath stringByAppendingPathComponent:filename];
            BOOL success = [dataFromServer writeToFile:path atomically:YES];

            if (success) {
                NSLog(@"Image saved to disk successfully with filename: %@", filename);
            } else {
                NSLog(@"Image save failed for filename: %@", filename);
            }
        } else {
            NSLog(@"Unable to download image.");
        }
    }];
    downloadOperation.name = filename;

    [self.downloadQueue addOperation:downloadOperation];
}

/**
 * Updates our image cache by adding the provided filename as the key and the image object
 * as the value for that key. If the cache is full, remove the first image and add the new
 * image to the end of the queue.
 *
 * @param filename The name of the image file that will be used as the key for the image.
 * @param image The image to be cached.
 */
- (void)updateCacheWithFilename:(NSString *)filename image:(UIImage *)image {
    NSParameterAssert(filename);
    NSParameterAssert(image);

    // Remove the first (oldest) object from the cache if we're at the limit.
    if (self.imageCache.count == kImageCacheLimit) {
        [self.imageCache removeObjectAtIndex:0];
    }

    // Insert the new key/value pair at the end of the cache.
    self.imageCache[filename] = image;
}

@end
