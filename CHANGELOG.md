# Change Log
All notable changes to this project will be documented in this file.
`FetchRequests` adheres to [Semantic Versioning](https://semver.org/).

## 4.0
In Progress

* Updated minimum SDKs to iOS 13 and related OSes
* Added a Swift 5.5 package definition
* Added Identifiable conformance to FetchedResultsSection
* Added `objectWillChange` and `objectDidChange` Publishers to all Controllers 
* Removed FRIdentifiable in deference to Identifiable
* Removed simplediff in deference to BidirectionalCollection.difference(from:)

## [3.2.0](https://github.com/crewos/FetchRequests/releases/tag/3.2.0)
Released on 2021-06-21

* Added FetchableRequest SwiftUI Property Wrapper and friends

## [3.1.1](https://github.com/crewos/FetchRequests/releases/tag/3.1.1)
Released on 2021-05-19

* Fix warnings related to deprecation of using `class` in protocol definitions

## [3.1](https://github.com/crewos/FetchRequests/releases/tag/3.1)
Released on 2021-01-15

* Add `func resort(using newSortDescriptors: [NSSortDescriptor])`

## [3.0.2](https://github.com/crewos/FetchRequests/releases/tag/3.0.2)
Released on 2020-11-19

* Expose test target in Swift Package Manager
* Fix thread safety bug with insertion

## [3.0.1](https://github.com/crewos/FetchRequests/releases/tag/3.0.1)
Released on 2020-10-26

* Tweaked logging format

## [3.0](https://github.com/crewos/FetchRequests/releases/tag/3.0)
Released on 2020-09-15

* Renamed Identifiable to FRIdentifiable to avoid naming collisions with Swift.Identifiable
* Changed to require Xcode 12, and increased the minimum OS by 2, so iOS 14, tvOS 14, macOS 10.14, & watchOS 5
* RawDataRepresentable.RawData is now an associatedtype as the tests execute cleanly in Xcode 12
* Note: The JSON type is still being vended by this framework

## [2.2.1](https://github.com/crewos/FetchRequests/releases/tag/2.2.1)
Released on 2020-09-02

* Made Sequence.sorted(by comparator: Comparator) private

## [2.2](https://github.com/crewos/FetchRequests/releases/tag/2.2)
Released on 2019-12-05

* BoxedJSON.init(__object: NSObject?) for Obj-C uses

## [2.1](https://github.com/crewos/FetchRequests/releases/tag/2.1)
Released on 2019-12-02

* Support NS(Secure)Coding in BoxedJSON

## [2.0](https://github.com/crewos/FetchRequests/releases/tag/2.0)
Released on 2019-11-15

* Change `objectID` to `id`
* Remove a bunch of KVO requirements and weird conformance rules
* Remove the CW prefix from everything
* Change the `RawData` type from `[String: Any]` to `JSON`
    * `JSON` is an equatable struct
    * It supports dynamic member lookup
    * It does lazy initialization and lookup, so it's very cheap
    * It is bridgeable to Obj-C, so you can still use KVO with it

Sadly, we still cannot make `data` an `associatedtype`. Something about it breaks the runtime.

## [1.0.2](https://github.com/crewos/FetchRequests/releases/tag/1.0.2)
Released on 2019-08-01.

* CWObservableNotificationCenterToken will automatically invalidate itself on deinit
* Added SwiftLint validation

## [1.0.1](https://github.com/crewos/FetchRequests/releases/tag/1.0.1)
Released on 2019-07-02.

* Adds an example app

## [1.0.0](https://github.com/crewos/FetchRequests/releases/tag/1.0.0)
Released on 2019-07-01.

#### Added
- Initial release of FetchRequests
