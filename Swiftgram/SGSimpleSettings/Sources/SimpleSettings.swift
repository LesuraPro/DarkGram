import Foundation
import SGAppGroupIdentifier
import SGLogging

let APP_GROUP_IDENTIFIER = sgAppGroupIdentifier()

public class SGSimpleSettings {
    
    public static let shared = SGSimpleSettings()
    
    private init() {
        setDefaultValues()
        migrate()
        preCacheValues()
    }
    
    private func setDefaultValues() {
        UserDefaults.standard.register(defaults: SGSimpleSettings.defaultValues)
        // Just in case group defaults will be nil
        UserDefaults.standard.register(defaults: SGSimpleSettings.groupDefaultValues)
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.register(defaults: SGSimpleSettings.groupDefaultValues)
        }
    }
    
    private func migrate() {
        let showRepostToStoryMigrationKey = "migrated_\(Keys.showRepostToStory.rawValue)"
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            if !groupUserDefaults.bool(forKey: showRepostToStoryMigrationKey) {
                self.showRepostToStoryV2 = self.showRepostToStory
                groupUserDefaults.set(true, forKey: showRepostToStoryMigrationKey)
                SGLogger.shared.log("SGSimpleSettings", "Migrated showRepostToStory. \(self.showRepostToStory) -> \(self.showRepostToStoryV2)")
            }
        } else {
            SGLogger.shared.log("SGSimpleSettings", "Unable to migrate showRepostToStory. Shared UserDefaults suite is not available for '\(APP_GROUP_IDENTIFIER)'.")
        }

        let chatListLinesMigrationKey = "migrated_\(Keys.chatListLines.rawValue)"
        if !UserDefaults.standard.bool(forKey: chatListLinesMigrationKey) {
            let legacyCompactMessagePreviewKey = "compactMessagePreview"
            if UserDefaults.standard.object(forKey: legacyCompactMessagePreviewKey) != nil {
                if UserDefaults.standard.bool(forKey: legacyCompactMessagePreviewKey) {
                    self.chatListLines = ChatListLines.one.rawValue
                }
                UserDefaults.standard.removeObject(forKey: legacyCompactMessagePreviewKey)
                SGLogger.shared.log("SGSimpleSettings", "Migrated compactMessagePreview -> chatListLines. \(self.chatListLines)")
            }
            UserDefaults.standard.set(true, forKey: chatListLinesMigrationKey)
        }
    }
    
    private func preCacheValues() {
        // let dispatchGroup = DispatchGroup()

        let tasks = [
//            { let _ = self.allChatsFolderPositionOverride },
            { let _ = self.tabBarSearchEnabled },
            { let _ = self.allChatsHidden },
            { let _ = self.hideTabBar },
            { let _ = self.bottomTabStyle },
            { let _ = self.compactChatList },
            { let _ = self.chatListLines },
            { let _ = self.compactFolderNames },
            { let _ = self.disableSwipeToRecordStory },
            { let _ = self.rememberLastFolder },
            { let _ = self.quickTranslateButton },
            { let _ = self.stickerSize },
            { let _ = self.stickerTimestamp },
            { let _ = self.hideReactions },
            { let _ = self.disableGalleryCamera },
            { let _ = self.disableSendAsButton },
            { let _ = self.disableSnapDeletionEffect },
            { let _ = self.startTelescopeWithRearCam },
            { let _ = self.hideRecordingButton },
            { let _ = self.inputToolbar },
            { let _ = self.dismissedSGSuggestions },
            { let _ = self.customAppBadge },
            { let _ = self.ghostMode },
            { let _ = self.stealthStoryViews },
            { let _ = self.keepDeletedMessages },
            { let _ = self.keepEditHistory },
            { let _ = self.bypassCopyProtection },
            { let _ = self.confirmSendToGroup },
            { let _ = self.ghostScheduleEnabled },
            { let _ = self.perChatGhostPeerIds },
            { let _ = self.keywordAlertSound },
            { let _ = self.preferLocalSearch },
            { let _ = self.keepOneTimeMedia }
        ]

        tasks.forEach { task in
            DispatchQueue.global(qos: .background).async(/*group: dispatchGroup*/) {
                task()
            }
        }

        // dispatchGroup.notify(queue: DispatchQueue.main) {}
    }
    
    // MARK: DarkGram - settings backup.
    // A free Apple ID signature lasts seven days, so the app gets reinstalled constantly and
    // every toggle is lost each time. Keys is CaseIterable, so the whole set round-trips without
    // a hand-maintained list that would silently drift as settings are added.

    /// Serialises every known setting that currently has a stored value.
    /// Values that JSON cannot represent are skipped rather than failing the whole export.
    public func exportToJSON() -> Data? {
        var payload: [String: Any] = [:]
        let defaults = UserDefaults.standard
        for key in Keys.allCases {
            guard let value = defaults.object(forKey: key.rawValue) else {
                continue
            }
            if JSONSerialization.isValidJSONObject([value]) {
                payload[key.rawValue] = value
            }
        }
        guard !payload.isEmpty else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    /// Restores settings from a previously exported file.
    /// Unknown keys are ignored, so a file from a newer or older build cannot inject
    /// arbitrary values into UserDefaults. Returns how many settings were applied.
    @discardableResult
    public func importFromJSON(_ data: Data) -> Int {
        guard let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return 0
        }
        let knownKeys = Set(Keys.allCases.map({ $0.rawValue }))
        let defaults = UserDefaults.standard
        var applied = 0
        for (key, value) in payload where knownKeys.contains(key) {
            defaults.set(value, forKey: key)
            applied += 1
        }
        if applied > 0 {
            defaults.synchronize()
            self.synchronizeShared()
        }
        return applied
    }

    public func synchronizeShared() {
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.synchronize()
        }
    }
    
    public enum Keys: String, CaseIterable {
        case hidePhoneInSettings
        case showTabNames
        case startTelescopeWithRearCam
        case accountColorsSaturation
        case uploadSpeedBoost
        case downloadSpeedBoost
        case bottomTabStyle
        case rememberLastFolder
        case lastAccountFolders
        case localDNSForProxyHost
        case sendLargePhotos
        case outgoingPhotoQuality
        case storyStealthMode
        case canUseStealthMode
        case ghostMode
        case stealthStoryViews
        case keepDeletedMessages
        case keepEditHistory
        case bypassCopyProtection
        case confirmSendToGroup
        case disableSwipeToRecordStory
        case quickTranslateButton
        case outgoingLanguageTranslation
        case hideReactions
        case showRepostToStory
        case showRepostToStoryV2
        case contextShowSelectFromUser
        case contextShowSaveToCloud
        case contextShowRestrict
        // case contextShowBan
        case contextShowHideForwardName
        case contextShowReport
        case contextShowReply
        case contextShowPin
        case contextShowSaveMedia
        case contextShowMessageReplies
        case contextShowJson
        case disableScrollToNextChannel
        case disableScrollToNextTopic
        case disableChatSwipeOptions
        case disableDeleteChatSwipeOption
        case disableGalleryCamera
        case disableGalleryCameraPreview
        case disableSendAsButton
        case disableSnapDeletionEffect
        case stickerSize
        case stickerTimestamp
        case hideRecordingButton
        case hideTabBar
        case showDC
        case showCreationDate
        case showRegDate
        case regDateCache
        case compactChatList
        case chatListLines
        case compactFolderNames
        case allChatsTitleLengthOverride
//        case allChatsFolderPositionOverride
        case allChatsHidden
        case defaultEmojisFirst
        case messageDoubleTapActionOutgoing
        // MARK: DarkGram
        case messageDoubleTapActionIncoming
        case wideChannelPosts
        case forceEmojiTab
        case forceBuiltInMic
        case secondsInMessages
        case hideChannelBottomButton
        case forceSystemSharing
        case confirmCalls
        case videoPIPSwipeDirection
        case legacyNotificationsFix
        case messageFilterKeywords
        case notifyKeywords
        case quickReplies
        case contactAliases
        case contactNotes
        case ghostScheduleEnabled
        case ghostScheduleFromHour
        case ghostScheduleToHour
        case keywordAlertSound
        case preferLocalSearch
        case keepOneTimeMedia
        case perChatGhostPeerIds
        case inputToolbar
        case pinnedMessageNotifications
        case mentionsAndRepliesNotifications
        case primaryUserId
        case status
        case dismissedSGSuggestions
        case duckyAppIconAvailable
        case transcriptionBackend
        case translationBackend
        case customAppBadge
        case canUseNY
        case nyStyle
        case wideTabBar
        case tabBarSearchEnabled
        case hideStories
        case warnOnStoriesOpen
        case showProfileId
        case sendWithReturnKey
    }
    
    public enum DownloadSpeedBoostValues: String, CaseIterable {
        case none
        case medium
        case maximum
    }
    
    public enum BottomTabStyleValues: String, CaseIterable {
        case telegram
        case ios
    }
    
    public enum AllChatsTitleLengthOverride: String, CaseIterable {
        case none
        case short
        case long
    }
    
    public enum AllChatsFolderPositionOverride: String, CaseIterable {
        case none
        case last
        case hidden
    }

    public enum ChatListLines: String, CaseIterable {
        case three = "3"
        case two = "2"
        case one = "1"

        public static let defaultValue: ChatListLines = .three
    }
    
    public enum MessageDoubleTapAction: String, CaseIterable {
        case `default`
        case none
        case edit
        // MARK: DarkGram
        case reply
        case copy

        /// Editing someone else's message is not a thing, so that choice is hidden for incoming.
        public static func available(incoming: Bool) -> [MessageDoubleTapAction] {
            return allCases.filter { incoming ? $0 != .edit : true }
        }
    }
    
    public enum VideoPIPSwipeDirection: String, CaseIterable {
        case up
        case down
        case none
    }

    public enum TranscriptionBackend: String, CaseIterable {
        case `default`
        case apple
    }

    public enum TranslationBackend: String, CaseIterable {
        case `default`
        case gtranslate
        case system
        // Make sure to update TranslationConfiguration
    }
        
    public enum PinnedMessageNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }
    
    public enum MentionsAndRepliesNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }

    public enum NYStyle: String, CaseIterable {
        case `default`
        case snow
        case lightning
    }
    
    public static let defaultValues: [String: Any] = [
        Keys.hidePhoneInSettings.rawValue: true,
        Keys.showTabNames.rawValue: true,
        Keys.startTelescopeWithRearCam.rawValue: false,
        Keys.accountColorsSaturation.rawValue: 100,
        Keys.uploadSpeedBoost.rawValue: false,
        Keys.downloadSpeedBoost.rawValue: DownloadSpeedBoostValues.none.rawValue,
        Keys.rememberLastFolder.rawValue: false,
        Keys.bottomTabStyle.rawValue: BottomTabStyleValues.telegram.rawValue,
        Keys.lastAccountFolders.rawValue: [:],
        Keys.localDNSForProxyHost.rawValue: false,
        Keys.sendLargePhotos.rawValue: false,
        Keys.outgoingPhotoQuality.rawValue: 70,
        Keys.storyStealthMode.rawValue: false,
        Keys.ghostMode.rawValue: false,
        Keys.stealthStoryViews.rawValue: false,
        Keys.keepDeletedMessages.rawValue: false,
        Keys.keepEditHistory.rawValue: false,
        Keys.bypassCopyProtection.rawValue: false,
        Keys.confirmSendToGroup.rawValue: false,
        Keys.canUseStealthMode.rawValue: true,
        Keys.disableSwipeToRecordStory.rawValue: false,
        Keys.quickTranslateButton.rawValue: false,
        Keys.outgoingLanguageTranslation.rawValue: [:],
        Keys.hideReactions.rawValue: false,
        Keys.showRepostToStory.rawValue: true,
        Keys.contextShowSelectFromUser.rawValue: true,
        Keys.contextShowSaveToCloud.rawValue: true,
        Keys.contextShowRestrict.rawValue: true,
        // Keys.contextShowBan.rawValue: true,
        Keys.contextShowHideForwardName.rawValue: true,
        Keys.contextShowReport.rawValue: true,
        Keys.contextShowReply.rawValue: true,
        Keys.contextShowPin.rawValue: true,
        Keys.contextShowSaveMedia.rawValue: true,
        Keys.contextShowMessageReplies.rawValue: true,
        Keys.contextShowJson.rawValue: false,
        Keys.disableScrollToNextChannel.rawValue: false,
        Keys.disableScrollToNextTopic.rawValue: false,
        Keys.disableChatSwipeOptions.rawValue: false,
        Keys.disableDeleteChatSwipeOption.rawValue: false,
        Keys.disableGalleryCamera.rawValue: false,
        Keys.disableGalleryCameraPreview.rawValue: false,
        Keys.disableSendAsButton.rawValue: false,
        Keys.disableSnapDeletionEffect.rawValue: false,
        Keys.stickerSize.rawValue: 100,
        Keys.stickerTimestamp.rawValue: true,
        Keys.hideRecordingButton.rawValue: false,
        Keys.hideTabBar.rawValue: false,
        Keys.showDC.rawValue: false,
        Keys.showCreationDate.rawValue: true,
        Keys.showRegDate.rawValue: true,
        Keys.regDateCache.rawValue: [:],
        Keys.compactChatList.rawValue: false,
        Keys.chatListLines.rawValue: ChatListLines.defaultValue.rawValue,
        Keys.compactFolderNames.rawValue: false,
        Keys.allChatsTitleLengthOverride.rawValue: AllChatsTitleLengthOverride.none.rawValue,
//        Keys.allChatsFolderPositionOverride.rawValue: AllChatsFolderPositionOverride.none.rawValue
        Keys.allChatsHidden.rawValue: false,
        Keys.defaultEmojisFirst.rawValue: false,
        Keys.messageDoubleTapActionOutgoing.rawValue: MessageDoubleTapAction.default.rawValue,
        Keys.messageDoubleTapActionIncoming.rawValue: MessageDoubleTapAction.default.rawValue,
        Keys.wideChannelPosts.rawValue: false,
        Keys.forceEmojiTab.rawValue: false,
        Keys.hideChannelBottomButton.rawValue: false,
        Keys.secondsInMessages.rawValue: false,
        Keys.forceSystemSharing.rawValue: false,
        Keys.confirmCalls.rawValue: true,
        Keys.videoPIPSwipeDirection.rawValue: VideoPIPSwipeDirection.up.rawValue,
        Keys.messageFilterKeywords.rawValue: [],
        Keys.notifyKeywords.rawValue: [],
        Keys.quickReplies.rawValue: [],
        Keys.ghostScheduleEnabled.rawValue: false,
        Keys.ghostScheduleFromHour.rawValue: 0,
        Keys.ghostScheduleToHour.rawValue: 7,
        Keys.keywordAlertSound.rawValue: true,
        Keys.preferLocalSearch.rawValue: true,
        Keys.keepOneTimeMedia.rawValue: false,
        Keys.perChatGhostPeerIds.rawValue: [],
        Keys.inputToolbar.rawValue: false,
        Keys.primaryUserId.rawValue: "",
        Keys.dismissedSGSuggestions.rawValue: [],
        Keys.duckyAppIconAvailable.rawValue: true,
        Keys.transcriptionBackend.rawValue: TranscriptionBackend.default.rawValue,
        Keys.translationBackend.rawValue: TranslationBackend.default.rawValue,
        Keys.customAppBadge.rawValue: "",
        Keys.canUseNY.rawValue: false,
        Keys.nyStyle.rawValue: NYStyle.default.rawValue,
        Keys.wideTabBar.rawValue: false,
        Keys.tabBarSearchEnabled.rawValue: true,
        Keys.hideStories.rawValue: false,
        Keys.warnOnStoriesOpen.rawValue: false,
        Keys.showProfileId.rawValue: true,
        Keys.sendWithReturnKey.rawValue: false
    ]
    
    public static let groupDefaultValues: [String: Any] = [
        Keys.legacyNotificationsFix.rawValue: false,
        Keys.pinnedMessageNotifications.rawValue: PinnedMessageNotificationsSettings.default.rawValue,
        Keys.mentionsAndRepliesNotifications.rawValue: MentionsAndRepliesNotificationsSettings.default.rawValue,
        Keys.status.rawValue: 1,
        Keys.showRepostToStoryV2.rawValue: true,
    ]
    
    @UserDefault(key: Keys.hidePhoneInSettings.rawValue)
    public var hidePhoneInSettings: Bool
    
    @UserDefault(key: Keys.showTabNames.rawValue)
    public var showTabNames: Bool
    
    @UserDefault(key: Keys.startTelescopeWithRearCam.rawValue)
    public var startTelescopeWithRearCam: Bool
    
    @UserDefault(key: Keys.accountColorsSaturation.rawValue)
    public var accountColorsSaturation: Int32
    
    @UserDefault(key: Keys.uploadSpeedBoost.rawValue)
    public var uploadSpeedBoost: Bool
    
    @UserDefault(key: Keys.downloadSpeedBoost.rawValue)
    public var downloadSpeedBoost: String
    
    @UserDefault(key: Keys.rememberLastFolder.rawValue)
    public var rememberLastFolder: Bool
    
    // Disabled while Telegram is migrating to Glass
    // @UserDefault(key: Keys.bottomTabStyle.rawValue)
    public var bottomTabStyle: String {
        set {}
        get {
            return BottomTabStyleValues.ios.rawValue
        }
    }
    
    public var lastAccountFolders = UserDefaultsBackedDictionary<String, Int32>(userDefaultsKey: Keys.lastAccountFolders.rawValue, threadSafe: false)


    /// Returns the local alias for a peer, or nil when none is set or it is blank.
    // MARK: DarkGram
    // Display-title lookup runs on every name drawn, concurrently from many threads.
    // UserDefaultsBackedDictionary cannot serve that: its lazy load mutates the cached
    // container while holding only a READ lock, so concurrent first-touches race and corrupt
    // it. This snapshot is plain immutable state behind a real mutex, refreshed on write.
    private static let aliasCacheLock = NSLock()
    private static var aliasCache: [String: String]?

    private func aliasSnapshot() -> [String: String] {
        SGSimpleSettings.aliasCacheLock.lock()
        defer { SGSimpleSettings.aliasCacheLock.unlock() }
        if let cached = SGSimpleSettings.aliasCache {
            return cached
        }
        let loaded = (UserDefaults.standard.dictionary(forKey: Keys.contactAliases.rawValue) as? [String: String]) ?? [:]
        SGSimpleSettings.aliasCache = loaded
        return loaded
    }

    private func invalidateAliasCache() {
        SGSimpleSettings.aliasCacheLock.lock()
        SGSimpleSettings.aliasCache = nil
        SGSimpleSettings.aliasCacheLock.unlock()
    }

    public func contactAlias(forPeerId peerId: Int64) -> String? {
        let snapshot = self.aliasSnapshot()
        guard let alias = snapshot[String(peerId)], !alias.isEmpty else {
            return nil
        }
        return alias
    }

    /// MARK: DarkGram - free-form private notes about a peer, keyed by peer id.
    /// Read straight from UserDefaults for the same reason aliases are: the backing dictionary
    /// type mutates its cache under a read lock, which is unsafe under concurrency.
    public func contactNote(forPeerId peerId: Int64) -> String? {
        let stored = (UserDefaults.standard.dictionary(forKey: Keys.contactNotes.rawValue) as? [String: String]) ?? [:]
        guard let note = stored[String(peerId)], !note.isEmpty else {
            return nil
        }
        return note
    }

    public func setContactNote(_ note: String?, forPeerId peerId: Int64) {
        let key = String(peerId)
        var stored = (UserDefaults.standard.dictionary(forKey: Keys.contactNotes.rawValue) as? [String: String]) ?? [:]
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed = trimmed, !trimmed.isEmpty {
            stored[key] = trimmed
        } else {
            stored.removeValue(forKey: key)
        }
        UserDefaults.standard.set(stored, forKey: Keys.contactNotes.rawValue)
    }

    public func setContactAlias(_ alias: String?, forPeerId peerId: Int64) {
        let key = String(peerId)
        var stored = (UserDefaults.standard.dictionary(forKey: Keys.contactAliases.rawValue) as? [String: String]) ?? [:]
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed = trimmed, !trimmed.isEmpty {
            stored[key] = trimmed
        } else {
            stored.removeValue(forKey: key)
        }
        UserDefaults.standard.set(stored, forKey: Keys.contactAliases.rawValue)
        self.invalidateAliasCache()
    }
    
    @UserDefault(key: Keys.localDNSForProxyHost.rawValue)
    public var localDNSForProxyHost: Bool
    
    @UserDefault(key: Keys.sendLargePhotos.rawValue)
    public var sendLargePhotos: Bool
    
    @UserDefault(key: Keys.outgoingPhotoQuality.rawValue)
    public var outgoingPhotoQuality: Int32

    @UserDefault(key: Keys.hideStories.rawValue)
    public var hideStories: Bool

    @UserDefault(key: Keys.warnOnStoriesOpen.rawValue)
    public var warnOnStoriesOpen: Bool
    
    @UserDefault(key: Keys.storyStealthMode.rawValue)
    public var storyStealthMode: Bool
    
    @UserDefault(key: Keys.canUseStealthMode.rawValue)
    public var canUseStealthMode: Bool    

    /// MARK: DarkGram - suppresses read receipts, typing activity and online presence.
    @UserDefault(key: Keys.ghostMode.rawValue)
    public var ghostMode: Bool

    /// MARK: DarkGram - views stories without reporting them as seen.
    @UserDefault(key: Keys.stealthStoryViews.rawValue)
    public var stealthStoryViews: Bool

    /// MARK: DarkGram - keep server-deleted messages in the local database.
    @UserDefault(key: Keys.keepDeletedMessages.rawValue)
    public var keepDeletedMessages: Bool

    /// MARK: DarkGram - record superseded texts when a message is edited.
    @UserDefault(key: Keys.keepEditHistory.rawValue)
    public var keepEditHistory: Bool

    /// MARK: DarkGram - ignore content protection on restricted chats.
    @UserDefault(key: Keys.bypassCopyProtection.rawValue)
    public var bypassCopyProtection: Bool

    /// MARK: DarkGram - ask before posting into a group or channel.
    @UserDefault(key: Keys.confirmSendToGroup.rawValue)
    public var confirmSendToGroup: Bool
    
    @UserDefault(key: Keys.disableSwipeToRecordStory.rawValue)
    public var disableSwipeToRecordStory: Bool   
    
    @UserDefault(key: Keys.quickTranslateButton.rawValue)
    public var quickTranslateButton: Bool
    
    public var outgoingLanguageTranslation = UserDefaultsBackedDictionary<String, String>(userDefaultsKey: Keys.outgoingLanguageTranslation.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.hideReactions.rawValue)
    public var hideReactions: Bool

    // @available(*, deprecated, message: "Use showRepostToStoryV2 instead")
    @UserDefault(key: Keys.showRepostToStory.rawValue)
    public var showRepostToStory: Bool

    @UserDefault(key: Keys.showRepostToStoryV2.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var showRepostToStoryV2: Bool

    @UserDefault(key: Keys.contextShowRestrict.rawValue)
    public var contextShowRestrict: Bool

    /*@UserDefault(key: Keys.contextShowBan.rawValue)
    public var contextShowBan: Bool*/

    @UserDefault(key: Keys.contextShowSelectFromUser.rawValue)
    public var contextShowSelectFromUser: Bool

    @UserDefault(key: Keys.contextShowSaveToCloud.rawValue)
    public var contextShowSaveToCloud: Bool

    @UserDefault(key: Keys.contextShowHideForwardName.rawValue)
    public var contextShowHideForwardName: Bool

    @UserDefault(key: Keys.contextShowReport.rawValue)
    public var contextShowReport: Bool

    @UserDefault(key: Keys.contextShowReply.rawValue)
    public var contextShowReply: Bool

    @UserDefault(key: Keys.contextShowPin.rawValue)
    public var contextShowPin: Bool

    @UserDefault(key: Keys.contextShowSaveMedia.rawValue)
    public var contextShowSaveMedia: Bool

    @UserDefault(key: Keys.contextShowMessageReplies.rawValue)
    public var contextShowMessageReplies: Bool
    
    @UserDefault(key: Keys.contextShowJson.rawValue)
    public var contextShowJson: Bool
    
    @UserDefault(key: Keys.disableScrollToNextChannel.rawValue)
    public var disableScrollToNextChannel: Bool

    @UserDefault(key: Keys.disableScrollToNextTopic.rawValue)
    public var disableScrollToNextTopic: Bool

    @UserDefault(key: Keys.disableChatSwipeOptions.rawValue)
    public var disableChatSwipeOptions: Bool

    @UserDefault(key: Keys.disableDeleteChatSwipeOption.rawValue)
    public var disableDeleteChatSwipeOption: Bool

    @UserDefault(key: Keys.disableGalleryCamera.rawValue)
    public var disableGalleryCamera: Bool

    @UserDefault(key: Keys.disableGalleryCameraPreview.rawValue)
    public var disableGalleryCameraPreview: Bool

    @UserDefault(key: Keys.disableSendAsButton.rawValue)
    public var disableSendAsButton: Bool

    @UserDefault(key: Keys.disableSnapDeletionEffect.rawValue)
    public var disableSnapDeletionEffect: Bool
    
    @UserDefault(key: Keys.stickerSize.rawValue)
    public var stickerSize: Int32
    
    @UserDefault(key: Keys.stickerTimestamp.rawValue)
    public var stickerTimestamp: Bool    

    @UserDefault(key: Keys.hideRecordingButton.rawValue)
    public var hideRecordingButton: Bool
    
    @UserDefault(key: Keys.hideTabBar.rawValue)
    public var hideTabBar: Bool

    @UserDefault(key: Keys.showProfileId.rawValue)
    public var showProfileId: Bool
    
    @UserDefault(key: Keys.showDC.rawValue)
    public var showDC: Bool
    
    @UserDefault(key: Keys.showCreationDate.rawValue)
    public var showCreationDate: Bool

    @UserDefault(key: Keys.showRegDate.rawValue)
    public var showRegDate: Bool

    public var regDateCache = UserDefaultsBackedDictionary<String, Data>(userDefaultsKey: Keys.regDateCache.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.compactChatList.rawValue)
    public var compactChatList: Bool

    @UserDefault(key: Keys.chatListLines.rawValue)
    public var chatListLines: String

    @UserDefault(key: Keys.compactFolderNames.rawValue)
    public var compactFolderNames: Bool
    
    @UserDefault(key: Keys.allChatsTitleLengthOverride.rawValue)
    public var allChatsTitleLengthOverride: String
//    
//    @UserDefault(key: Keys.allChatsFolderPositionOverride.rawValue)
//    public var allChatsFolderPositionOverride: String
    @UserDefault(key: Keys.allChatsHidden.rawValue)
    public var allChatsHidden: Bool

    @UserDefault(key: Keys.defaultEmojisFirst.rawValue)
    public var defaultEmojisFirst: Bool
    
    @UserDefault(key: Keys.messageDoubleTapActionOutgoing.rawValue)
    public var messageDoubleTapActionOutgoing: String

    // MARK: DarkGram
    // Upstream fixed the incoming gesture to the reaction, so the most common message in any
    // chat -- someone else's -- had no configurable gesture at all.
    @UserDefault(key: Keys.messageDoubleTapActionIncoming.rawValue)
    public var messageDoubleTapActionIncoming: String
    
    @UserDefault(key: Keys.wideChannelPosts.rawValue)
    public var wideChannelPosts: Bool

    @UserDefault(key: Keys.forceEmojiTab.rawValue)
    public var forceEmojiTab: Bool
    
    @UserDefault(key: Keys.forceBuiltInMic.rawValue)
    public var forceBuiltInMic: Bool
    
    @UserDefault(key: Keys.secondsInMessages.rawValue)
    public var secondsInMessages: Bool
    
    @UserDefault(key: Keys.hideChannelBottomButton.rawValue)
    public var hideChannelBottomButton: Bool

    @UserDefault(key: Keys.forceSystemSharing.rawValue)
    public var forceSystemSharing: Bool

    @UserDefault(key: Keys.confirmCalls.rawValue)
    public var confirmCalls: Bool
    
    @UserDefault(key: Keys.videoPIPSwipeDirection.rawValue)
    public var videoPIPSwipeDirection: String

    @UserDefault(key: Keys.legacyNotificationsFix.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var legacyNotificationsFix: Bool
    
    @UserDefault(key: Keys.status.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var status: Int64

    public var ephemeralStatus: Int64 = 1
    
    @UserDefault(key: Keys.messageFilterKeywords.rawValue)
    public var messageFilterKeywords: [String]

    /// MARK: DarkGram - words that raise a local notification wherever they appear,
    /// including in muted chats.
    @UserDefault(key: Keys.notifyKeywords.rawValue)
    public var notifyKeywords: [String]

    /// MARK: DarkGram - canned reply texts offered from the input toolbar.
    @UserDefault(key: Keys.quickReplies.rawValue)
    public var quickReplies: [String]

    /// MARK: DarkGram - turn Ghost Mode on automatically during a nightly window.
    @UserDefault(key: Keys.ghostScheduleEnabled.rawValue)
    public var ghostScheduleEnabled: Bool

    @UserDefault(key: Keys.ghostScheduleFromHour.rawValue)
    public var ghostScheduleFromHour: Int32

    @UserDefault(key: Keys.ghostScheduleToHour.rawValue)
    public var ghostScheduleToHour: Int32

    /// MARK: DarkGram - give keyword alerts their own sound so they stand out.
    @UserDefault(key: Keys.keywordAlertSound.rawValue)
    public var keywordAlertSound: Bool

    /// MARK: DarkGram - search cached history before asking the server.
    @UserDefault(key: Keys.preferLocalSearch.rawValue)
    public var preferLocalSearch: Bool

    /// MARK: DarkGram - never consume one-time media, so it stays an ordinary message.
    @UserDefault(key: Keys.keepOneTimeMedia.rawValue)
    public var keepOneTimeMedia: Bool

    /// MARK: DarkGram - peers that are always treated as ghosted, whatever the global switch says.
    @UserDefault(key: Keys.perChatGhostPeerIds.rawValue)
    public var perChatGhostPeerIds: [String]

    /// The single source of truth for whether outgoing signals are suppressed right now.
    /// Combines the manual switch with the optional schedule; every network seam reads this
    /// rather than `ghostMode`, so the schedule cannot be forgotten at one of them.
    public var isGhostModeActive: Bool {
        if self.ghostMode {
            return true
        }
        guard self.ghostScheduleEnabled else {
            return false
        }
        let hour = Int32(Calendar.current.component(.hour, from: Date()))
        let from = self.ghostScheduleFromHour
        let to = self.ghostScheduleToHour
        if from == to {
            return false
        }
        if from < to {
            return hour >= from && hour < to
        }
        // Window crosses midnight, e.g. 23 -> 7.
        return hour >= from || hour < to
    }

    /// True when this specific peer is ghosted, either globally or by its own entry.
    public func isGhostModeActive(forPeerId peerId: Int64) -> Bool {
        if self.isGhostModeActive {
            return true
        }
        return self.perChatGhostPeerIds.contains(String(peerId))
    }

    public func setPerChatGhost(_ enabled: Bool, forPeerId peerId: Int64) {
        let key = String(peerId)
        var ids = self.perChatGhostPeerIds
        if enabled {
            if !ids.contains(key) {
                ids.append(key)
            }
        } else {
            ids.removeAll(where: { $0 == key })
        }
        self.perChatGhostPeerIds = ids
    }
    
    @UserDefault(key: Keys.inputToolbar.rawValue)
    public var inputToolbar: Bool

    @UserDefault(key: Keys.sendWithReturnKey.rawValue)
    public var sendWithReturnKey: Bool
    
    @UserDefault(key: Keys.pinnedMessageNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var pinnedMessageNotifications: String
    
    @UserDefault(key: Keys.mentionsAndRepliesNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var mentionsAndRepliesNotifications: String
    
    @UserDefault(key: Keys.primaryUserId.rawValue)
    public var primaryUserId: String

    @UserDefault(key: Keys.dismissedSGSuggestions.rawValue)
    public var dismissedSGSuggestions: [String]

    @UserDefault(key: Keys.duckyAppIconAvailable.rawValue)
    public var duckyAppIconAvailable: Bool

    @UserDefault(key: Keys.transcriptionBackend.rawValue)
    public var transcriptionBackend: String

    @UserDefault(key: Keys.translationBackend.rawValue)
    public var translationBackend: String

    @UserDefault(key: Keys.customAppBadge.rawValue)
    public var customAppBadge: String

    @UserDefault(key: Keys.canUseNY.rawValue)
    public var canUseNY: Bool

    @UserDefault(key: Keys.nyStyle.rawValue)
    public var nyStyle: String

    @UserDefault(key: Keys.wideTabBar.rawValue)
    public var wideTabBar: Bool
    
    @UserDefault(key: Keys.tabBarSearchEnabled.rawValue)
    public var tabBarSearchEnabled: Bool
}

extension SGSimpleSettings {
    public var isStealthModeEnabled: Bool {
        return storyStealthMode && canUseStealthMode
    }
    
    public static func makeOutgoingLanguageTranslationKey(accountId: Int64, peerId: Int64) -> String {
        return "\(accountId):\(peerId)"
    }
}

extension SGSimpleSettings {
    public var translationBackendEnum: SGSimpleSettings.TranslationBackend {
        return TranslationBackend(rawValue: translationBackend) ?? .default
    }
    
    public var transcriptionBackendEnum: SGSimpleSettings.TranscriptionBackend {
        return TranscriptionBackend(rawValue: transcriptionBackend) ?? .default
    }
}

extension SGSimpleSettings {
    public var isNYEnabled: Bool {
        return canUseNY && NYStyle(rawValue: nyStyle) != .default
    }
}

public func getSGDownloadPartSize(_ default: Int64, fileSize: Int64?) -> Int64 {
    let currentDownloadSetting = SGSimpleSettings.shared.downloadSpeedBoost
    // Increasing chunk size for small files make it worse in terms of overall download performance
    let smallFileSizeThreshold = 1 * 1024 * 1024 // 1 MB
    switch (currentDownloadSetting) {
        case SGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 512 * 1024
        case SGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 1024 * 1024
        default:
            return `default`
    }
}

public func getSGMaxPendingParts(_ default: Int) -> Int {
    let currentDownloadSetting = SGSimpleSettings.shared.downloadSpeedBoost
    switch (currentDownloadSetting) {
        case SGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            return 8
        case SGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            return 12
        default:
            return `default`
    }
}

public func sgUseShortAllChatsTitle(_ default: Bool) -> Bool {
    let currentOverride = SGSimpleSettings.shared.allChatsTitleLengthOverride
    switch (currentOverride) {
        case SGSimpleSettings.AllChatsTitleLengthOverride.short.rawValue:
            return true
        case SGSimpleSettings.AllChatsTitleLengthOverride.long.rawValue:
            return false
        default:
            return `default`
    }
}
