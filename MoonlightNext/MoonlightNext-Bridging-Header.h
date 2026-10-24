//
//  MoonlightNext-Bridging-Header.h
//  Moonlight Next
//
//  ObjC services the SwiftUI launcher calls into. Do not import anything that pulls in
//  StreamView.h: it imports the generated Moonlight-Swift.h, which would be a cycle.
//  Stream-side code is reached through MNBridge instead.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

#import "DataManager.h"
#import "TemporaryHost.h"
#import "TemporaryApp.h"
#import "TemporarySettings.h"
#import "DiscoveryManager.h"
#import "PairManager.h"
#import "HttpManager.h"
#import "AppAssetManager.h"
#import "ConnectionHelper.h"
#import "AppListResponse.h"
#import "WakeOnLanManager.h"
#import "CryptoManager.h"
#import "IdManager.h"
#import "Utils.h"
#import "MNBridge.h"
