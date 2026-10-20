# F-Droid MR Description — App Inclusion Template (verbatim, answered)

Status: DRAFT — ready to paste into the resubmission MR (~mid-Jan 2027, once the
3-month maintenance policy is satisfied; repo created 2026-10-15).

Reference: the official template lives at
https://gitlab.com/fdroid/fdroiddata/-/blob/master/.gitlab/merge_request_templates/App%20inclusion.md

Prior attempt: fdroid/fdroiddata!53147 (closed 2026-10-19 for template
non-adherence + 3-month maintenance policy).

HOW TO USE: paste the section below into the new MR description WITHOUT
renaming headers or rephrasing checklist items. Swap in the v1.5.x commit
hash, paste the Reproducible Builds reason, attach screenshots, then create
the MR with title exactly: New app: JotLock

---

## Abstract

### Please introduce the functions and usage of your app in summary, and also attach some screenshots.

JotLock is a lock-screen-first notes app: a persistent Quick note notification puts a Write note button on the lock screen, an inline Jot field lives in the notification shade, and reminders (once/daily/weekly/custom) always play your sound but never clutter the lock screen. Also includes checklists with `[ ]` / `[x]` syntax and progress counts, priority colors, pinning, copy and share, search as you type, an optional App PIN, and JSON/text export with JSON import. Free, open source (MIT), ad-free, and no INTERNET permission — notes physically have nowhere to go but the device.

Screenshots (upstream fastlane): https://github.com/Ryfire/jotlock/tree/main/fastlane/metadata/android/en-US/images/phoneScreenshots

### Please elaborate why you wrote this app. Please highlight the unique functions it provides over other similar apps in F-Droid.

I wanted to capture a thought without unlocking the phone first, and I wanted the note-taking app to double as a lock-button when I'm done. Every other notes app I tried requires unlocking first. JotLock's entry point is the lock screen itself — live lock-screen quick note, inline shade reply, and an opt-in auto-lock after saving — and it requests no INTERNET permission at all.

## Checklist

### Policy

* [x] The app complies with the [inclusion criteria](https://f-droid.org/docs/Inclusion_Policy).
* [x] The original app author has been notified (and does not oppose the inclusion). If you are not the author, please paste the link of the reply from the author.
  * I am the author.
* [x] The upstream app source code repo contains the app metadata in a [Fastlane](https://gitlab.com/snippets/1895688) or [Triple-T](https://gitlab.com/snippets/1901490) folder structure. The summary and description must be included and images, icon, and changelog should also be provided for better user experience. The `en-US` locale must be included.
  * `fastlane/metadata/android/en-US/` provides title, short/full description, changelogs, icon, and 8 phone screenshots.

### Docs

* [x] Please read [the guide](https://gitlab.com/fdroid/fdroiddata/-/blob/master/CONTRIBUTING.md) first if this is your first contribution.
* [x] Please make sure your metadata follows the best practice in [our templates](https://gitlab.com/fdroid/fdroiddata/tree/master/templates).
  * Recipe uses the reviewer-revised srclib pattern from !53147: `srclibs: flutter@3.47.6`.
* [x] Please read the [Build Metadata Reference](https://f-droid.org/docs/Build_Metadata_Reference/) and make sure your metadata is valid.
* [x] Please read the [Quick Start Guide](https://f-droid.org/en/docs/Submitting_to_F-Droid_Quick_Start_Guide/).

### Merge Request Setup

* [x] The title of this merge request should follow "New app: app name" format.
  * Title: New app: JotLock
* [x] Please make sure your fdroiddata fork is public and your branch is not protected. See <https://docs.gitlab.com/user/project/repository/branches/protected/>.
  * Fork ryfireapps/fdroiddata is public; single clean branch, not protected.
* [x] Please read [our Git guide](https://gitlab.com/fdroid/wiki/-/wikis/Tips-for-fdroiddata-contributors/Git-Usage) if you don't know how to rebase your branch. Don't rebase your branch if there is no conflict.
  * No conflict, no rebase.
* [x] All related [fdroiddata](https://gitlab.com/fdroid/fdroiddata/issues) and [RFP issues](https://gitlab.com/fdroid/rfp/issues) have been referenced in this merge request
  * RFP: https://gitlab.com/fdroid/rfp/-/issues/4600 (closed; now tracked via this MR)
  * Prior attempt: fdroid/fdroiddata!53147 (closed — 3-month maintenance policy; resubmitting after the repo passes the 3-month mark)
* [x] Please only submit one app in one MR.

### Metadata

* [x] Metadata must be put in `metadata/<applicationId>.yml`.
  * `metadata/com.ryfire.jotlock.yml`
* [x] Metadata must be a valid YAML file.
* [x] Metadata must use LF as line ending.
* [x] Don't add summary/description/changelog/images or anything that should be provided in upstream repo. Please check the Changes tab to make sure there is no other unrelated files added in the MR.
  * MR adds only the single metadata yml.
* [x] Releases are tagged and auto update is enabled unless there is a special reason.
  * `AutoUpdateMode: Version v%v`, `UpdateCheckMode: Tags v[\d.]+`
* [x] There is an issue tracker and contact info of the author so that we can report bugs and contact the author.
  * https://github.com/Ryfire/jotlock/issues
* [x] An AuthorName must be added. It doesn't need to be the real name.
  * `AuthorName: Ryfire`
* [x] External repos are added as git submodules instead of srclibs. You can update git submodules without opening an MR in this repo and the submodule is covered by our scanner.
  * N/A — no external repos; the only srclib is the standard Flutter toolchain (`flutter@3.47.6`).
* [ ] Enable [Reproducible Builds](https://f-droid.org/docs/Reproducible_Builds). We'll use your signature for improved security/reliability, also allowing users to switch between different channels. Do note that if you don't enable reproducible build then the apk will be signed with our key so you can't enable it later. If you can't enable this, please add the reasons here.
  * RESOLVED 2026-10-19 — leave `[ ]` with reason. Tested locally: two clean
    `flutter build apk --release` runs of the same commit, same Flutter SDK,
    same release keystore produce different SHA256 hashes (6706B1EB…F2CCE936
    vs 5726D254…2F85F39) at identical byte size; the only in-APK content
    difference is `assets/flutter_assets/NOTICES.Z` (zip metadata/timestamps
    otherwise) — enumeration/compression-order nondeterminism. F-Droid's
    buildserver may normalize this, but reproducibility is unverified from
    here, so it cannot be claimed.
  * Paste-ready reason: "Not enabled: local double-builds of the same commit
    produce differing APKs (NOTICES.Z payload + zip metadata), so
    reproducibility is unverified from here. Accepting F-Droid signing; happy
    to help if a maintainer wants to attempt a reproducible verification build."
* [x] Setup abi split if the APK is large and the splitted ones can be much smaller.
  * RESOLVED 2026-10-19 — not applicable: the F-Droid main repo ships exactly
    one universal APK per version. fdroidserver's Build Metadata Reference has
    no split/per-ABI support, and fdroiddata's Flutter recipes (e.g.
    chat.fluffy.fluffychat — every build uses `flutter build apk --release`
    with a single `output:` path) as well as the reviewer-revised JotLock
    recipe from !53147 all build universal APKs. Splits would not reduce what
    F-Droid users download (~50.6 MB universal). Per-ABI splits may still be
    offered on GitHub Releases for Obtainium users — separate channel
    decision, not part of this MR.
* [x] Only the latest versions should be kept in the metadata before it's merged. If you update the metadata, please replace the old versions with the new ones.
* [x] Don't add any disabled versions in the metadata.
* [x] The `commit` field should be the full hash. Please don't use tag or branch in commit.
  * TODO at resubmission: update `commit:` to the v1.5.x full hash.

### Pipeline

* [ ] All pipelines should pass.
* [ ] All warnings and errors in the Reports tab should be fixed or explained.
* [x] F-Droid CI runners are under GitLab's FOSS program, so there's no need for you to pay for any CI time. If Gitlab starts asking for phone numbers or credit cards don't submit anything, just leave a note in the MR so we know we need to trigger the CI.
  * Note: fork CI runners may be unavailable on this account — please trigger the CI if pipelines don't start.

---

## Resubmission checklist (before opening the new MR)

1. ~2027-01-15: repo will be 3 months old — verify public commit/release
   history shows continuous maintenance (regular commits, tagged releases,
   issue activity).
2. Tag + push v1.5.x; update `metadata/com.ryfire.jotlock.yml`:
   `versionName`, `versionCode`, `commit` (full hash), `CurrentVersion`,
   `CurrentVersionCode`. Add fastlane changelog `9.txt` (or matching
   versionCode).
3. Box status at resubmit: Reproducible Builds — leave `[ ]`, paste the
   ready reason (Metadata section); ABI split — done, `[x]` N/A (universal
   APK is the F-Droid norm, verified 2026-10-19); Pipeline boxes — fix/explain
   once CI runs.
4. Create MR from `ryfireapps/fdroiddata:jotlock-init` (fresh branch off
   current fdroiddata master) → `fdroid/fdroiddata:master`, paste the
   answered template above, attach screenshots.
5. If pipelines don't run, leave the note above and ask a maintainer to
   trigger CI.
