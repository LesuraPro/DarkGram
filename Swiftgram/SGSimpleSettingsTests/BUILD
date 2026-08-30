load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: DarkGram
# Deliberately a separate package from SGSimpleSettings. The app build resolves
# //Swiftgram/SGSimpleSettings:SGSimpleSettings and never reaches here, so a mistake in this
# file cannot take the IPA build down with it -- which matters when a build costs an hour.
#
# Run it on its own:
#   Make.py test --target //Swiftgram/SGSimpleSettingsTests:SGSimpleSettingsTests

swift_library(
    name = "SGSimpleSettingsTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
    ],
)

ios_test_runner(
    name = "SGSimpleSettingsTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "SGSimpleSettingsTests",
    minimum_os_version = "13.0",
    runner = ":SGSimpleSettingsTestRunner",
    deps = [
        ":SGSimpleSettingsTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)
