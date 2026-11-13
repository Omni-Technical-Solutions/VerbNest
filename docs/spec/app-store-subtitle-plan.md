# App Store: the subtitle mentions price (again)

Status 2026-11-13: reviewed; a guard test added; the fix itself is in App Store Connect and is the owner's. Nothing in the app changes.

## What App Review said

The subtitle to be displayed on the App Store includes a reference to the price of the app or the service it provides. Free or discounted wording counts as price. Remove it from the metadata; price changes belong in Pricing and Availability, or the description.

This is guideline 2.3.7 (and 2.3.10). The first Mac review of 0.64.3 rejected a subtitle for the same reason; `docs/release/app-store-post.md` has carried a warning since commit `3af3764`.

## Review

- The subtitle in the repository (`docs/release/app-store-post.md`) is **"Local-first API client"** (22 of 30 characters). It has no price wording, nor do the name, the promotional text or the keywords. The long description has none either ("no account", "no analytics or advertising" are about privacy, not price).
- So the text Apple objected to is not in the repository. The subtitle is entered by hand in App Store Connect, per app record and per localisation, and the text in Connect is what Apple reads. The likeliest causes, in order:
  1. a different **app record or platform** was not corrected: the iOS/iPadOS record and the macOS record are separate listings with their own subtitles, and only one was fixed after the 0.64.3 rejection;
  2. the subtitle of the **version under review** still has the old text (Connect keeps a subtitle per version; a new version copies the previous one, so an old line can come back);
  3. a second localisation (for example English (U.K.) or (Australia)) with its own subtitle.
- Nothing can be checked from here: the repository has no App Store Connect access. The owner needs to read the field.

## Steps

1. **Find it (owner).** In App Store Connect, for each app record (macOS, and iOS if it has its own) open the version under review > App Information > Localizable Information (and every localisation in the language list) and read the Subtitle. Whichever field has words such as free, open source, no cost, no subscription, discount, or a price: that is the one. Also read Name and Promotional Text on the same page.
2. **Replace it (owner).** Set the subtitle to exactly `Local-first API client` in every localisation of every record. If you prefer other wording, keep it to what the app is and does ("Local-first API client", "Test APIs on your device"), with no price, plan or licence words.
3. **Reply and resubmit (owner).** Reply in Resolution Center that the subtitle has been corrected (and name the record and localisation), then resubmit. A new build is not needed for a metadata fix: for a version still in "Rejected" or "Metadata Rejected" you can edit the metadata and click Resubmit to App Review.
4. **Keep it from coming back (agent, done).** `apps/verbnest_app/test/store_metadata_test.dart` fails if the name, subtitle, promotional text or keywords in `docs/release/app-store-post.md` contain price wording (free, open source, no cost, subscription, discount, a price, a currency sign and similar), or if the subtitle is longer than 30 characters. Whenever you change the copy there, the test says so. It cannot see App Store Connect, so after each new version also do step 1.
5. **Licence wording (note).** "Open source" in the description is allowed (it is not price), but keep it out of the subtitle, name and promotional text, which the guideline treats most strictly. The App Store licence agreement field and the privacy policy may state the Apache-2.0 licence.

## Risks

- If Apple names the same subtitle again after step 2, send the exact text you entered and a screenshot of the field in the reply; the message is automated and may have read a cached version.
- The earlier `network.server` message is a separate matter (`network-server-entitlement-plan.md`); both can be answered in one resubmission.
