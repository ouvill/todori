#!/bin/sh

set -eu

emulator_port=${EMULATOR_PORT:-5554}
device_id=${ANDROID_SERIAL:-emulator-$emulator_port}

adb -s "$device_id" wait-for-device

cd app/android
./gradlew -Ptarget-platform=android-x64 connectedDebugAndroidTest

cd ..
flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/device_key_rotation_test.dart \
    -d "$device_id" \
    --profile
flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/device_key_rotation_test.dart \
    -d "$device_id" \
    --profile
