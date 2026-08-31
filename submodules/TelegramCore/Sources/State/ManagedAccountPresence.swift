import SGSimpleSettings
import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


// MARK: DarkGram
/// Re-asserts offline right after activity the server reads as coming online.
///
/// Sending a message flips the account online server-side the instant it lands, and the
/// periodic heartbeat would not correct that until its next tick. Everyone watching saw the
/// account online for that whole window -- and kept seeing it until their own client
/// refreshed the chat, which is why it looked like the status was stuck rather than delayed.
/// Firing the correction on the send's completion closes the window to one round trip.
func darkGramReassertOffline(network: Network) {
    guard SGSimpleSettings.shared.isGhostModeActive else {
        return
    }
    let _ = network.request(Api.functions.account.updateStatus(offline: .boolTrue)).start()
}

private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    private var wasOnline: Bool = false
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        self.queue = queue
        self.network = network
        
        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            if self.wasOnline != value {
                self.wasOnline = value
                self.updatePresence(value)
            }
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
    }
    
    private func updatePresence(_ isOnline: Bool) {
        // MARK: DarkGram - ghost mode reports offline while the app is in use.
        //
        // The earlier attempt suppressed the online announcement and stopped the heartbeat with
        // it, which failed in practice: updatePresence runs only when the online state itself
        // changes, and toggling ghost mode is not such a change. Turning it on while already
        // online left the server believing you were online, with nothing scheduled to correct it.
        //
        // Keeping the heartbeat alive fixes both directions. Every 30 seconds it re-asserts the
        // current answer, so enabling ghost mode pushes "offline" without waiting for the app to
        // background, and disabling it restores presence just as quickly.
        let darkGramGhost = SGSimpleSettings.shared.isGhostModeActive
        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: darkGramGhost ? 10.0 : 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: darkGramGhost ? .boolTrue : .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
