# GuitarCHUD

A floating chord window for macOS. It watches what Spotify is playing, pulls the
matching chords from Ultimate Guitar, and keeps them in front of your other
windows like a FaceTime PiP tile.

Native Swift + AppKit, no dependencies, no API keys, no login. Around 1,500
lines. Requires macOS 13+, the Spotify **desktop** app, and a guitar.

**Features:** every new song opens a ranked list of chord versions with the best
one already loaded · hover any chord for its fingering · transpose (diagrams
follow) · wrap long lines or let them run · scroll in time with the song ·
menu-bar item when the window is closed.

## Build & install

```bash
./build.sh                 # builds ./GuitarCHUD.app for this Mac
./build.sh /Applications   # builds straight into /Applications
./build.sh --share         # universal build + dist/GuitarCHUD.zip to send someone
```

`--share` builds both arm64 and x86_64 slices, since an Apple Silicon–only build
won't launch on an Intel Mac, and produces two things: `GuitarCHUD.zip` (archived
with `ditto`, so the bundle and signature survive the round trip) and
`GuitarCHUD.dmg`, which opens to the familiar drag-onto-Applications window.

The recipient needs macOS 13 or later and the Spotify **desktop** app — the web
player and the phone app can't be read over Apple Events. Any Spotify account
works, free or Premium; nothing is tied to the machine that built it.

Sending that zip to someone else has one snag: macOS quarantines anything
arriving by Messages, AirDrop or download, and this app is ad-hoc signed rather
than notarized, so Gatekeeper refuses it — usually with a misleading "app is
damaged" message. The recipient clears it with:

```bash
xattr -dr com.apple.quarantine /Applications/GuitarCHUD.app
```

Notarizing it (a paid Apple Developer account) is the only way to skip that step.

First launch, macOS asks for permission to read Spotify ("GuitarCHUD wants to
control Spotify"). Say yes — that Apple Event is the only way to see the current
track without an API key or login. If you miss the prompt, the window shows a
button that opens the right Privacy pane.

The build is ad-hoc signed with a fixed identifier so that permission survives
rebuilds.

## How it works

- **Track** — reads Spotify over Apple Events once a second. It never launches
  Spotify; if Spotify isn't running, it just waits.
- **Title cleanup** — Spotify titles carry noise that wrecks a chord search, so
  `"El Scorcho - Live at Reading Festival / 1996"` is searched as `"El Scorcho"`.
  Same for `(feat. …)`, `- Remastered`, `- Radio Edit`, and friends.
- **Dead links** — search results sometimes point at tabs that have since been
  pulled. Rather than surfacing a 404, the lookup walks down the ranking and
  loads the next best version.
- **Search** — Ultimate Guitar has no public API, so this reads the JSON that
  every UG page embeds in `div.js-store`. Results are ranked by chord sheets
  first, then artist/title match, then rating weighted by vote count — so a 4.85
  from 12,000 people beats a 5.00 from two.
- **Render** — UG returns text marked up with `[ch]…[/ch]`, which is drawn
  natively. (An iframe isn't an option: UG sends
  `content-security-policy: frame-ancestors 'self'`, so embedding is refused —
  and native drawing is what makes transpose and scroll-sync possible.)

## Using it

The toolbar scrolls sideways when the window is too narrow to show every button,
with the right edge fading to show there's more. Everything fits from about 460px
wide. The song title keeps a minimum width so there's always a strip of bar left
to drag the window by — letting it collapse is what made dragging stop working.

On every new song the version list opens automatically with the best match
already loaded underneath, so a wrong pick is one click to fix and you never
type a search.

| Control | Does |
|---|---|
| `≡` | Show/hide the version list |
| `♭ / ♯` | Transpose (the `0` button resets) |
| `A− / A+` | Text size (remembered) |
| `↵` | Wrap long lines instead of shrinking the text |
| `⇕` | Scroll in time with the song — scroll to shift it, toggle to re-sync |
| `📌` | Float above other windows |
| `🔍` | Search Ultimate Guitar by hand |
| hover a chord | Fingering diagram |
| click a chord | Pin the diagram, then click again (or `‹ ›`) to cycle voicings |

Keys: `+` / `−` transpose, `v` versions, `s` scroll-sync, `w` wrap, `⌘F` search.

Closing the window doesn't quit — the 🎸 in the menu bar keeps the current song
and its versions one click away. Quit from there or with `⌘Q`.

Two ways to handle a narrow window, toggled with `↵`. Either way `A−`/`A+` sets
the text size outright.

**Wrap off (default)** — long lines run off the right edge and the sheet scrolls
sideways, keeping the original line breaks exactly as written.

**Wrap on** — long lines fold instead. This can't be done with CSS wrapping: a
chord line and the lyric line under it would break at different columns and the
chords would drift off their syllables. Instead lines are grouped — chords with
their lyrics, and runs of tab strings together — and every line in a group breaks
at the *same* column, chosen where all of them have whitespace so no chord or
word is ever cut in half. Since the text size decides how many columns fit, the
sheet reflows when you resize the window *or* change the size.

Tab blocks need extra care. A chord line sitting above six tab strings belongs
to that block and has to break with it, or the strings shear apart. Tab strings
are also solid dashes with no spaces, so no column is ever blank — there the
break falls wherever it can without cutting a chord name on the line above in
half, and each wrapped chunk keeps its string label (`eb|`) so a continuation
isn't an anonymous run of dashes.

Playback-synced scrolling holds the spot you're playing at a fixed 38% down the
window. Mapping the song's progress straight onto the scrollbar instead — the
obvious approach — makes the current bar sink steadily toward the bottom, and
land exactly on the bottom edge by the last chord. The target is re-measured
every frame, so resizing the window or changing text size retargets the scroll
on its own rather than drifting out of sync.

Scrolling by hand doesn't fight the sync or get undone: whatever you scroll
becomes a standing offset, and the sheet carries on from there at the same rate.
That's usually what you want, since a manual nudge is normally correcting the
drift of linear timing. Toggle `⇕` off and on to drop the offset and snap back.
User scrolling is detected by noticing the scrollbar isn't where the animation
last put it, so wheel, trackpad, scrollbar and keyboard all count.

Chord diagrams come from UG's own fingering data, so they're real voicings
rather than generated guesses — often several per chord. When you transpose,
every fretted string shifts with it, which is exactly how an open shape becomes
the right barre chord (A `x02220` up two frets is `x24442`, B major). Voicings
that end up unplayable after a shift — wider than five frets or past the end of
the neck — are dropped rather than drawn half-finished.

Transposing keeps chords lined up over their lyrics by borrowing or padding the
spaces that follow each chord, so the monospace grid doesn't drift.

## The icon

`Resources/GuitarCHUD.icns` is drawn in code, not painted by hand — a chord
diagram in the same amber the app uses for chord names. Regenerate it with
`Icon/make-icon.sh` after editing `Icon/make-icon.swift`; it renders all ten
sizes macOS wants and runs them through `iconutil`.

If a rebuild still shows the old icon, macOS is caching it: `touch` the bundle
and `killall Dock`.

## Layout

```
Icon/make-icon.swift           draws the app icon at every size
Sources/Spotify.swift          reads the current track over Apple Events
Sources/UltimateGuitar.swift   title cleanup, search, ranking, tab parsing
Sources/main.swift             window, menu bar item, web-view bridge
Resources/ui.html              the whole interface
```

## If it breaks

UG is being scraped, not called through an API, so a redesign on their end can
break parsing. The failure is loud and contained: the window says "Couldn't load
chords" and the fix is almost always in `UGClient.store(from:)` (the `js-store`
extraction) or the field names in `fetchTab`.

## Notes

Not affiliated with, endorsed by, or connected to Ultimate Guitar or Spotify.

Ultimate Guitar has no public API, so chords are read from the JSON each page
embeds. Worth knowing before you run it: UG's `robots.txt` disallows
`/search.php` for automated clients, and the chord sheets themselves are
user-submitted transcriptions of copyrighted compositions that UG licenses from
publishers. This is a personal-use tool that reads pages you could open in a
browser — it is not a way to redistribute that content, and it caches nothing
beyond the current session. Be considerate: it fetches once per song change and
never retries on a loop.

Spotify is read locally over Apple Events, the same way any AppleScript can ask
the app what's playing. No Spotify account, API key or login is involved, and
nothing is sent anywhere.
