//
//  MKBuyReleaseEscrow.m
//  BitMarkets
//
//  Created by Steve Dekorte on 5/6/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "MKBuyReleaseEscrow.h"
#import "MKBuy.h"
#import "MKRootNode.h"
#import "MKBuyPostRefundMsg.h"
#import "MKBuyPostPaymentMsg.h"

@implementation MKBuyReleaseEscrow

- (id)init
{
    self = [super init];
    self.nodeViewClass = NavMirrorView.class;
    
    {
        NavActionSlot *slot = [self.navMirror newActionSlotWithName:@"requestRefund"];
        [slot setVisibleName:@"Request Refund"];
        [slot setVerifyMessage:@"You should only request a refund if the seller has failed to deliver the item in a reasonable amount of time or the item was unsatifactory. Request a refund?"];

    }
    
    {
        NavActionSlot *slot = [self.navMirror newActionSlotWithName:@"makePayment"];
        [slot setVisibleName:@"Make Payment"];
        [slot setVerifyMessage:@"You should only send payment after your purchased good or service is delivered and you have found it satifactory. Make the payment?"];
    }

    return self;
}

- (NSNumber *)nodeSuggestedWidth
{
    return @300.0;
}

- (NSString *)nodeSubtitle
{
    if (self.buyRequestRefundMsg)
    {
        if(!self.sellAcceptRefundRequestMsg)
        {
            return @"Refund requested, awaiting seller acceptance.";
        }
        
        if (!self.confirmRefundMsg)
        {
            return @"Awaiting refund confirmation.";
        }
        
        return @"Refund confirmed. Transaction complete.";
    }
    
    if (self.buyPaymentMsg)
    {
        if(!self.sellAcceptPaymentMsg)
        {
            return @"Payment sent, awaiting seller acceptance.";
        }
        
        if (!self.confirmPaymentMsg)
        {
            return @"Payment sent and accepted, awaiting payment confirmation.";
        }
        
        return @"Payment confirmed. Transaction complete.";
    }
    
    if (self.buy.isCanceled)
    {
        return nil;
    }
    
    if (!self.runningWallet)
    {
        return @"Waiting for wallet...";
    }
    
    if (self.isActive)
    {
        return @"Ready to make payment (after item received) or request refund.";
    }
    
    return nil;
}

- (BOOL)isActive
{
    if (!self.buy.delivery.isComplete)
    {
        return NO;
    }
    
    /*
    if (!self.runningWallet)
    {
        return NO;
    }
*/
    return self.buy.lockEscrow.isConfirmed && !self.isComplete;
//    return (self.buyPaymentMsg || self.buyRequestRefundMsg) && !self.isComplete;
}

- (BOOL)isComplete
{
    return (self.confirmPaymentMsg || self.confirmRefundMsg);
}

- (NSString *)nodeNote
{
    if (self.isComplete)
    {
        return @"✓";
    }
    
    if (self.isActive)
    {
        return @"●";
    }
    
    /*
    if (self.wasRejected)
    {
        return @"✗";
    }
    */
    
    return nil;
}

// update

- (BOOL)handleMsg:(MKMsg *)msg
{
    if ([msg isKindOfClass:MKSellAcceptPaymentMsg.class] ||
        [msg isKindOfClass:MKSellAcceptRefundRequestMsg.class] ||
        [msg isKindOfClass:MKSellRejectRefundRequestMsg.class])
    {
        [self addChild:msg];
        [self update];
        [self postParentChainChanged];
        return YES;
    }
    
    return NO;
}


- (void)update
{
    if (self.sellAcceptPaymentMsg && !self.buyPostPaymentMsg)
    {
        [self signAndPostAcceptToBlockChain];
    }
    
    if (self.sellAcceptRefundRequestMsg && !self.buyPostRefundMsg)
    {
        [self signAndPostRefundToBlockChain];
    }
    
    [self lookForConfirmsIfNeeded];
    
    [self updateActions];
}

- (void)updateActions
{
    BOOL isActive = self.isActive && (self.runningWallet != nil);
    //BOOL hasActed = self.buyRequestRefundMsg != nil || self.buyPaymentMsg != nil;
    BOOL canRequestRefund = self.buyRequestRefundMsg == nil && isActive;
    BOOL canMakePayment = self.buyPaymentMsg == nil && isActive;
    
    [[self.navMirror actionSlotNamed:@"requestRefund"] setIsActive:canRequestRefund];
    //[[self.navMirror actionSlotNamed:@"requestRefund"] setIsVisible:canRequestRefund];
    
    [[self.navMirror actionSlotNamed:@"makePayment"] setIsActive:canMakePayment];
    //[[self.navMirror actionSlotNamed:@"makePayment"] setIsVisible:canMakePayment];
}

// initiate payemnt

- (void)makePayment // user initiated
{
    //self.buy.lockEscrow.pos
    
    BNWallet *wallet = self.runningWallet;
    
    if (!wallet)
    {
        return;
    }
    
    BNTx *escrowTx = self.buy.lockEscrow.lockEscrowMsgToConfirm.tx;
    escrowTx.wallet = wallet;
    [escrowTx fetch]; //update subsuming tx
    if (escrowTx.subsumingTx)
    {
        escrowTx = escrowTx.subsumingTx;
    }
    
    BNTx *releaseTx = [[BNTx alloc] init];
    releaseTx.wallet = wallet;
    [releaseTx configureForReleaseWithInputTx:escrowTx];
    [releaseTx addPayToAddressOutputWithValue:[NSNumber numberWithLongLong:escrowTx.firstOutput.value.longLongValue/3]];
    
    MKBuyPaymentMsg *msg = [[MKBuyPaymentMsg alloc] init];
    [msg setPayload:[releaseTx asJSONObject]];
    [msg copyThreadFrom:self.buy.bidMsg];
    [msg sendToSeller];
    
    [self addChild:msg];
    [self update];
    [self updateActions];
    [self postParentChainChanged];
}

// initiate refund

- (void)requestRefund // user initiated
{
    BNWallet *wallet = MKRootNode.sharedMKRootNode.wallet;
    
    if (!wallet.isRunning)
    {
        return;
    }
    
    BNTx *escrowTx = self.buy.lockEscrow.lockEscrowMsgToConfirm.tx;
    escrowTx.wallet = wallet;
    [escrowTx fetch]; //update subsuming tx
    if (escrowTx.subsumingTx)
    {
        escrowTx = escrowTx.subsumingTx;
    }
    
    BNTx *refundTx = [[BNTx alloc] init];
    refundTx.wallet = wallet;
    [refundTx configureForReleaseWithInputTx:escrowTx];
    [refundTx addPayToAddressOutputWithValue:[NSNumber numberWithLongLong:2*escrowTx.firstOutput.value.longLongValue/3]];
    
    MKBuyRefundRequestMsg *msg = [[MKBuyRefundRequestMsg alloc] init];
    [msg copyThreadFrom:self.buy.bidMsg];
    [msg setPayload:refundTx.asJSONObject];
    [msg sendToSeller];
    
    [self addChild:msg];
    [self update];
    [self postParentChainChanged];
    [self updateActions];
}

// post payment

- (MKBuyPostPaymentMsg *)buyPostPaymentMsg
{
    return [self.children firstObjectOfClass:MKBuyPostPaymentMsg.class];
}

- (void)verifyAccept
{
    BNTx *buyerTx = self.buyPaymentMsg.tx;
    
    BNTx *sellerTx = self.sellAcceptPaymentMsg.tx;
    
    assert(sellerTx.inputs.count == 1);
    assert([sellerTx.inputs containsObject:[buyerTx.inputs firstObject]]);
    assert([sellerTx.outputs containsObject:[buyerTx.outputs firstObject]]);
}

- (void)signAndPostAcceptToBlockChain
{
    BNWallet *wallet = [MKRootNode sharedMKRootNode].wallet;
    
    if (!wallet.isRunning)
    {
        return;
    }
    
    if (!self.buyPostPaymentMsg)
    {
        BNTx *releaseTx = self.sellAcceptPaymentMsg.payload.asObjectFromJSONObject;
        releaseTx.wallet = wallet;
        [self verifyAccept];
        [releaseTx sign];
        [releaseTx broadcast];
        releaseTx.txType = @"Payment";
        releaseTx.description = self.buy.description;
        
        MKBuyPostPaymentMsg *msg = [[MKBuyPostPaymentMsg alloc] init];
        [msg copyThreadFrom:self.buy.bidMsg];
        [self addChild:msg];
    }
}


- (void)verifyRefund
{
    BNTx *buyerTx = self.buyRequestRefundMsg.tx;
    
    BNTx *sellerTx = self.sellAcceptRefundRequestMsg.tx;
    
    assert(sellerTx.inputs.count == 1);
    assert([sellerTx.inputs containsObject:[buyerTx.inputs firstObject]]);
    assert([sellerTx.outputs containsObject:[buyerTx.outputs firstObject]]);
}


// post refund

- (MKBuyPostRefundMsg *)buyPostRefundMsg
{
    return [self.children firstObjectOfClass:MKBuyPostRefundMsg.class];
}


- (void)signAndPostRefundToBlockChain
{
    BNWallet *wallet = [MKRootNode sharedMKRootNode].wallet;
    
    if (!wallet.isRunning)
    {
        return;
    }
    
    if (!self.buyPostRefundMsg)
    {
        BNTx *refundTx = self.sellAcceptRefundRequestMsg.payload.asObjectFromJSONObject;
        refundTx.wallet = wallet;
        [self verifyRefund];
        [refundTx sign];
        [refundTx broadcast];
        refundTx.txType = @"Refund";
        refundTx.description = self.buy.description;
        
        MKBuyPostRefundMsg *msg = [[MKBuyPostRefundMsg alloc] init];
        [msg copyThreadFrom:self.buy.bidMsg];
        [self addChild:msg];
    }
}

@end
