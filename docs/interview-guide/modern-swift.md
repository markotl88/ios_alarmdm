# Part VI - Modern Swift and SwiftUI interview lab

This part supplies the SwiftUI and concurrency depth needed alongside the
repository walkthrough. **Current approach** means code present in this app.
**Alternative** means a proposed design, not a claim that it has shipped.
Complete examples below stand alone; excerpts with `...` are deliberately
incomplete. The deployment target is iOS 17.5, so Observation is available,
but this app currently uses Combine's `ObservableObject` and `@Published`.

## 19. SwiftUI: identity, ownership and updates

**Q. How should an experienced UIKit developer think about a View struct?**

**A.** It describes the UI for some inputs. It is not the persistent screen
object that a `UIViewController` is. SwiftUI can recreate the description
while retaining state in storage associated with the view's identity.
Re-evaluating `body` is neither destroying every underlying UIKit view nor
necessarily repainting every pixel. Dependency changes invalidate relevant
view computations; reconciliation then decides what needs updating.

**Project example.** `RootView` describes a sidebar or tab layout depending
on size class. Its `@StateObject playerViewModel` survives repeated `body`
evaluations at the same root identity. Starting audio, fetching the feed, or
writing SwiftData from `body` would make those effects repeat for reasons
unrelated to user intent. Keep rendering cheap and side-effect-free.

**Follow-up: Is a View initializer called only once?** No. Initializers may
run frequently. Do not interpret initializer/deinitializer logging of a
helper as proof of a screen's visible lifetime. UIKit's view-controller
lifecycle and SwiftUI identity are different abstractions.

**Q. What are structural and explicit identity?**

**A.** Structural identity comes from type and position in the hierarchy.
Explicit identity is supplied by an ID, including `ForEach`'s element IDs or
`.id(...)`. Identity determines which state storage SwiftUI reuses.

**Project example.** `RootView` gives `BookmarkToastView` `.id(bookmark.id)`.
A new capture intentionally gets fresh local state. By contrast, episode rows
must use the stable `Podcast.id`; a freshly generated UUID on each fetch would
turn updates into replacements, losing row state and disrupting animations.
`Podcast` equality includes mutable data, so equality is not a substitute for
stable identity. In UIKit terms, think stable diffable-data-source identifiers,
not array indexes or equality of the entire view model.

**Follow-up: Is `.id(UUID())` a harmless refresh trick?** No. It discards the
subtree's state on every reevaluation. Use explicit identity only when that
reset represents the domain, such as choosing a different episode editor.

**Q. What owns state in the current project?**

| Mechanism | Ownership and correct use here |
|---|---|
| `@State` | View-lifetime value storage: scrubber draft value and drag offset. |
| `@Binding` | A read/write connection to another owner's storage; not storage itself. |
| `@StateObject` | Owns the lifetime of a Combine observable model for a view identity. |
| `@ObservedObject` | Observes an externally owned model, such as `AppSettings.shared`. |
| `@EnvironmentObject` | Retrieves an ancestor-injected Combine model such as the player. |
| `@Environment` | Retrieves values or dependencies, such as size class and scene phase. |

**Project example, `PodcastEpisodesView.swift`:**

```swift
@StateObject private var viewModel: PodcastEpisodesViewModel

init(show: Show) {
    _viewModel = StateObject(
        wrappedValue: PodcastEpisodesViewModel(show: show)
    )
}
```

The declaration says this view owns the model's lifetime. The initializer
supplies its initial value through `StateObject`'s deferred construction.
Recreating the same view description does not replace the installed model.
However, changing `show` while preserving the *same identity* does not
reinitialize that model either. A destination must have appropriate show
identity, or explicitly update its model when its input changes.

**Trap.** `@ObservedObject var model = Model()` constructs a model whenever
that view value is constructed. The wrapper observes; it does not provide
stable ownership. It is not specifically `body` that calls the initializer.

**Q. Why does the scrubber keep local state instead of binding directly to the engine?**

**A.** `ScrubberView` in `FullscreenPlayerView.swift` owns a draft slider
value and an `isScrubbing` flag. During a drag, the user's draft is authoritative;
periodic playback reports must not pull the thumb back. On release it sends an
intent to seek; outside editing it can mirror engine progress again.

This is one source of truth per responsibility: the engine owns actual
playback, the control owns an in-progress gesture. A binding to engine time
would mix a user command with a measurement. The UIKit comparison is an
editable text field that does not replace its text on every server refresh
while the user is typing.

**Follow-up: Could a binding setter start an expensive request?** It can, but
controls may call it repeatedly. For a seek slider, commit on edit completion
or explicitly throttle. Keep the measurement path distinct from the command.

**Q. How would you migrate to Observation?**

**A. Current approach:** `PlayerViewModel` and the list models use
`ObservableObject`; changes announced through `objectWillChange` can invalidate
subscribers even when they do not display that particular property.

**Alternative, complete standalone illustration:**

```swift
import SwiftUI
import Observation

@MainActor @Observable
final class EpisodeFilter {
    var showsPlayed = false
}

@MainActor
struct FilterHost: View {
    @State private var filter = EpisodeFilter()

    var body: some View {
        FilterControl(filter: filter)
    }
}

@MainActor
struct FilterControl: View {
    @Bindable var filter: EpisodeFilter

    var body: some View {
        Toggle("Prikaži preslušane", isOn: $filter.showsPlayed)
    }
}
```

`@Observable` instruments property access and mutation. `@State` preserves the
owned instance for this view identity. `@Bindable` produces the writable
projection needed by `Toggle`; it does not own the instance. A child that
only reads the model may use an ordinary stored reference. Observation tracks
properties read while evaluating the view, so unrelated property changes need
not invalidate that view.

**Trade-off.** The real `AppSettings` also persists preferences; replacing it
with this illustrative model would lose that behavior. Migrate ownership and
persistence deliberately. Observation does not make a model thread-safe, and
it does not automatically replace Combine pipelines used by the recorder.
`@MainActor` answers isolation; `@Observable` answers observation.

**Follow-up: Must a View never own a service with `@State`?** That is too broad.
An owned `@Observable` reference can correctly live in `@State`. A service
whose lifetime must exceed the screen, such as the playback engine, belongs
in an app-level owner. An ordinary non-observable class in `@State` retains
its reference, but mutating its internal properties does not by itself notify
SwiftUI. Decide from lifetime and observation requirements, not from the name
"service".

**Q. Is the environment dependency injection or a service locator?**

**A.** It is a propagation mechanism with implicit lookup at consumption.
The app injects the player at the root so all descendant controls share it.
That avoids threading a parameter through every intermediate view, but hides
requirements from initializer signatures. A missing `@EnvironmentObject`
crashes at runtime, including in previews. Test and preview roots must inject
it. For domain services, explicit initializer injection makes dependencies
and test doubles easier to see; use environment for genuinely shared UI scope.
Typed Observation injection uses `.environment(model)` with
`@Environment(Model.self)`, not `@EnvironmentObject`.

**Q. How should navigation and presentation be modeled?**

**A. Current approach:** show selection leads to `PodcastEpisodesView`; the
expanded player is an overlay driven by `PlayerViewModel.isExpanded`, so audio
can continue across tab changes and collapse. This is presentation state, not
a second playback engine.

**Alternative:** if the app needs deep links and restoration of multi-step
routes, use a typed `NavigationStack` path whose values are stable domain IDs.
Resolve IDs at the destination and handle an episode missing from the local
cache. For a selected editor, `.sheet(item:)` makes the selected item and its
presentation one optional state value, avoiding contradictory booleans.

**Trade-off.** A navigation coordinator is useful when route policy is shared;
adding one just to wrap a two-screen stack adds indirection. Do not keep full
SwiftData model objects as navigation state across unrelated contexts.

**Q. How do `.task`, `onAppear`, and `scenePhase` differ?**

**A.** `onAppear` is a visibility callback and can run more than once. In the
current episode view it calls `fetchData()`, whose model must prevent duplicate
loads. `.task` starts async work associated with the view's lifetime and
requests cancellation when that lifetime ends; `.task(id:)` also restarts
when its ID changes. Cancellation is cooperative, not a guarantee that every
operation has stopped before the next one begins. `scenePhase` describes a
scene's activity, not whether a particular view is on screen.

**Project implication.** Re-fetching a list is appropriate view work. Audio
playback and recording a CarPlay listen cannot depend on a view task that may
not exist. `ListeningRecorder` therefore starts at application launch.

**Follow-up: Does `Task {}` inside `onAppear` inherit view cancellation?** No.
That creates an unstructured task. Keep and cancel its handle if that is the
intended ownership, or use the view's `.task` modifier for view-scoped work.

**Q. What would you profile before optimizing this UI?**

**A.** Reproduce scrolling with playback active, a long episode list, and
incoming store updates. Use Instruments to distinguish main-thread CPU, layout,
image decoding, database fetches, and excessive view invalidations. A frequent
`body` evaluation is evidence to investigate, not automatically a defect.

**Project example.** The player publishes progress frequently, while rows
mostly need current-episode identity and playback state. Splitting those
observations can reduce unnecessary work. Keep row IDs stable, avoid sorting
or fetching all episodes inside `body`, and decode/resize artwork once rather
than per frame. Measure release builds on a device as well as the simulator.
A 60 Hz frame is about 16.7 ms; 120 Hz leaves roughly half that time.

**Follow-up: Does `withAnimation` move work off the main actor?** No. It supplies
an animation transaction to state changes. It cannot make expensive synchronous
work cheap. Respect Reduce Motion, avoid animating every periodic time update,
and use transitions only when insertion/removal and identity are intentional.

**Q. How would you migrate a UIKit screen incrementally?**

**A.** Embed a SwiftUI feature in `UIHostingController`, keeping its dependencies
owned by the surrounding composition root. Expose explicit actions back to the
UIKit coordinator. In the other direction use `UIViewRepresentable` or
`UIViewControllerRepresentable`, with `make` for creation, `update` for applying
current inputs, a coordinator for delegates, and teardown for observers.
The coordinator must not keep stale copies of changing inputs or create a
retain cycle through callbacks. The repository already retains UIKit lifecycle
integration through `AppDelegate`; a rewrite of the whole app is unnecessary.

## 20. Concurrency: execution, cancellation and isolation

**Q. What actually happens at `await`?**

**A.** It marks a possible suspension point. If the operation suspends, the task
preserves its continuation and releases its executing thread to other work.
It resumes when the awaited operation completes, on the executor required by
isolation. It does not block a thread like a semaphore wait. An `await` may
complete without suspending; it is not a mandatory context switch.

**Project example.** An async replacement for `PodcastService` could suspend
while `URLSession` waits for network data. Decoding a large response remains
CPU work. Calling an `async` method does not automatically move decoding off
the main actor, and wrapping synchronous decoding in `Task {}` from a
main-actor context does not solve that problem.

**Version trap.** This project uses Swift 5 language mode. Swift 6.2's
`NonisolatedNonsendingByDefault` feature changes unannotated nonisolated async
execution to remain on the caller's actor; earlier semantics use the generic
executor. Check language mode and enabled features. With modern semantics,
`@concurrent` explicitly requests concurrent execution for CPU work. State the
configuration before claiming that a nonisolated async function leaves main.

**Q. How do structured and unstructured tasks differ?**

| Form | Lifetime and suitable project use |
|---|---|
| `async let` | Fixed child operations whose results are awaited before leaving scope. |
| Task group | Dynamic children, bounded by their enclosing scope. |
| `Task {}` | Unstructured task; caller owns lifecycle explicitly. Inherits surrounding isolation when applicable. |
| `Task.detached` | Unstructured; does not inherit actor isolation or task-local values. Requires an explicit ownership and cancellation plan. |

**A.** Child tasks cannot outlive their structured scope. Scope exit waits for
them, including after cancellation. An unstructured task is not automatically
cancelled because its creator returns or is cancelled. Detached does not mean
"dedicated thread" or "guaranteed faster". For this app, a screen load is
view-owned work; a download intentionally continuing after navigation needs
an application-level owner and a user-visible cancel operation.

**Follow-up: Does a throwing group instantly stop siblings?** No. When an
error propagates out of the group body, remaining children are cancelled and
awaited. Children must cooperate. You must consume throwing results; an error
is not a magical immediate broadcast just because a child throws. A race that
returns the first answer still waits for cancelled children to finish before
leaving its structured scope.

**Q. What is cooperative cancellation?**

**A.** `cancel()` records a cancellation request. Code checks
`Task.isCancelled`, calls `Task.checkCancellation()`, or awaits an API that
responds to cancellation. A CPU loop must check periodically. Cleanup still
runs. Cancellation is distinct from a user-visible network failure.

**Project alternative.** A feed request should cancel when its screen-owned
task disappears. A response for an old show must never overwrite a newer
selection. Use cancellation *and* a request identity check: callback adapters
may not stop promptly, and an old result can race a new request.

**Follow-up: Is weak self sufficient?** No. `guard let self` before a long
`await` holds the object strongly through that suspension. A model holding a
task whose closure holds the model can keep itself alive indefinitely,
especially when consuming an endless stream. Capture a service independently,
use an explicit owner to cancel, and avoid relying only on `deinit` to break a
cycle that prevents `deinit` from running.

**Q. How would an async network boundary look here?**

**A. Current approach:** `NetworkManaging` uses callbacks and has inconsistent
callback-queue contracts across overloads. Its API does not expose the task
needed to cancel a request. The review fixes session construction so the
configured timeouts actually apply; it does not silently migrate callers to
async/await.

**Alternative, standalone example:**

```swift
import Foundation

enum FeedFailure: Error {
    case invalidResponse
    case http(Int)
}

struct FeedClient: Sendable {
    func data(for url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw FeedFailure.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedFailure.http(http.statusCode)
        }
        return data
    }
}
```

The request carries its timeout before submission. The suspension waits for
transport. The cancellation check prevents processing a just-cancelled result.
HTTP validation is explicit because a completed transport can still return a
500 response. Returning `Data` separates transport from decoding and state
mutation. The real app would inject a session for protocol-based tests rather
than hard-code `.shared`.

**Trade-off.** `data(for:)` buffers the response. For large media use download
APIs or streaming bytes, not whole-file `Data` in memory. Retry idempotent feed
reads with bounded backoff; do not treat cancellation as a reason to retry.
Keep cached episodes visible on failure and offer an actionable retry state.

**Q. What does `@MainActor` guarantee?**

**A.** It establishes isolation for state and operations, with main-executor
serialization. In Swift concurrency, accessing isolated state from outside
requires crossing that boundary appropriately. It is not a spell that makes
an arbitrary synchronous legacy callback hop queues. Annotate the owner and
adapt callback entry points deliberately; enable strict concurrency checking
to find violations rather than assuming runtime thread conventions suffice.

**Project example.** Playback state, UI models, and the current synchronous
store layer are intended for main-thread access. AVFoundation completion
callbacks need an explicit hop before changing `@Published` properties. The
seek review adds that hop and invalidates old completions on teardown.

**Follow-up: Should decoding run on MainActor?** Small decoding may be fine;
measure. Large decoding and full-library transformations can block input even
inside an async method. Move CPU work to a deliberately non-main execution
boundary and transfer value snapshots back. Never move a live `ModelContext`
or managed model instance into a detached task just to silence a hang.

**Q. Are actors transactions across an `await`?**

**A.** No. They serialize access to isolated state, but can process other work
while a method is suspended. This reentrancy is useful for throughput and
requires rechecking assumptions after suspension.

**Alternative example: deduplicating feed downloads.** An actor checks whether
an episode is downloaded, awaits the network, and then writes the path. Another
request can arrive during that await and also start a download. Record an
in-flight task *before* suspension, or recheck and resolve duplication after
suspension. Make failure remove that in-flight entry so retry is possible.

**Follow-up: Does an actor have its own thread?** No. An actor provides an
isolation domain and executor scheduling, not a dedicated OS thread. Actors
also do not solve cross-device ordering: the CloudKit merge policy is still
necessary because two processes do not share an actor.

**Q. What is Sendable, and what is it not?**

**A.** It describes values safe to transfer across concurrency domains.
Compiler-checked value types require their stored values to satisfy the relevant
rules; an immutable reference or synchronized reference can also be suitable.
`@Sendable` constrains closure captures. It is not a scheduling mechanism and
does not mean "run in the background".

**Project example.** Prefer passing an episode ID or immutable DTO into a
background worker and returning a value result. `Podcast` is a useful candidate
for a checked conformance after auditing its stored properties. SwiftData
entities and contexts are not interchangeable with those snapshots.
`@unchecked Sendable` is a manual proof obligation, not a warning suppression
strategy. Audit all mutation paths and callbacks before using it.

**Q. How do you bridge a one-shot callback with a continuation?**

**A.** A checked throwing continuation suspends the task and must be resumed
exactly once, with a result or error. It does not add cancellation to the
callback API. A correct adapter needs the underlying cancel handle, a
cancellation handler, and synchronization for completion-versus-cancel races.
Cancellation can arrive before that handle is installed. Both paths must
share a once-only completion state.

**Project trap.** `NetworkManaging` currently returns `Void`, so a naive
`withCheckedThrowingContinuation` wrapper cannot cancel the underlying request.
Expose the task or use native async URLSession APIs. A seek callback that is
intentionally dropped when superseded is also unsuitable for direct wrapping
unless supersession explicitly resumes the continuation with cancellation.

**Follow-up: When is an unsafe continuation appropriate?** Only after a measured
need and a proven exactly-once contract. Checked continuations help diagnose
misuse; neither kind repairs missing callbacks or races automatically.

**Q. When would AsyncSequence or AsyncStream help?**

**A.** An async sequence supplies multiple values over time through `for await`.
For this app, download progress or live metadata is a better fit than a
one-shot continuation. `AsyncThrowingStream` can additionally end with an
error. A stream does not automatically make its producer structured or cancel
external observers when the consumer leaves.

**Alternative design.** Adapt a download delegate into a progress stream with
`.bufferingNewest(1)` because the UI needs the latest percentage, not thousands
of stale samples. Use `onTermination` to release the delegate/observation and
cancel work if this stream owns it. Serialize cleanup with delegate callbacks;
termination may arrive on a different executor. Finish the stream on completion
and handle its terminal result separately from progress.

**Trade-off.** Dropping intermediate *events* can lose information, so do not
reuse that buffering policy for bookmark commands. Multiple consumers of one
AsyncStream are not automatically a multicast state publisher. Keep Combine
where its current-value and multicast semantics are part of the contract, or
explicitly design those semantics in the replacement.

**Q. How would you test async behavior without arbitrary sleeps?**

**A.** Inject a transport, clock, and storage boundary. Suspend a fake request
until the test releases it; change the selection; complete the obsolete request;
assert it cannot overwrite the new state. Cancel during a request and assert
cleanup and the absence of a displayed cancellation error. For time-based
metadata expiry, advance an injected clock instead of waiting ten minutes.
Use async XCTest fulfillment when the producer needs the main actor; blocking
that actor waiting for work scheduled on it can deadlock.

**Project connection.** Existing tests inject engine and store protocols and
use expectations for real AVPlayer behavior. Keep a small framework integration
suite because a fake engine cannot prove seek semantics. Add a regression test
that stops or replaces the player before an outstanding completion arrives.
Use Thread Sanitizer and Instruments for additional evidence; passing a unit
test is not proof that every callback is race-free.

## 21. A three-to-five-minute project walkthrough

**Q. Tell me about this project and the decisions you would defend.**

**A.** AlarmDM is a radio and podcast client with live audio, downloaded
listening, favorites, and bookmarks. The same product supports iPhone, iPad,
Mac, and CarPlay. The engineering problem is making one listening session
behave consistently across UI entry points and eventually across devices.

The playback engine owns the active AVPlayer, audio-session interaction and
Now Playing integration. The phone UI, CarPlay and remote commands all issue
intents through it. The UI does not own the lifetime of playback. A separate
ListeningRecorder observes the engine and persists progress even when CarPlay
launches the application without a phone window. That boundary came from a
real failure: audio worked in the car while nobody saved where it got to.

SwiftUI uses view-owned observable presentation models and a shared player
facade. Lists operate on value snapshots, with stable IDs rather than generated
identities on every refresh. The scrubber temporarily owns a gesture draft so
periodic playback observations cannot fight the user's drag. Wide layouts use
a sidebar and persistent player area; phone layouts use tabs and an expanded
player overlay. UI adaptation does not duplicate playback policy.

SwiftData has two store configurations. Reproducible feed data and device-local
file paths stay local; listening state and bookmarks sync through CloudKit.
The repository folds duplicate state rows consistently for both list and
single-episode reads. The current position selection uses timestamps; boolean
flags are merged with OR. That is a deliberate but incomplete conflict policy:
removing a favorite needs a more expressive versioned decision, and equal
timestamps need a deterministic tie-breaker before claiming full convergence.
CloudKit transport does not remove those domain decisions.

Networking is still callback-based. The near-term correctness fix is creating
a URLSession with its configured timeouts, rather than mutating the copy
returned by an existing session. The next architectural step is explicit
isolation and cancellation-aware request APIs, with DTOs crossing execution
boundaries. I would keep framework ownership and domain behavior stable while
migrating, rather than rewrite all layers at once.

Testing follows those boundaries: fake engine/store tests cover playback and
sync decisions; in-memory and two-container tests cover repository behavior;
a small real-player test checks EOF and replay assumptions. These do not prove
CloudKit delivery, device audio interruption behavior, or every UI layout, so
release validation still includes devices and platform-specific interaction.
For performance I would measure main-thread stalls and repeated observation
updates while scrolling with audio active. For memory I would trace observer
tokens, subscriptions and long-lived task ownership. My next improvements are
compiler-enforced isolation, visible storage fallback, cancellation-aware
networking, and a conflict policy for reversible user decisions.

## 22. Interview cheat sheet

| Topic | Answer to remember |
|---|---|
| View value | A description; identity-backed storage outlives many descriptions. |
| Identity | Stable domain ID; changing identity intentionally resets local state. |
| State / Binding | Owned storage versus access to another owner's storage. |
| StateObject | Stable owner of a Combine observable model for one view identity. |
| Observation | Tracks property reads; `@State` owns, `@Bindable` exposes bindings. |
| Environment | Shared UI scope; explicit injection remains useful for services/tests. |
| Lifecycle | `onAppear` repeats; `.task` requests cancellation; playback outlives views. |
| Await | Possible suspension, not a blocking wait or automatic background thread. |
| Structured work | Children are scoped and awaited; cancellation is cooperative. |
| Task / detached | Unstructured; define ownership, retention and cancellation explicitly. |
| MainActor | Isolation; CPU work can still block UI even inside an async method. |
| Actors | Serialized state access; invariants spanning await must be rechecked. |
| Sendable | Transfer safety, not scheduling; audit captured and stored references. |
| Continuation | Exactly once; cancellation and callback races need a real design. |
| AsyncStream | Lifetime, cleanup and buffering are part of the API contract. |
| Persistence | Confine contexts; move snapshots/IDs across isolation boundaries. |
| Networking | Validate HTTP, distinguish cancellation, bound retries, preserve cache. |
| Memory | Trace owner to task/subscription to closure to owner; weak is not enough. |
| Performance | Profile release builds; body counts alone are not frame-cost evidence. |
| Testing | Control time/completions; supplement fakes with real framework tests. |
| Architecture | Explain ownership, lifetime, failure policy and a concrete trade-off. |

## Primary references and verification notes

Use these primary references to check platform claims against the SDK being
used; the codebase's Swift language mode is not the same as the compiler version.

- SwiftUI model data: https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
- Swift language concurrency: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/
- Swift SE-0461, async isolation semantics: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
- AVPlayer seek completion: https://developer.apple.com/documentation/avfoundation/avplayer/seek(to:completionhandler:)
- App Tracking Transparency scope: https://developer.apple.com/app-store/user-privacy-and-data-use/

The modern examples are alternatives, not excerpts from shipped production
code. Existing historical excerpts document the behavior at the cited commit.
The review corrects claims where those comments or narratives overstated what
the implementation or a test actually proves.
