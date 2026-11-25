# Skyglide

A portrait Flutter game for Android. Tilt the top of the phone up to climb and down to descend. Each gate adds one point, and flying through the gold feather collects it. Every ten points advances the level. Flight speed increases with every gate through the 16th. Gate openings narrow every four points through the 40th. The title screen also supports vertical drag controls.

Moon Valley begins at level 8 (70 gates). Gates with glowing rims drift vertically. Three moon feathers charge a shield that absorbs contact with one gate.

Feathers also go into a balance saved on the phone across flights. After a crash, spend 50 feathers to continue at the same position, score and level. The gate that caused the crash is safe to pass on that continue. Starting a new flight is free.

Hold the playfield to boost up to 1.5× and release to return to cruise speed. In touch mode, drag immediately to steer at cruise speed, or hold briefly before dragging to boost. A second finger can boost independently. Fifteen courses unlock at levels 5, 10, and every fifth level through 75. The final course keeps remixing four-gate sequences.

Run `flutter run` on a connected Android device. Build the APK with `flutter build apk --release`. Run the sensor, collision and gameplay tests with `flutter test`.

The generated game art is in [assets/flight](assets/flight). The [artwork manifest](artwork.json) contains the ImageGen prompts.
