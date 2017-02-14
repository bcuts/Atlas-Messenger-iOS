//
//  ATLMAuthenticationProvider.m
//  Atlas Messenger
//
//  Created by Kevin Coleman on 5/26/16.
//  Copyright © 2016 Layer, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//


#import "ATLMAuthenticationProvider.h"
#import "ATLMHTTPResponseSerializer.h"
#import "ATLMConstants.h"
#import "ATLMConfiguration.h"
#import "ATLMUtilities.h"


NSString *const ATLMEmailKey = @"ATLMEmailKey";
NSString *const ATLMPasswordKey = @"ATLMPasswordKey";
NSString *const ATLMCredentialsKey = @"DIMCredentialsKey";
static NSString *const ATLMAtlasIdentityTokenKey = @"identity_token";

@interface ATLMAuthenticationProvider ();

@property (nonatomic) NSURL *baseURL;
@property (nonatomic) NSURLSession *URLSession;

@end

@implementation ATLMAuthenticationProvider

+ (nonnull instancetype)providerWithBaseURL:(nonnull NSURL *)baseURL layerAppID:(NSURL *)layerAppID
{
    return  [[self alloc] initWithBaseURL:baseURL layerAppID:layerAppID];
}

- (instancetype)initWithConfiguration:(ATLMConfiguration *)configuration
{
    NSURL *appIDURL = configuration.appID;
    NSURL *identityProviderURL = (configuration.identityProviderURL ?: ATLMRailsBaseURL(ATLMEnvironmentProduction));
    
    self = [self initWithBaseURL:identityProviderURL layerAppID:appIDURL];
    return self;
}

- (instancetype)initWithBaseURL:(nonnull NSURL *)baseURL layerAppID:(NSURL *)layerAppID;
{
    self = [super init];
    if (self) {
        _baseURL = baseURL;
        _layerAppID = layerAppID;
        
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.HTTPAdditionalHeaders = @{ @"Accept": @"application/json",
                                                 @"X_LAYER_APP_ID": self.layerAppID.absoluteString };
        _URLSession = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (instancetype)init
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"Failed to call designated initializer. Call the designated initializer on the subclass instead."
                                 userInfo:nil];
}

+ (NSString *)authenticateEndpoint
{
    return @"/authenticate";
}

+ (NSString *)listUsersEndpoint
{
    return @"/users.json";
}

- (void)authenticateWithCredentials:(NSDictionary *)credentials nonce:(NSString *)nonce completion:(void (^)(NSString *identityToken, NSError *error))completion
{
    NSURL *authenticateURL = [NSURL URLWithString:[self.class authenticateEndpoint] relativeToURL:self.baseURL];
    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:credentials];
    [payload setObject:nonce forKey:@"nonce"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:authenticateURL];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }
        
        [[NSUserDefaults standardUserDefaults] setValue:credentials forKey:ATLMCredentialsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // TODO: Basic response and content checks — status and length
        NSError *serializationError;
        NSDictionary *rawResponse = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:data options:0 error:&serializationError];
        if (serializationError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, serializationError);
            });
        }
        
        NSString *identityToken = rawResponse[@"identity_token"];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(identityToken, nil);
        });
    }] resume];
}

- (void)refreshAuthenticationWithNonce:(NSString *)nonce completion:(void (^)(NSString *identityToken, NSError *error))completion
{
    NSDictionary *credentials = [[NSUserDefaults standardUserDefaults] objectForKey:ATLMCredentialsKey];
    [self authenticateWithCredentials:credentials nonce:nonce completion:^(NSString * _Nonnull identityToken, NSError * _Nonnull error) {
        completion(identityToken, error);
    }];
}

@end
