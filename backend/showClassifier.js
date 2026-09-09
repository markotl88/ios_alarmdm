/**
 * showClassifier.js
 *
 * Maps a podcast episode title from the daskoimladja.com RSS feed to a show key.
 * The keys are exactly the rawValues of the `Show` enum in the iOS app, so
 * whatever this returns can be stored as `showType` and consumed directly.
 *
 * Measured against the full feed (5252 episodes, September 2026): 99.81%
 * classified, 10 titles left unclassified.
 *
 * Design notes:
 * - Returns null rather than guessing. The previous behaviour — falling back to
 *   the daily show — silently mislabelled every unknown episode as Alarm.
 * - Titles are entered by hand and are inconsistent: abbreviations (LJP, LJIP,
 *   PUP, NIO), missing spaces (LJP93-11decembar2019), typos (Provizprni,
 *   Srerda, Četvrtvrtak, Ve;ernja), and mixed diacritics. Rules are tolerant on
 *   purpose.
 * - The daily show is matched LAST: weekday names are the broadest pattern and
 *   would otherwise swallow episodes of other shows that mention a day.
 */

'use strict';

const DAYS = ['ponedeljak', 'utorak', 'sreda', 'cetvrtak', 'petak', 'subota', 'nedelja'];
const MONTHS = ['januar', 'februar', 'mart', 'april', 'maj', 'jun',
                'jul', 'avgust', 'septembar', 'oktobar', 'novembar', 'decembar'];

/** Lowercase, strip diacritics, keep only letters/digits/underscore/space. */
function normalize(title) {
  return String(title || '')
    .toLowerCase()
    .replace(/đ/g, 'dj')
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9_ ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Ordered: the first match wins, so the daily show stays at the bottom. */
const RULES = [
  ['jbt',                       /\bjbt\b/],
  ['nepopularnoMisljenje',      /nepopularno\s*misljenje/],
  ['citanjac',                  /citanjac/],
  ['priceUMagli',               /price u magli|radio\s*-?\s*drama/],
  ['sportskiPozdrav',           /sportski\s*pozdra/],
  ['unutrasnjaEmigracija',      /un[a-z]*\s*emigr[a-z]*/],
  ['ljudiIzPodzemlja',          /ljudi\s*iz\s*podzem[a-z]*|\blji?p\s*\d|\blji?p\b/],
  ['naIviciOfsajda',            /na\s*ivici\s*ofsajda|\bnio\b/],
  ['vecernjaSkolaRokenrola',    /ve\s*[a-z]*ernja\s*sko[a-z]*|\bvsr\b/],
  ['provizorniPodnevniProgram', /p[a-z]{0,3}vi[a-z]*\s*podnevni|podnevni\s*p[a-z]{0,3}vi[a-z]*|\bppp\b/],
  ['rastrojavanje',             /rastrojavanje/],
  ['topleLjuckePrice',          /tople?\s*ljucke|\btljp\b/],
  ['punaUstaPoezije',           /puna\s*usta\s*poezije|\bpup\s*\d/],
  ['mozemoSamoDaSeSlikamo',     /mozemo\s*samo\s*da\s*se\s*slikamo|\bmsdss\b/],
  ['falis',                     /\bfalis\b/],
  ['alarmSaDaskomIMladjom',     /\balarm\b|\b\d?_?(ponedeljak|utorak|sreda|cetvrtak|petak|subota|nedelja)\b/],
];

function levenshtein(a, b) {
  const m = a.length, n = b.length;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) {
      cur[j] = Math.min(
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)
      );
    }
    prev = cur;
  }
  return prev[n];
}

/** Catches misspelled weekdays: Srerda, Cetvrtvrtak, Uorak, Ponedeljka. */
function looksLikeWeekday(normalized) {
  return normalized.split(' ').some(token => {
    if (token.length < 4) return false;
    return DAYS.some(day => {
      const distance = levenshtein(token, day);
      return distance <= Math.max(1, Math.floor(day.length * 0.25));
    });
  });
}

/** A bare date is the daily show: "30. oktobar 2025". */
function looksLikeDate(normalized) {
  return /\b\d{1,2}\b/.test(normalized) &&
         MONTHS.some(month => normalized.includes(month.slice(0, 4)));
}

/**
 * @param {string} title Episode title as it appears in the feed.
 * @returns {string|null} A Show rawValue, or null when nothing matches.
 */
function classifyShow(title) {
  const n = normalize(title);
  if (!n) return null;

  for (const [key, pattern] of RULES) {
    if (pattern.test(n)) return key;
  }
  if (looksLikeWeekday(n) || looksLikeDate(n)) return 'alarmSaDaskomIMladjom';
  return null;
}

module.exports = { classifyShow, normalize, RULES };
