# FetchRequests

FetchRequests is an eventing library inspired by NSFetchedResultsController and written in Swift.

[![Build Status](https://img.shields.io/travis/crewos/FetchRequests/main)](https://travis-ci.com/crewos/FetchRequests)
[![codecov](https://img.shields.io/codecov/c/github/crewos/FetchRequests/main)](https://codecov.io/gh/crewos/FetchRequests)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/FetchRequests)](https://cocoapods.org/pods/FetchRequests)
[![Carthage Compatible](https://img.shields.io/badge/carthage-compatible-4BC51D)](https://github.com/Carthage/Carthage)
[![Platform](https://img.shields.io/cocoapods/p/FetchRequests)](https://cocoapods.org/pods/FetchRequests)
[![Pod License](https://img.shields.io/cocoapods/l/FetchRequests)](https://opensource.org/licenses/MIT)

- [Features](#features)
- [Usage](#usage)
- [Requirements](#requirements)
- [Communication](#communication)
- [Installation](#installation)
- [License](#license)

## Features

- [x] Sort and section a list of items
- [x] Listen for live updates
- [x] Animate underlying data changes
- [x] Fetch associated values in batch
- [x] Support paginated requests
- [x] SwiftUI Integration
- [x] Comprehensive Unit Test Coverage

## Usage

FetchRequests can be used for any combination of networking, database, and file queries.
It is best when backed by something like a [WebSocket](https://en.wikipedia.org/wiki/WebSocket) where you're expecting your data to live update.

To get started, you create a `FetchRequest` which explains your data access patterns.
The `FetchedResultsController` is the interface to access the your data.
It will automatically cache your associated values for the lifetime of that controller.
If a memory pressure event occurs, it will release its hold on those objects, allowing them to be de-inited.

The example app has an UserDefaults-backed storage mechanism.
The unit tests have in-memory objects, with NotificationCenter eventing.

Today, it is heavily dependent on the Obj-C runtime, as well as Key-Value Observation.
It should be possible to further remove those restrictions, and some effort has been made to remove them.

### SwiftUI

There are two SwiftUI Property Wrappers available for use, `FetchableRequest` and `SectionedFetchableRequest`. These are analagous to CoreData's property wrappers.

The controller will perform a fetch once and only once upon the first view render. After that point, it is dependent upon live update events.

Examples:

```swift
struct AllUsersView: View {
    @FetchableRequest(
        fetchRequest: FetchRequest(request: User.fetchAll),
        sortDescriptors: [
            NSSortDescriptor(
                key: #keyPath(User.name),
                ascending: true,
                selector: #selector(NSString.localizedStandardCompare)
            ),
        ]
    )
    private var members: FetchableResults<User>

    // ...
}
```

For more complicated use cases, you probably will need to write initializers for your view, for example:

```swift
struct MembersView: View {
    private let fromID: EntityID

    @FetchableRequest
    private var members: FetchableResults<Membership>

    func init(fromID: EntityID) {
        self.fromID = fromID
        _members = FetchableRequest(
            fetchRequest: Membership.fetchRequest(from: fromID, toEntityType: .user)
        )
    }

    // ...
}
```

## Requirements

- iOS 13+ / macOS 10.15+ / tvOS 13+ / watchOS 6+
- Xcode 12+
- Swift 5+

## Communication

- If you **found a bug**, open an issue.
- If you **have a feature request**, open an issue.
- If you **want to contribute**, submit a pull request.

## Installation

### CocoaPods

Install with [CocoaPods](http://cocoapods.org) by specifying the following in your `Podfile`:

```ruby
pod 'FetchRequests', '~> 4.0'
```

### Carthage

Install with [Carthage](https://github.com/Carthage/Carthage) by specify the following in your `Cartfile`:

```
github "crewos/FetchRequests" ~> 4.0
```

### Swift Package Manager

Install with [Swift Package Manager](https://swift.org/package-manager/) by adding it to the `dependencies` value of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/crewos/FetchRequests.git", from: "4.0.0")
]
```

## License

FetchRequests is released under the MIT license. [See LICENSE](https://github.com/crewos/FetchRequests/blob/main/LICENSE) for details.
