//
//  MKSetupLockMsg.h
//  BitMarkets
//
//  Created by Rich Collins on 7/8/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "MKLockMsg.h"

@interface MKSetupLockMsg : MKLockMsg

@property (strong, nonatomic) NSNumber *broadcastDateNumber;

- (void)configureAndBroadcastTx;
//- (void)broadcastIfNeeded;

- (void)returnChangeToWallet;

@end
