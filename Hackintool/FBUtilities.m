//
//  FBUtilities.m
//  Hackintool
//
//  Created by Ben Baker on 7/29/18.
//  Copyright © 2018 Ben Baker. All rights reserved.
//

// https://github.com/opensource-apple/IOKitTools/blob/master/ioreg.tproj/ioreg.c

#include "FBUtilities.h"
#include "AudioDevice.h"
#include <Foundation/Foundation.h>

bool getIntelGenString(NSDictionary *fbDriversDictionary, NSString **intelGenString)
{
	*intelGenString = @"???";
	NSString *framebufferName = nil;
	
	if (!getIORegString(@"AppleIntelMEIDriver", @"CFBundleIdentifier", &framebufferName))
		if (!getIORegString(@"AppleIntelAzulController", @"CFBundleIdentifier", &framebufferName))
			if (!getIORegString(@"AppleIntelFBController", @"CFBundleIdentifier", &framebufferName)) // AppleMEClientController
				if (!getIORegString(@"AppleIntelFramebufferController", @"CFBundleIdentifier", &framebufferName))
					return false;
	
	int intelGen = IGSandyBridge;
	
	for (int i = 0; i < IGCount; i++)
	{
		NSString *kextName = [fbDriversDictionary objectForKey:g_fbNameArray[i]];
		
		if ([framebufferName containsString:kextName])
		{
			intelGen = i;
			break;
		}
	}
	
	*intelGenString = g_fbNameArray[intelGen];
	
	return true;
}

void getConfigDictionary(AppDelegate *appDelegate, NSMutableDictionary *configDictionary, bool forceAll)
{
	Settings settings = [appDelegate settings];
	
	if (settings.PatchGraphicDevice || forceAll)
	{
		NSInteger intelGen = [appDelegate.intelGenComboBox indexOfSelectedItem];
		
		switch (intelGen)
		{
			case IGUnknown:
				break;
			case IGSandyBridge:
				getIGPUProperties<FramebufferSNB>(appDelegate, configDictionary);
				break;
			case IGIvyBridge:
				getIGPUProperties<FramebufferIVB>(appDelegate, configDictionary);
				break;
			case IGHaswell:
				getIGPUProperties<FramebufferHSW>(appDelegate, configDictionary);
				break;
			case IGBroadwell:
				getIGPUProperties<FramebufferBDW>(appDelegate, configDictionary);
				break;
			case IGSkylake:
			case IGKabyLake:
				getIGPUProperties<FramebufferSKL>(appDelegate, configDictionary);
				break;
			case IGCoffeeLake:
				getIGPUProperties<FramebufferCFL>(appDelegate, configDictionary);
				break;
			case IGCannonLake:
				getIGPUProperties<FramebufferCNL>(appDelegate, configDictionary);
				break;
			case IGIceLakeLP:
				getIGPUProperties<FramebufferICLLP>(appDelegate, configDictionary);
				break;
			case IGIceLakeHP:
				getIGPUProperties<FramebufferICLHP>(appDelegate, configDictionary);
				break;
		}
	}
	
	if (settings.PatchAudioDevice || forceAll)
	{
		NSArray *audioArray = @[@"HDEF", @"ALZA", @"AZAL", @"HDAS", @"CAVS"];
		
		for (NSString *name in audioArray)
			getAudioProperties(appDelegate, name, configDictionary);
	}
		
	if (settings.PatchPCIDevices || forceAll)
		getPCIProperties(appDelegate, configDictionary);
	
	injectUseIntelHDMI(appDelegate, configDictionary);
}

bool appendFramebufferInfoDSL(AppDelegate *appDelegate, uint32_t tab, NSMutableDictionary *configDictionary, NSString *name, NSMutableString **outputString)
{
	NSMutableDictionary *pciDeviceDictionary;

	if (![appDelegate tryGetPCIDeviceDictionary:name pciDeviceDictionary:&pciDeviceDictionary])
		return false;
	
	NSString *ioregName = [pciDeviceDictionary objectForKey:@"IORegName"];
	NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
	NSNumber *address = [pciDeviceDictionary objectForKey:@"Address"];
	
	if (![appDelegate isValidACPIEntry:ioregName])
		return false;
	
	[appDelegate appendDSLString:tab + 0 outputString:*outputString value:[NSString stringWithFormat:@"External (_SB_.%@, DeviceObj)", ioregName]];
	[appDelegate appendDSLString:tab + 0 outputString:*outputString value:[NSString stringWithFormat:@"Device (_SB.%@)", ioregName]];
	[appDelegate appendDSLString:tab + 0 outputString:*outputString value:@"{"];
	[appDelegate appendDSLString:tab + 1 outputString:*outputString value:[NSString stringWithFormat:@"Name (_ADR, 0x%08x)", [address unsignedIntValue]]];
	[appDelegate appendDSLString:tab + 1 outputString:*outputString value:@"Method (_DSM, 4, NotSerialized)"];
	[appDelegate appendDSLString:tab + 1 outputString:*outputString value:@"{"];
	[appDelegate appendDSLString:tab + 2 outputString:*outputString value:@"If (LEqual (Arg2, Zero)) { Return (Buffer() { 0x03 } ) }"];
	[appDelegate appendDSLString:tab + 2 outputString:*outputString value:@"Return (Package ()"];
	[appDelegate appendDSLString:tab + 2 outputString:*outputString value:@"{"];
	
	NSMutableDictionary *devicesPropertiesDictionary = ([appDelegate isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);
	NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
	
	for (NSString *deviceKey in deviceDictionary)
	{
		id deviceValue = deviceDictionary[deviceKey];
		
		if ([deviceValue isKindOfClass:[NSData class]])
			[appDelegate appendDSLValue:tab + 3 outputString:*outputString name:deviceKey value:deviceValue];
		else if ([deviceValue isKindOfClass:[NSString class]])
			[appDelegate appendDSLValue:tab + 3 outputString:*outputString name:deviceKey value:deviceValue];
	}
	
	[appDelegate appendDSLString:tab + 2 outputString:*outputString value:@"})"];
	[appDelegate appendDSLString:tab + 1 outputString:*outputString value:@"}"];
	[appDelegate appendDSLString:tab + 0 outputString:*outputString value:@"}"];
	
	return true;
}

void appendFramebufferInfoDSL(AppDelegate *appDelegate)
{
	// "AAPL,ig-platform-id", Buffer() { 0x00, 0x00, 0x16, 0x59 },
	// "model", Buffer() { "Intel UHD Graphics 620" },
	// "hda-gfx", Buffer() { "onboard-1" },
	// "device-id", Buffer() { 0x16, 0x59, 0x00, 0x00 },
	// "framebuffer-patch-enable", Buffer() { 0x01, 0x00, 0x00, 0x00 },
	// "framebuffer-unifiedmem", Buffer() {0x00, 0x00, 0x00, 0x80},
	
	Settings settings = [appDelegate settings];
	
	NSMutableDictionary *configDictionary = [NSMutableDictionary dictionary];
	NSMutableString *outputString = [NSMutableString string];
	
	getConfigDictionary(appDelegate, configDictionary, false);
	
	if (settings.PatchPCIDevices)
	{
		[appDelegate appendDSLString:0 outputString:outputString value:@"DefinitionBlock (\"\", \"SSDT\", 2, \"Hackintool\", \"PCI Devices\", 0x00000000)"];
		[appDelegate appendDSLString:0 outputString:outputString value:@"{"];
		
		for (int i = 0; i < [appDelegate.pciDevicesArray count]; i++)
		{
			NSMutableDictionary *pciDeviceDictionary = appDelegate.pciDevicesArray[i];
			NSString *ioregName = [pciDeviceDictionary objectForKey:@"IORegName"];
			
			appendFramebufferInfoDSL(appDelegate, 1, configDictionary, ioregName, &outputString);
		}
		
		[appDelegate appendDSLString:0 outputString:outputString value:@"}"];
	}
	else
	{
		if (settings.PatchGraphicDevice)
			appendFramebufferInfoDSL(appDelegate, 0, configDictionary, @"IGPU", &outputString);
		
		if (settings.PatchAudioDevice)
		{
			NSArray *audioArray = @[@"HDEF", @"ALZA", @"AZAL", @"HDAS", @"CAVS"];
			
			for (NSString *name in audioArray)
				appendFramebufferInfoDSL(appDelegate, 0, configDictionary, name, &outputString);
		}
	}
	
	[appDelegate appendTextView:appDelegate.patchOutputTextView text:outputString];
}

void getPCIProperties(AppDelegate *appDelegate, NSMutableDictionary *configDictionary)
{
	[appDelegate getPCIConfigDictionary:configDictionary];
}

bool getAudioProperties(AppDelegate *appDelegate, NSString *name, NSMutableDictionary *configDictionary)
{
	Settings settings = [appDelegate settings];
	
	NSMutableDictionary *devicesPropertiesDictionary = ([appDelegate isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);
	NSMutableDictionary *pciDeviceDictionary;
	
	if (![appDelegate tryGetPCIDeviceDictionary:name pciDeviceDictionary:&pciDeviceDictionary])
		return false;
	
	NSString *deviceName = [pciDeviceDictionary objectForKey:@"DeviceName"];
	NSString *className = [pciDeviceDictionary objectForKey:@"ClassName"];
	NSString *subClassName = [pciDeviceDictionary objectForKey:@"SubClassName"];
	NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
	NSString *slotName = [pciDeviceDictionary objectForKey:@"SlotName"];
	
	NSMutableDictionary *audioDictionary = [NSMutableDictionary dictionary];
	
	[devicesPropertiesDictionary setObject:audioDictionary forKey:devicePath];
	
	[audioDictionary setObject:deviceName forKey:@"model"];
	[audioDictionary setObject:([subClassName isEqualToString:@"???"] ? className : subClassName) forKey:@"device_type"];
	[audioDictionary setObject:slotName forKey:@"AAPL,slot-name"];
	
	if (settings.SpoofAudioDeviceID)
	{
		uint32_t audioDeviceID = 0;
		
		if ([appDelegate spoofAudioDeviceID:&audioDeviceID])
			[audioDictionary setObject:getNSDataUInt32(audioDeviceID) forKey:@"device-id"];
	}
	
	[audioDictionary setObject:getNSDataUInt32(appDelegate.audioDevice.alcLayoutID) forKey:@"layout-id"];
	
	return true;
}

void injectUseIntelHDMI(AppDelegate *appDelegate, NSMutableDictionary *configDictionary)
{
	// UseIntelHDMI
	// If TRUE, hda-gfx=onboard-1 will be injected into the GFX0 and HDEF devices. Also, if an ATI or Nvidia HDMI device is present, they'll be assigned to onboard-2.
	// If FALSE, then ATI or Nvidia devices will get onboard-1 as well as the HDAU device if present.
	
	Settings settings = [appDelegate settings];
	
	NSMutableDictionary *devicesPropertiesDictionary = ([appDelegate isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);

	NSMutableDictionary *igpuDeviceDictionary;
	
	if ([appDelegate tryGetPCIDeviceDictionary:@"IGPU" pciDeviceDictionary:&igpuDeviceDictionary])
	{
		NSString *devicePath = [igpuDeviceDictionary objectForKey:@"DevicePath"];
		NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
		
		if (settings.UseIntelHDMI)
			[deviceDictionary setObject:@"onboard-1" forKey:@"hda-gfx"];
		else if ([appDelegate hasGFX0])
			[deviceDictionary setObject:@"onboard-2" forKey:@"hda-gfx"];
	}
	
	NSMutableDictionary *hdefDeviceDictionary;
	
	if ([appDelegate tryGetPCIDeviceDictionary:@"HDEF" pciDeviceDictionary:&hdefDeviceDictionary])
	{
		NSString *devicePath = [hdefDeviceDictionary objectForKey:@"DevicePath"];
		NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
		
		if (settings.UseIntelHDMI)
			[deviceDictionary setObject:@"onboard-1" forKey:@"hda-gfx"];
		else if ([appDelegate hasGFX0])
			[deviceDictionary setObject:@"onboard-2" forKey:@"hda-gfx"];
	}
	
	NSMutableDictionary *gfx0DeviceDictionary;
	
	if ([appDelegate tryGetPCIDeviceDictionary:@"GFX0" pciDeviceDictionary:&gfx0DeviceDictionary])
	{
		NSString *devicePath = [gfx0DeviceDictionary objectForKey:@"DevicePath"];
		NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
		
		if (settings.UseIntelHDMI)
			[deviceDictionary setObject:@"onboard-2" forKey:@"hda-gfx"];
		else
			[deviceDictionary setObject:@"onboard-1" forKey:@"hda-gfx"];
	}
	
	NSMutableDictionary *hdauDeviceDictionary;
	
	if ([appDelegate tryGetPCIDeviceDictionary:@"HDAU" pciDeviceDictionary:&hdauDeviceDictionary])
	{
		NSString *devicePath = [hdefDeviceDictionary objectForKey:@"DevicePath"];
		NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
		
		if (settings.UseIntelHDMI)
			[deviceDictionary setObject:@"onboard-2" forKey:@"hda-gfx"];
		else
			[deviceDictionary setObject:@"onboard-1" forKey:@"hda-gfx"];
	}
}
