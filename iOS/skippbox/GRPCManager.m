//
//  GRPCManager.m
//  skippbox
//
//  Created by Remi Santos on 27/07/16.
//  Copyright © 2016 Azendoo. All rights reserved.
//

#import "GRPCManager.h"
#import "RCTLog.h"
#import <GRPCClient/GRPCCall+Tests.h>
#import <AFNetworking/AFNetworking.h>
#import "hapi/services/Tiller.pbrpc.h"
#import "hapi/chart/Metadata.pbobjc.h"
#import "hapi/chart/Template.pbobjc.h"
#import <NVHTarGzip/NVHTarGzip.h>
#import <YAMLThatWorks/YATWSerialization.h>

@implementation GRPCManager

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(deployChartAtURL:(NSString*)chartUrl
                      onHost:(NSString*)host
                      resolver:(RCTPromiseResolveBlock)resolve
                      rejecter:(RCTPromiseRejectBlock)reject)
{
  [GRPCCall useInsecureConnectionsForHost:host];
  ReleaseService *service = [[ReleaseService alloc] initWithHost:host];
  
  [self downloadFileAtUrl:chartUrl completion:^(NSURL *filePath) {
    NSURL *documentsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    NSURL *toPath = [documentsDirectoryURL URLByAppendingPathComponent:@"chart"];
    NSError *error;
    NSLog(@"Decrompressing file...");
    BOOL untared = [[NVHTarGzip sharedInstance] unTarGzipFileAtPath:filePath.path toPath:toPath.path error:&error];
    if (error) {
      error ? NSLog(@"ERROR %@", [error description]) : NSLog(@"failed");
      reject([@(error.code) stringValue], [error description], error);
      return;
    }
    if (!untared) {
      reject(0, @"Untar failed", nil);
      return;
    }

    NSLog(@"File decompressed at path %@", toPath.path);
    InstallReleaseRequest *request = [[InstallReleaseRequest alloc] init];
    [request setNamespace_p:@"default"];
    Chart *chart = [[Chart alloc] init];
    
    // Metadata
    NSString *chartYamlPath = [self searchFileWithName:@"Chart.yaml" inDirectory:toPath.path];
    NSData *chartData = [NSData dataWithContentsOfFile: chartYamlPath];
    NSDictionary *chartYaml = [YATWSerialization YAMLObjectWithData:chartData options:0 error:nil];
    Metadata *meta = [[Metadata alloc] init];
    meta.name = chartYaml[@"name"];
    meta.version = chartYaml[@"version"];
    meta.keywordsArray = chartYaml[@"keywoard"];
    meta.home = chartYaml[@"home"];
    meta.description_p = chartYaml[@"description"];
    [chart setMetadata:meta];
    
    // Templates
    NSMutableArray *templates = [NSMutableArray new];
    NSString *templatesPath = [self searchFileWithName:@"templates" inDirectory:toPath.path];
    NSArray *templatesDir = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:templatesPath error:nil];
    for (NSString *templatePath in templatesDir) {
      NSLog(@"Template: %@", templatePath);
      Template *template = [[Template alloc] init];
      template.name = templatePath;
      NSDictionary *templateDic = [YATWSerialization YAMLObjectWithData:[NSData dataWithContentsOfFile:[templatesPath stringByAppendingPathComponent:templatePath]] options:0 error:nil];
      template.data_p = [NSJSONSerialization dataWithJSONObject:templateDic options:0 error:nil];
      [templates addObject:template];
    }
    [chart setTemplatesArray:templates];
    [request setChart:chart];
    [service installReleaseWithRequest:request handler:^(InstallReleaseResponse * _Nullable response, NSError * _Nullable error) {
      [[NSFileManager defaultManager] removeItemAtPath:toPath.path error:nil];
      [[NSFileManager defaultManager] removeItemAtPath:filePath.path error:nil];
      if (error) {
        reject([@(error.code) stringValue], error.localizedDescription, error);
      } else {
        resolve(response.description);
      }
    }];
  }];
}

- (NSString*)searchFileWithName:(NSString*)lastPath inDirectory:(NSString*)directory
{
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self.lastPathComponent == %@", lastPath];
  NSArray *matchingPaths = [[[NSFileManager defaultManager] subpathsAtPath:directory] filteredArrayUsingPredicate:predicate];
  return [directory stringByAppendingPathComponent:matchingPaths.firstObject];
}

- (void)downloadFileAtUrl:(NSString*)url completion:(void (^)(NSURL *filePath))completion
{
  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
  AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
  
  NSURL *URL = [NSURL URLWithString:url];
  NSURLRequest *request = [NSURLRequest requestWithURL:URL];
  
  NSURLSessionDownloadTask *downloadTask = [manager downloadTaskWithRequest:request progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
    NSURL *documentsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    return [documentsDirectoryURL URLByAppendingPathComponent:[response suggestedFilename]];
  } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
    completion(filePath);
  }];
  [downloadTask resume];
}

@end