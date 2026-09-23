# Senior iOS Interview Guide — progress

Working file. Updated as the guide is written, not at the end.

**Source of truth:** the AlarmDM repository at the commit named below. Every
code excerpt in the guide is copied from a real file, not invented. If an
excerpt and the repository disagree, the repository is right and the guide is
stale.

- Base commit: `0e5639d` (branch `bugfix/3.1`)
- Guide: `docs/interview-guide/guide.md`
- PDF: `docs/interview-guide/Senior_iOS_Interview_Guide.pdf`
- Build: `bash docs/interview-guide/build.sh` (pandoc + xelatex)
- Swift highlighting: `swift.xml`, a syntax definition written for this
  document because the installed pandoc (2.9.2.1) has no Swift support
- LaTeX layout: `header.tex`

## Status

| # | Chapter | State |
|---|---------|-------|
| — | Repository analysis | done |
| — | Structure + this file | done |
| 1 | The two-minute description | done |
| 2 | One engine, many faces | done |
| 3 | Identity: ids from a feed that has none | done |
| 4 | SwiftData: two stores, and what CloudKit forbids | done |
| 5 | Conflict resolution without a server | done |
| 6 | Where a listen is written down (the CarPlay bug) | done |
| 7 | AVPlayer: five bugs and their shapes | done |
| 8 | Stream metadata, and giving it a lifetime | done |
| 9 | Domain rules as values | done |
| 10 | One codebase, four faces | done |
| 11 | Localization and a forced default | done |
| 12 | Analytics that measure nobody | done |
| 13 | Testing what has no simulator | done |
| 14 | Reading a code review like a senior | done |
| 15 | Honest weaknesses | done |
| 16 | Question bank with model answers | done |
| 17 | System design drill | done |
| 18 | Behavioural stories (STAR) | done |
| A | Appendix: file map, glossary, commands | done |

## Done

Everything in the table above is written, reviewed and in the PDF: 18 chapters
and 3 appendices, 66 A4 pages.

**Verification that was run, and should be re-run after any edit:**

- Every Swift and XML excerpt was checked line by line against the source
  tree. 439 of 452 substantive lines matched the repository verbatim. The 13
  that did not are all deliberate: code that no longer exists and is labelled
  as historical (`var id = UUID()`), elisions written as `...`, and the
  proposed fix in chapter 15 item 3, which is code that *should* exist and
  does not. Five transcription slips were found this way and corrected.
- Counts were checked against the tree rather than remembered: 47 app files,
  53 Swift files in all, ~10 900 lines, ~1 600 of tests, 147 catalog keys,
  `#if targetEnvironment(macCatalyst)` in 6 files, 23 tests in
  `ListeningRulesTests`.
- The PDF was rendered to images and read page by page for layout.

**Things deliberately left out**, so nobody wastes time looking for them: the
three PR review documents are not in the repository (they were pasted into a
chat), so chapter 14 is built from the commit messages that answered them,
which are in `git log` and are quoted exactly.

**If the code changes, these chapters go stale first:** 5 and 6 (they quote
`PodcastRepository` and `ListeningRecorder` heavily), 9 (the listening rules
move whenever the resume behaviour is tuned), and 15, which is a list of
things that are supposed to stop being true.

## Notes for whoever resumes this

- The repository analysis does not need repeating. The files that carry the
  guide's material are listed in the appendix file map, with what each one is
  good for.
- Chapters are independent. Write them in any order; each ends with an
  "In an interview" box that is the part worth rehearsing.
- Build the PDF with `bash docs/interview-guide/build.sh` (needs `pandoc` and
  `xelatex`, both present on this machine).
- Accuracy beats length. A claim about AVFoundation, SwiftData or CloudKit
  that cannot be traced to the code or to Apple's documentation should be cut
  rather than hedged.
