# Design sources

The app icon is Brian's "design 6C": a yellow navigation arrow with a
violet ghost arrow behind it, on a near-black ground (D-049). The three
SVGs here are the sources for the light, dark and tinted variants; the
1024×1024 PNGs in `App/RouteWarrior/Assets.xcassets/AppIcon.appiconset/`
are their exports, declared with iOS 18 `appearances` in that folder's
`Contents.json` so Xcode builds every size from them.

Colours: ground #0e0e10, ghost arrow #7674f1, arrow #f1c40f. iOS rounds
the corners itself; the sources stay square.
