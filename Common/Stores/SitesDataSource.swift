//
//  SitesDataSource.swift
//  Nightscouter
//
//  Created by Peter Ina on 1/15/16.
//  Copyright © 2016 Nothingonline. All rights reserved.
//

import Foundation

public enum DefaultKey: String, RawRepresentable {
    case sites, lastViewedSiteIndex, primarySiteUUID, lastDataUpdateDateFromPhone, updateData, action, error, alarm
    
    static var payloadAlarmUpdate: [String: String] {
        return [DefaultKey.action.rawValue: DefaultKey.alarm.rawValue]
    }
    
    static var payloadPhoneUpdate: [String : String] {
        return [DefaultKey.action.rawValue: DefaultKey.updateData.rawValue]
    }
    
    static var payloadPhoneUpdateError: [String : String] {
        return [DefaultKey.action.rawValue: DefaultKey.error.rawValue]
    }
}

public class SitesDataSource: SiteStoreType {
    
    public static let sharedInstance = SitesDataSource()
    
    private init() {
        self.defaults = UserDefaults(suiteName: AppConfiguration.sharedApplicationGroupSuiteName ) ?? UserDefaults.standard
        
//        let watchConnectivityManager = WatchSessionManager.sharedManager
//        watchConnectivityManager.store = self
//        watchConnectivityManager.startSession()
        
        let iCloudManager = iCloudKeyValueStore()
        iCloudManager.store = self
        iCloudManager.startSession()
        
        let alarmManager = AlarmManager.sharedManager
        alarmManager.store = self
        alarmManager.startSession()
        
        self.sessionManagers = [iCloudManager, /*watchConnectivityManager,*/ alarmManager]
    }
    
    private let defaults: UserDefaults
    
    private var sessionManagers: [SessionManagerType] = []
    
    public var storageLocation: StorageLocation { return .localKeyValueStore }
    
    public var otherStorageLocations: SiteStoreType?
    
    public var sites: [Site] {
        if let loaded = loadData() {
            return loaded
        }
        return []
    }
    
    public var lastViewedSiteIndex: Int {
        set {
            if lastViewedSiteIndex != newValue {
                saveData([DefaultKey.lastViewedSiteIndex.rawValue: newValue])
            }
        }
        
        get {
            return defaults.object(forKey: DefaultKey.lastViewedSiteIndex.rawValue) as? Int ?? 0
        }
    }
    
    public var primarySite: Site? {
        set{
            if let site = newValue {
                saveData([DefaultKey.primarySiteUUID.rawValue: site.uuid.uuidString])
            }
        }
        get {
            if let uuidString = defaults.object(forKey: DefaultKey.primarySiteUUID.rawValue) as? String {
                return sites.filter { $0.uuid.uuidString == uuidString }.first
            } else if let firstSite = sites.first {
                return firstSite
            }
            return nil
        }
    }
    
    // MARK: Array modification methods
    @discardableResult
    public func createSite(_ site: Site, atIndex index: Int?) -> Bool {
        var initial: [Site] = self.sites
        
        if initial.isEmpty {
            primarySite = site
        }
        
        if let index = index {
            initial.insert(site, at: index)
        } else {
            initial.append(site)
        }
        
        let siteDict = initial.map { $0.encode() }
        
        saveData([DefaultKey.sites.rawValue: siteDict])
        
        return initial.contains(site)
    }
    
    @discardableResult
    public func updateSite(_ site: Site)  ->  Bool {
        
        var initial = sites
        
        let success = initial.insertOrUpdate(site)
        
        let siteDict = initial.map { $0.encode() }
        
        saveData([DefaultKey.sites.rawValue: siteDict])
        
        return success
    }
    
    @discardableResult
    public func deleteSite(_ site: Site) -> Bool {
        
        var initial = sites
        let success = initial.remove(site)
        
        if success == false {
            return false
        }
        
        /// Need to enabled this...
        // AppConfiguration.keychain[site.uuid.UUIDString] = nil
        
        if site == lastViewedSite {
            lastViewedSiteIndex = 0
        }
        
        if initial.isEmpty {
            lastViewedSiteIndex = 0
            primarySite = nil
        }
        
        let siteDict = initial.map { $0.encode() }
        saveData([DefaultKey.sites.rawValue: siteDict])
        
        return success
    }
    
    @discardableResult
    public func clearAllSites() -> Bool {
        var initial = sites
        initial.removeAll()
        
        saveData([DefaultKey.sites.rawValue: []])
        
        return initial.isEmpty
    }
    
    public func handleApplicationContextPayload(_ payload: [String : Any]) {
        
        if let sites = payload[DefaultKey.sites.rawValue] as? ArrayOfDictionaries {
            defaults.set(sites, forKey: DefaultKey.sites.rawValue)
        } else {
            print("No sites were found.")
        }
        
        if let lastViewedSiteIndex = payload[DefaultKey.lastViewedSiteIndex.rawValue] as? Int {
            self.lastViewedSiteIndex = lastViewedSiteIndex
        } else {
            print("No lastViewedIndex was found.")
        }
        
        if let uuidString = payload[DefaultKey.primarySiteUUID.rawValue] as? String {
            self.primarySite = sites.filter{ $0.uuid.uuidString == uuidString }.first
        } else {
            print("No primarySiteUUID was found.")
        }
        
        if let alarm = payload[DefaultKey.alarm.rawValue] as? String {
            print(alarm)
            
            
            
            
        } else {
            print("No alarm update was found.")
        }
        
        #if os(watchOS)
            if let lastDataUpdateDateFromPhone = payload[DefaultKey.lastDataUpdateDateFromPhone.rawValue] as? Date {
                defaults.set(lastDataUpdateDateFromPhone,forKey: DefaultKey.lastDataUpdateDateFromPhone.rawValue)
            }
        #endif
        
        if let action = payload[DefaultKey.action.rawValue] as? String {
            if action == DefaultKey.updateData.rawValue {
                print("found an action: \(action)")
                for _ in sites {
                    print("Why?")
                    fatalError()
                }
            } else if action == DefaultKey.error.rawValue {
                print("Received an error.")
                
            } else {
                print("Did not find an action.")
            }
        }
        
        defaults.synchronize()
    }
    
    public func loadData() -> [Site]? {
        
        if let sites = defaults.array(forKey: DefaultKey.sites.rawValue) as? ArrayOfDictionaries {
            return sites.flatMap { Site.decode($0) }
        }
        
        return []
    }
    
    let postToObservers = debounce(delay: 1, action: {
        print(">>> Entering \(#function) <<<")
        NotificationCenter.default.post(name: .NightscoutDataUpdatedNotification, object: nil)
    })
    
    @discardableResult
    public func saveData(_ dictionary: [String: Any]) -> (savedLocally: Bool, updatedApplicationContext: Bool) {
        
        var dictionaryToSend = dictionary
        
        var successfullSave: Bool = false
        
        for (key, object) in dictionaryToSend {
            defaults.set(object, forKey: key)
        }
        
        dictionaryToSend[DefaultKey.lastDataUpdateDateFromPhone.rawValue] = Date()
        
        successfullSave = defaults.synchronize()
        
        var successfullAppContextUpdate = true
        
        sessionManagers.forEach({ (manager: SessionManagerType ) -> () in
            do {
                try manager.updateApplicationContext(dictionaryToSend)
            } catch {
                successfullAppContextUpdate = false
                fatalError("Something didn't go right, create a fix.")
            }
        })
        
        postToObservers()
        
        return (successfullSave, successfullAppContextUpdate)
    }
}


public func debounce(delay: Int, queue: DispatchQueue = DispatchQueue.main, action: @escaping (()->()) ) -> ()->() {
    var lastFireTime   = DispatchTime.now()
    let dispatchDelay  = DispatchTimeInterval.seconds(delay)
    
    return {
        lastFireTime     = DispatchTime.now()
        let dispatchTime: DispatchTime = lastFireTime + dispatchDelay
        queue.asyncAfter(deadline: dispatchTime) {
            let when: DispatchTime = lastFireTime + dispatchDelay
            let now = DispatchTime.now()
            if now.rawValue >= when.rawValue {
                action()
            }
        }
    }
}