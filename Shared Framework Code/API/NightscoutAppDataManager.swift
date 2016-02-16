//
//  NightscoutAppDataManager.swift
//  Nightscouter
//
//  Created by Peter Ina on 12/16/15.
//  Copyright © 2015 Peter Ina. All rights reserved.
//

import Foundation

let updateInterval: NSTimeInterval = Constants.NotableTime.StandardRefreshTime
public let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)

public func quickFetch(site: Site, handler: (returnedSite: Site, error: NightscoutAPIError) -> Void) {
    dispatch_async(queue) {
        print(">>> Entering \(__FUNCTION__) <<<")
        print("STARTING:    Load all available site data for: \(site.url)")
        
        let nsAPI = NightscoutAPIClient(url: site.url)
        var errorToReturn: NightscoutAPIError = .NoError
        
        let data_downloader_group: dispatch_group_t = dispatch_group_create()
        dispatch_group_enter(data_downloader_group)
        let startDate = NSDate()
        print("STEP 1:  GET Sever Status/Configuration for site: \(site.url)")
        nsAPI.fetchServerConfiguration { (result) -> Void in
            switch result {
            case .Error:
                site.disabled = true
                errorToReturn = NightscoutAPIError.DownloadErorr("No configuration was found")
                handler(returnedSite: site, error: errorToReturn)
            case let .Value(boxedConfiguration):
                let configuration = boxedConfiguration.value
                site.configuration = configuration
            }
            
            dispatch_group_leave(data_downloader_group)
        }
        
        if site.disabled == false {
            
            dispatch_group_enter(data_downloader_group)
            print("STEP 2:      GET Sever Pebble/Watch for site: \(site.url)")
            nsAPI.fetchDataForWatchEntry({ (watchEntry, errorCode) -> Void in
                site.watchEntry = watchEntry
                errorToReturn = errorCode
                
                dispatch_group_leave(data_downloader_group)
            })
            
        }
        
        dispatch_group_notify(data_downloader_group, dispatch_get_main_queue()) {
            print("COMPLETE:    All network operations are complete for site: \(site.url)")
            print("DURATION:    The entire process took: \(NSDate().timeIntervalSinceDate(startDate))")
            print("STEP 6:      Return Handler to main thread.")
            handler(returnedSite: site, error: errorToReturn)
        }
    }
}


public func fetchSiteData(site: Site, handler: (returnedSite: Site, error: NightscoutAPIError) -> Void) {
    dispatch_async(queue) {
        print(">>> Entering \(__FUNCTION__) <<<")
        print("STARTING:    Load all available site data for: \(site.url)")
        
        let nsAPI = NightscoutAPIClient(url: site.url)
        var errorToReturn: NightscoutAPIError = .NoError
        
        let data_downloader_group: dispatch_group_t = dispatch_group_create()
        dispatch_group_enter(data_downloader_group)
        let startDate = NSDate()
        print("STEP 1:  GET Sever Status/Configuration for site: \(site.url)")
        nsAPI.fetchServerConfiguration { (result) -> Void in
            switch result {
            case .Error:
                site.disabled = true
                errorToReturn = NightscoutAPIError.DownloadErorr("No configuration was found")
                handler(returnedSite: site, error: errorToReturn)
            case let .Value(boxedConfiguration):
                let configuration = boxedConfiguration.value
                site.configuration = configuration
            }
            
            dispatch_group_leave(data_downloader_group)
        }
        
        if site.disabled == false {
            
            dispatch_group_enter(data_downloader_group)
            print("STEP 2:      GET Sever Pebble/Watch for site: \(site.url)")
            nsAPI.fetchDataForWatchEntry({ (watchEntry, errorCode) -> Void in
                site.watchEntry = watchEntry
                errorToReturn = errorCode
            })
            
            print("STEP 3:      GET Sever Entries/SGVs for site: \(site.url)")
            nsAPI.fetchDataForEntries(Constants.EntryCount.NumberForComplication, completetion: { (entries, errorCode) -> Void in
                site.entries = entries
                errorToReturn = errorCode
            })
            
            print("STEP 4:      GET Sever CALs/Calibrations for site: \(site.url)")
            let numberOfCalsNeeded = ((Constants.EntryCount.NumberForComplication * 5) / 60) / 12 + 1
            nsAPI.fetchCalibrations(numberOfCalsNeeded, completetion: { (calibrations, errorCode) -> Void in
                errorToReturn = errorCode
                
                guard let calibrations = calibrations else {
                    dispatch_group_leave(data_downloader_group)
                    return
                }
                
                let cals = calibrations.sort{(item1:Entry, item2:Entry) -> Bool in
                    item1.date.compare(item2.date) == .OrderedDescending
                    }.flatMap { $0.cal }
                
                site.calibrations = cals
                
                dispatch_group_leave(data_downloader_group)
            })
            
        }
        
        let complication_generator_group: dispatch_group_t = dispatch_group_create()
        dispatch_group_enter(complication_generator_group)
        dispatch_group_notify(data_downloader_group, queue) {
            print("STEP 5:      Generate Timeline data for Complication for site: \(site.url)")
            let complicationModels = generateComplicationModels(forSite: site, calibrations: site.calibrations)
            site.complicationModels = complicationModels
            dispatch_group_leave(complication_generator_group)
        }
        
        dispatch_group_notify(complication_generator_group, dispatch_get_main_queue()) {
            print("COMPLETE:    All network operations are complete for site: \(site.url)")
            print("DURATION:    The entire process took: \(NSDate().timeIntervalSinceDate(startDate))")
            print("STEP 6:      Return Handler to main thread.")
            handler(returnedSite: site, error: errorToReturn)
        }
    }
}

private func generateComplicationModels(forSite site: Site, calibrations: [Calibration]) -> [ComplicationModel] {
    
    let cals = calibrations.sort{(item1: Calibration, item2: Calibration) -> Bool in
        item1.date.compare(item2.date) == NSComparisonResult.OrderedDescending
    }
    
    guard let configuration = site.configuration, entries = site.entries else {
        return []
    }
    
    var cmodels: [ComplicationModel] = []
    
    // Get prefered Units. mmol/L or mg/dL
    let units: Units = configuration.displayUnits
    
    for (index, entry) in entries.enumerate() {
        
        if let sgvValue = entry.sgv {
            
            // Convert units.
            let boundedColor = configuration.boundedColorForGlucoseValue(sgvValue.sgv)
            //if units == .Mmol {
            //  boundedColor = configuration.boundedColorForGlucoseValue(sgvValue.sgv)
            //}
            
            var sgvString = "\(sgvValue.sgv.formattedForMgdl)"
            if configuration.displayUnits == .Mmol {
                sgvString = sgvValue.sgv.formattedForMmol
            }
            
            sgvString =  "\(sgvValue.sgvString(forUnits: units))"
            let sgvEmoji = "\(sgvValue.direction.emojiForDirection)"
            let sgvStringWithEmoji = "\(sgvString) \(sgvValue.direction.emojiForDirection)"
            
            var delta: Double = 0
            
            let nextIndex: Int = index + 1
            
            if nextIndex < entries.count {
                if let previousSgv = entries[nextIndex].sgv {
                    if sgvValue.isSGVOk && previousSgv.isSGVOk {
                        delta = sgvValue.sgv - previousSgv.sgv
                    }
                }
            }
            
            if configuration.displayUnits == .Mmol {
                delta = delta.toMmol
            }
            
            let deltaString = delta.formattedBGDelta(forUnits: units)
            let deltaStringShort = delta.formattedBGDelta(forUnits: units, appendString: "∆")
            let sgvColor = colorForDesiredColorState(boundedColor)
            
            var raw: String?
            var rawShort: String?
            
            if let cal = nearestCalibration(calibrations: cals, calibrationsforDate: entry.date) {
                
                var convertedRawValue: String = sgvValue.rawIsigToRawBg(cal).formattedForMgdl
                if configuration.displayUnits == .Mmol {
                    convertedRawValue = sgvValue.rawIsigToRawBg(cal).formattedForMmol
                }
                
                raw = "\(convertedRawValue) : \(sgvValue.noise.description)"
                rawShort = "\(convertedRawValue) : \(sgvValue.noise.description[sgvValue.noise.description.startIndex])"
            }
            
            cmodels.append(ComplicationModel(displayName: configuration.displayName, date: entry.date, sgv: sgvStringWithEmoji, sgvEmoji: sgvEmoji, tintString: sgvColor.toHexString(), delta: deltaString, deltaShort: deltaStringShort, raw: raw, rawShort: rawShort))
            
        }
        
    }
    return cmodels
}


private func nearestCalibration(calibrations cals:[Calibration], calibrationsforDate date: NSDate) -> Calibration? {
    var desiredIndex: Int?
    var minDate: NSTimeInterval = fabs(NSDate().timeIntervalSinceNow)
    
    for (index, entry) in cals.enumerate() {
        let dateInterval = fabs(entry.date.timeIntervalSinceDate(date))
        let compared = minDate < dateInterval
        // print("Testing: \(minDate) < \(dateInterval) = \(compared)")
        if compared {
            minDate = dateInterval
            desiredIndex = index
        }
    }
    
    guard let index = desiredIndex else {
        print("NON-FATAL ERROR: No valid index was found... return last calibration if its there.")
        return cals.first
    }
    
    // print("incoming date: \(closestDate.timeIntervalSinceNow) returning date: \(calibrations[index].date.timeIntervalSinceNow)")
    return cals[index]
}

