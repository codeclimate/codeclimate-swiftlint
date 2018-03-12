# Code Climate SwiftLint Engine

`codeclimate-swiftlint` is a Code Climate engine that wraps the [SwiftLint](https://github.com/realm/SwiftLint) static analysis tool. You can run it on your command line using the Code Climate CLI, or on our hosted analysis platform.

### Installation

1. If you haven't already, [install the Code Climate CLI](https://github.com/codeclimate/codeclimate).
2. Enable the engine through the beta channel in your .codeclimate.yml file:
  ```yaml
  plugins:
    swiftlint:
      enabled: true
      channel: beta
  ```
3. You're ready to analyze! Browse into your project's folder and run `codeclimate analyze`.

### SwiftLint Config

`codeclimate-swiftlint` works with your existing `.swiftlint.yml` file. 
