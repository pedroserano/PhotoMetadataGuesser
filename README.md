<p align="center">
  <img src="Resources/Icon/AppIcon-1024.png" width="160" alt="Photo Date Guesser icon">
</p>

# Photo Date Guesser

A macOS app that finds the photos in your Apple Photos library that **don’t have a real date**, such as scanned prints, and estimates **when they were taken**. You review every guess with a thumbnail and a checkbox. When you click **Apply**, only the checked photos get the new date. It is set through Apple’s PhotoKit, so the photo isn’t replaced, its other details stay as they are, and Photos’ database stays consistent.

It’s built for very large libraries (250,000+ photos).

## How it works

The app has three steps: **Find Undated Photos**, **What You Know** (optional) and **Review & Apply**. The first time you open it, it asks for Photos access. It then asks you to point it at your Photos library file (so it can read the names you’ve tagged) and for Contacts access (for birthdays). You can skip either and do it later.

### 1. Find undated photos

The scan runs in two passes so it stays fast on huge libraries:

1. **Database pass.** It reads every photo’s library date from PhotoKit. A photo is flagged if it has no date, an impossible date, or a camera’s factory-default date (Jan 1 1970/1980/2000/2001 at midnight). It is also flagged if its date falls in a *scanning session* you entered, or if it’s in an album you marked “all undated.”
2. **File-header pass** (optional, on by default). This catches scans and imports. Photos gives a file with no capture date the date it was scanned or imported, so those photos *look* dated. The app reads only the first few hundred KB of each original file and checks for an EXIF `DateTimeOriginal`. It also recognizes scanner metadata (Epson FastFoto, VueScan, Photomyne, …). Files are never changed. Photos that have a GPS location are trusted by default, which skips most phone pictures.

Photos with a real date are skipped, and so are photos you already dated with this app (use **Scan Again ▸ Scan Again, Including Photos I Dated Here** to re-check them). Results are cached, so a re-scan doesn’t re-read files it already checked. Originals that are only in iCloud are counted as “couldn’t be checked” unless you allow downloads. These options are under **Options** on the scan screen.

As soon as the scan finishes, every photo gets a free on-device estimate. There’s no separate step to run.

### 2. What you know (optional)

Three tabs:

- **People.** Click **Import from Photos** to bring in everyone you’ve named in Photos, with the photos they’re tagged in. Names come only from Photos: to name someone, open the photo with **Show in Photos**, name the face there, and switch back. The app picks up the change on its own. Birthdays are read from the Contacts cards Photos linked people to (matched by contact ID, email, phone or name), or you can type them. If you turn it on in Settings, birthdays you type are also saved to the linked card. People who appear in the most undated photos are listed first.
- **Groups.** Select photos and make a group, or accept a suggestion (albums, and runs of sequentially numbered scans imported together). A group is either the **same event** (one date for all) or the **same era** (each photo gets its own date, nudged toward the group). Add notes like “Lake Tahoe trip, late 70s” or “xmas ’85”, a year range, a season, and who’s there.
- **Cameras.** Every camera that took undated photos, with how many. Enter the years you used one and its photos are dated within them. Scanners are left out.

### 3. Review & apply

Each card shows the thumbnail, the guess (“Summer 1976”), a confidence badge, the likely range and a checkbox. Change the year with the stepper or pick a season. **Why?** lists every clue behind the guess. Filter by **All / Checked / Unsure / Hidden**, sort or show one group, and bulk-check (e.g. “check all high-confidence”).

Double-click a photo for details. Every face Photos detected has a box with its name. **Who’s in this photo?** lists the people tagged there; fill in a missing birth year or how old they look. **Looks like the same event** shows look-alike photos that were dated together, with a button to make them one event.

**Apply** sets `PHAssetChangeRequest.creationDate` for the checked photos, in batches of 100. This is the same change as *Image ▸ Adjust Date and Time* in Photos:

- The original file is **not** rewritten or replaced.
- Location, people, albums, keywords, captions, edits and favorites are untouched.
- Photos makes the change itself, so its database stays consistent and iCloud Photos syncs it normally.
- Each photo’s previous date is saved, and **History ▸ Undo** puts it back.

### How dates are estimated

Every clue becomes evidence: a year range, how strong the clue is, and sometimes a season or exact month.

| Clue | Examples |
|---|---|
| Filenames | `IMG_20190704_…`, `1985-07-04`, `July 1979`, `xmas 85`, `late 70s`, `circa 1975`, `Santa visit`, `FB_IMG_<timestamp>` (camera counters like `IMG_1987` are ignored) |
| Album names | “Grandma 1965”, “Summer ’78”, “1960s” |
| When it was scanned | A scan or import can’t be older than the file: the library date is a firm upper limit |
| File format & camera | HEIC means 2017 or later, Live Photo 2015 or later, RAW 2000 or later, iPhone model release years, early-digital resolutions, and the years you entered for a camera |
| Color & tone | Sepia, black & white, the magenta shift of faded 1960s–80s prints |
| Border & paper | White print borders, instant-film frames, square 126/Instamatic prints |
| Scene (on-device Vision) | Santa, Christmas trees and decorations (December), snow and winter sports, pumpkins and costumes (October), Easter eggs and blossoms, beaches and pools |
| People | Someone can’t be in a photo from before they were born; their age in it (what you enter) dates it. Photos’ own rough age group for each face (baby, young child, adult) is used too |
| Look-alike photos | Undated photos that look alike (same scene, clothes or people) are dated together, so a printed date on one photo of a roll helps the others |
| Your groups and settings | Notes, year ranges, seasons, and “no photos before” (Settings ▸ Dates) |
| Your dated photos | An undated photo that’s almost identical to a photo with a real date (a scanned print of a dated original) gets that date. A close match counts if the same person is in both. Dates you apply with this app count too, a little less |
| Apple Intelligence (macOS 27+, optional) | Season and occasion (Christmas, Halloween, Easter, a beach day) from Apple’s on-device model. A gentle hint only; it’s never asked for the year |

The clues are combined statistically, like weighing testimony. Each clue is a mixture: either it’s right (and narrows the year) or it’s noise. Combining them gives a probability for every year since 1830. Strong, specific clues (a printed date stamp, `1985-07-04` in a filename) outweigh vague ones (“black & white”). Clues that agree reinforce each other. The result is:

- the **most likely year**, an **~80% range** (e.g. 1972–1978), and a **confidence** (the chance the year is within ±2 years);
- a **season**, written as the month you asked for: **January** (winter), **March** (spring), **June** (summer) or **September** (fall). If the season is unknown, June is used. When a strong clue gives an exact month or date (a full date in a filename, Christmas), that’s used instead. You can turn this off in Settings.

Some of these were calibrated on a real library of about 190,000 photos:

- **Look-alikes.** Photos are compared with Vision image fingerprints. Below a distance of 0.5, only 1 in 10,000 pairs from different years matched, against 17% of same-day pairs. Up to 0.7 is still a strong sign.
- **Face age groups.** Apple doesn’t document Photos’ age groups (`ZAGETYPE`). Following children from infancy across ~87,000 faces: 1 is a baby, 2 a young child (about 1–5), 3 older children through adults, and 5 older adults; 4 is almost never used. This matches the order of the one public mapping (mac4n6.com, 2020). Groups 3 and 5 overlap a lot, so they count only a little.

#### Built in, and private

Everything runs on your Mac with Apple’s own frameworks: Vision for scenes, faces and image fingerprints, and Apple Intelligence’s on-device model for seasons. Nothing is sent anywhere, and the app doesn’t need the internet.

- **Dated look-alikes.** Undated photos are compared with dated photos of the same people (up to 300 per face group, picked from Photos), and with photos you dated here. Only photos with a trustworthy date are used: one with a location, or with a capture date the scan checked. Below a distance of 0.35, none of 15.7 million pairs taken two or more years apart matched, so that’s the cutoff for “the same picture”. A looser match (below 0.5) counts only when the same person is in both.
- **Apple Intelligence.** Tested on dated phone photos, it was poor at years (it guessed 2015–2019 for nearly everything), so it’s only asked for the season and the occasion. It named a season for about a quarter of photos and was right on about half of those. It takes a few seconds per photo; turn it off in **Settings ▸ Apple Intelligence**.

## Building

Requirements: macOS 14 Sonoma or later. You also need Apple’s free developer tools; the build script offers to install them if they’re missing.

### One line

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/pedroserano/PhotoMetadataGuesser/main/install.sh | bash
```

It downloads the latest source, builds the app, puts it in your Applications folder and opens it. Run the same command again to update.

If you already have the project folder, you can instead double-click **`Build Photo Date Guesser.command`**. It does the same thing from the files on your Mac.

### Other ways

- `./scripts/build-app.sh` builds and signs `build/Photo Date Guesser.app` without installing it. To sign with your Developer ID, set `SIGN_IDENTITY="Developer ID Application: …"`.
- To work in Xcode, generate a project with [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen && xcodegen generate && open PhotoMetadataGuesser.xcodeproj`.
- `swift test` runs the estimation-logic tests (needs full Xcode).

Every push is built and tested on GitHub Actions (macOS). The built app is attached to each run as an artifact.

> **Tip:** Back up your Photos library (Time Machine is fine) before applying dates to thousands of photos. Undo is available, but a backup is the safest net.

## Project layout

```
Sources/DateGuessCore/        Pure-Swift logic (unit-tested)
  TextClues.swift             filename / album / hint parsing
  FormatClues.swift           file format & camera clues
  VisualClues.swift           color, sepia/B&W, borders, aspect; scene → season
  PeopleAndUndated.swift      ages from birthdays and face age groups, undated detection, group suggestions
  EvidenceFusion.swift        combining clues; group fusion
  EventLinks.swift            look-alike photos from the same event; matching to dated photos
Sources/PhotoMetadataGuesser/ The macOS app
  Photos/                     PhotoKit: scanning, header reads, writing dates;
                              reading names and faces from the Photos library; Show in Photos
  Support/                    storage, Keychain, Contacts birthdays
  Analysis/                   Vision + image stats, Apple Intelligence, estimation pipeline
  Views/                      SwiftUI screens
Resources/                    Info.plist, entitlements, app icon
```

## Privacy

- Everything runs on your Mac. Nothing is sent anywhere, and the app has no internet access.
- The Photos library file is only read (names and faces), never changed. Names are only ever added in Photos itself.
- Contacts are only read, unless you turn on saving birthdays to Contacts in Settings.
- App data (scan results, groups, people, estimates, undo history) lives in the app’s container under Application Support.

## Limitations

- Only photos in your own library are considered. Shared-album items can’t be edited through PhotoKit.
- If you previously fixed a scan’s date in Photos (rather than in this app), its file still has no capture date, so the scan may flag it again. Right-click ▸ *Keep Current Date* hides it for good.
- Each rebuild of an ad-hoc-signed app may make macOS ask for Photos permission again.
- Reading names from Photos relies on the layout of Photos’ private database, which Apple can change. If an update breaks it, import shows an error and everything else keeps working.
- If your Photos library is on an external drive, keep it connected: otherwise macOS shows the app an empty library.
- Face boxes can be slightly off for photos you cropped in Photos.
- Estimates are estimates. The confidence badge and **Why?** panel are there to help you decide what to trust.
