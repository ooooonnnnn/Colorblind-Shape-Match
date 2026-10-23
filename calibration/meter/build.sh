#!/bin/sh
# Builds calibration/meter.apk, the Shape Match Meter app, with the Android
# SDK's own tools: no Gradle or Android Studio. The game serves the APK to the
# phone (see scripts/calibration_link.gd). Run from Git Bash:
#   sh calibration/meter/build.sh
# Paths default to this machine's setup (see CLAUDE.md) and can be overridden.
set -e
SDK="${ANDROID_SDK:-$LOCALAPPDATA/Android/Sdk}"
TOOLS="$SDK/build-tools/35.0.1"
ANDROID_JAR="$SDK/platforms/android-35/android.jar"
JDK="${JDK:-$LOCALAPPDATA/Programs/Java/jdk-17.0.20.1+1}"
KEYSTORE="${KEYSTORE:-$APPDATA/Godot/keystores/debug.keystore}"
export JAVA_HOME="$JDK"  # d8 and apksigner run on it
export PATH="$JDK/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/build"

rm -rf "$OUT"
mkdir -p "$OUT/classes"
"$JDK/bin/javac" --release 11 -Xlint:-options -classpath "$ANDROID_JAR" -d "$OUT/classes" $(find "$HERE/src" -name '*.java')
"$TOOLS/d8.bat" --release --min-api 24 --lib "$ANDROID_JAR" --output "$OUT" $(find "$OUT/classes" -name '*.class')
"$TOOLS/aapt2" link -o "$OUT/unsigned.apk" --manifest "$HERE/AndroidManifest.xml" -I "$ANDROID_JAR"
(cd "$OUT" && "$JDK/bin/jar" uf unsigned.apk classes.dex)
"$TOOLS/zipalign" -f -p 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"
"$TOOLS/apksigner.bat" sign --v4-signing-enabled false --ks "$KEYSTORE" --ks-pass pass:android --out "$HERE/../meter.apk" "$OUT/aligned.apk"
rm -rf "$OUT"
echo "Built $HERE/../meter.apk"
