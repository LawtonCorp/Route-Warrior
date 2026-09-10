# Design sources

`AppIcon.svg` is the source of the app icon (D-048). To re-render the
1024×1024 PNG the asset catalog needs, screenshot it with headless
Chromium at a 1024×1024 window (Playwright's `headless_shell` works;
`--window-size=1024,1024 --screenshot=AppIcon.png file://…/AppIcon.svg`),
then replace `App/RouteWarrior/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
iOS rounds the corners itself; the source stays square.
