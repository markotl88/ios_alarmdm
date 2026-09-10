# backend

The app's episode list comes from two Firebase Cloud Functions in the Google
Cloud project `dasko-i-mladja` (region `us-central1`), which derive their data
from the RSS feed at `https://podcast.daskoimladja.com/feed.xml`. The function
source lives outside this repo.

## showClassifier.js

Maps an episode title to a show key. The keys are exactly the `Show` enum's
rawValues in the iOS app, so the result can be stored as `showType` and used
by the app without translation.

Drop it into the functions project and replace whatever currently decides
`showType`:

```js
const { classifyShow } = require('./showClassifier');
const showType = classifyShow(item.title);   // string, or null when unknown
```

### Why it looks the way it does

Episode titles are hand-entered and inconsistent. Measured against the whole
feed (5252 episodes, September 2026) the rules classify **99.81%**, leaving 10
titles unclassified — genuinely unclassifiable ones like `VANREDNO UKLJUČENJE`,
`Sound oi`, and bare dates from 2017.

It returns `null` instead of guessing. The old behaviour defaulted unknown
titles to the daily show, so every unrecognised episode showed up as Alarm with
Alarm's artwork. The app now maps `null` to a `.ostalo` bucket that is never
listed in the Shows tab.

Rules cover, deliberately: abbreviations (`LJP`, `LJIP`, `NIO`, `PUP`, `TLJP`,
`VSR`, `PPP`, `MSDSS`), missing spaces (`LJP93-11decembar2019`), typos
(`Provizprni`, `Povizorni`, `Srerda`, `Četvrtvrtak`, `Ve;ernja`, `Sportski
Pozdra`, `emigrcija`), and mixed diacritics. Misspelled weekdays are caught by
edit distance, and a bare date is treated as the daily show.

The daily show is matched **last** on purpose: weekday names are the broadest
pattern and would otherwise swallow other shows whose titles mention a day.

### Shows found in the feed that the app did not know about

| show | episodes | last episode |
|---|---|---|
| Nepopularno mišljenje | 10 | 2026-09-09 — active |
| JBT | 15 | 2026-05-15 |
| Priče u magli (radio-drama) | 4 | 2025-11-29 |
| Čitanjac | 3 | 2022-05-12 |
| FALIŠ | 6 | 2024-09-06 |

`mozemoSamoDaSeSlikamo` has no episodes in the feed at all and was removed from
the app. `punaUstaPoezije` has exactly one, from 2020, under the abbreviation
`PUP 007`.
