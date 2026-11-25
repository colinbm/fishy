# Fishy

A free game for cats on iPhone, iPad and Apple TV. A fish swims around a pond seen from above; when a paw
catches it, it splashes away and a new fish swims in from the edge. Every few minutes the fish also swims
off by itself and another arrives, which is all that happens on Apple TV.

No ads, no in-app purchases, no data collected. See [PRIVACY.md](PRIVACY.md).

## Support

Found a problem or have an idea? [Open an issue](https://github.com/colinbm/fishy/issues).

## Development

- `scripts/testflight.sh` archives, signs and uploads the iOS and tvOS builds to TestFlight
  (settings in `Config/testflight.conf`; API key in the git-ignored `Config/testflight.env`).
- `scripts/appstore.rb` fills in the App Store listing from `AppStore/metadata.json` and uploads
  `AppStore/screenshots`.
- `Tools/screenshots.sh` captures the screenshots on simulators; `Tools/make_icons.swift` draws the icons.
- Launch with `-swapSeconds 10` to make fish swap every 10 seconds instead of every 2–4 minutes.
