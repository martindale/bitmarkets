//
//  MKMsg.h
//  BitMarkets
//
//  Created by Steve Dekorte on 5/2/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "MKGroup.h"
#import <BitmessageKit/BitmessageKit.h>

@interface MKMsg : MKGroup

@property (strong, nonatomic) NSMutableDictionary *dict;

+ (MKMsg *)withBMMessage:(BMMessage *)bmMessage;

@end