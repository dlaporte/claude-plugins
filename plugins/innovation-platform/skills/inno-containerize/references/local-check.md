# Local sanity check before pushing

Read this from `inno-containerize` when Docker is available locally and you
want a Dockerfile checked before a push. Run it from the repo root.

The block below builds the image, then decides the non-root rule exactly the
way the CI gate does (`SKILL.md` item 2) and prints one `OK:` or `FAIL:` line. It
never runs the image to resolve the user: it reads `/etc/passwd` straight off
the image, maps NUL bytes before reading, and hands the name to `awk` through
the environment. Both `awk` compares append `""` to force a STRING compare,
exactly as the workflow does, because awk compares numerically when both sides
look numeric and a name like `1e3` would otherwise match a passwd name `1000`.
It has no comments and no `!` outside single quotes, so it pastes cleanly
into bash, zsh, or an interactive zsh, and it runs inside parentheses, so a
stop ends the block and never the shell it was pasted into. Everything after
the `EXPOSE` check is the `/healthz` smoke gate, and it waits the way CI does:
up to 18 tries 5 seconds apart, each with a 4 second timeout, stopping early
if the container exits (an app that crashes on boot reports that it exited,
even when it stops before its port can be read), and it tests for **exactly
200**, because `curl -f` would accept a 204 or a 301 that CI refuses. So an
app that is still booting is not a `FAIL`; a `FAIL` prints the container's
logs.

The block owns what it creates, because a developer's machine is shared with
other work in a way a CI runner is not. Each run builds its own image tag and
names its containers after it (`app-under-test-` with the time and the shell's
process id), keeps the IDs that `docker create` prints, and on the way out,
including after a Ctrl-C, removes only those containers and that tag: it never
removes a container by a name some earlier run or another tool may hold. The
smoke container's port 8080 is published on a free loopback port that Docker
picks, read back with `docker port`, so another service already answering on
8080 cannot pass the check for it. A failed `docker build`, or a smoke
container that cannot be created or started, stops the block with a `FAIL:`
line saying which, before anything reads or runs a stale image; fix that and
run the block again. A user probe that cannot be created is read as an image
with no readable `/etc/passwd`, as CI reads it.

```bash
(
run="app-under-test-$(date +%Y%m%d%H%M%S)-$$"; img="${run}:local"; built=""; probe=""; cid=""
trap '[ -n "$probe" ] && docker rm -f "$probe" >/dev/null 2>&1; [ -n "$cid" ] && docker rm -f "$cid" >/dev/null 2>&1; [ -n "$built" ] && docker rmi "$img" >/dev/null 2>&1' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
docker build -t "$img" . || { echo "FAIL: docker build failed, so nothing was checked"; exit 1; }
built=1
user="$(docker inspect --format='{{.Config.User}}' "$img" | tr '\000' '\001')"
u="${user%%:*}"; uid=""; why=""
case "$user" in 0|root|0:*|root:*|"") why="runs as root" ;; esac
if [ -z "$why" ]; then
  case "$u" in
    "") why="has an empty user part, which Docker runs as uid 0" ;;
    *[^0123456789]*)
      case "$u" in
        -*|*[^ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
          why="is neither a plain uid nor a portable user name" ;;
        *)
          pw=""; probe="$(docker create --name "$run-uidprobe" "$img" 2>/dev/null)"
          if [ -n "$probe" ]; then
            pw="$(docker cp "$probe":/etc/passwd - 2>/dev/null | tar -xO 2>/dev/null | tr '\000' '\001')"
            docker rm -f "$probe" >/dev/null 2>&1; probe=""
          fi
          if [ -z "$pw" ]; then
            why="cannot be resolved: the image has no readable /etc/passwd"
          else
            uid="$(printf '%s\n' "$pw" | U="$u" LC_ALL=C awk -F: '
              { line = $0; sub(/^[^!-~]+/, "", line); sub(/[^!-~]+$/, "", line)
                split(line, f, ":"); if ((f[1] "") == (ENVIRON["U"] "")) loose++
                if (($1 "") == (ENVIRON["U"] "")) { exact++; field = $3 } }
              END { if (loose == 0 && exact == 0) print "none"
                    else if (loose != 1 || exact != 1) print "ambiguous"
                    else if (field !~ /^[0-9]+$/) print "malformed"
                    else print field }')"
            case "$uid" in
              none) why="matches no /etc/passwd entry" ;;
              ambiguous) why="matches /etc/passwd ambiguously (on more than one line, or on a line with leading blanks, or with blanks inside the name field)" ;;
              malformed) why="matches an /etc/passwd line whose uid field is not a plain number" ;;
            esac
          fi ;;
      esac ;;
    *) uid="$u" ;;
  esac
fi
n="$(printf '%s' "$uid" | sed 's/^0*//')"
if [ -z "$why" ] && [ -z "$n" ]; then why="resolves to uid 0"; fi
if [ -z "$why" ] && { [ "${#n}" -gt 10 ] || [ "$n" -gt 2147483647 ]; }; then why="resolves to a uid above 2147483647"; fi
shown="$(printf '%s' "$user" | LC_ALL=C tr -c ' -~' '?')"
if [ -z "$why" ]; then echo "OK: User='$shown' runs as uid $n"; else echo "FAIL: User='$shown' $why"; fi
docker inspect --format='{{json .Config.ExposedPorts}}' "$img" | grep '8080/tcp' || true
cid="$(docker create -p 127.0.0.1::8080 --name "$run-run" "$img")" || { echo "FAIL: docker create failed for the smoke container"; exit 1; }
docker start "$cid" >/dev/null || { echo "FAIL: the smoke container did not start"; exit 1; }
addr="$(docker port "$cid" 8080/tcp | head -n 1)"
if [ -z "$addr" ]; then
  running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo false)"
  if [ "$running" = true ]; then echo "FAIL: the smoke container has no published port for 8080"
  else echo "FAIL: the container exited before /healthz answered 200, last status: none"; fi
  docker logs "$cid"; exit 1
fi
ok=""; last=""; exited=""
for i in $(seq 1 18); do
  last="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://$addr/healthz" || true)"
  if [ "$last" = 200 ]; then ok=1; break; fi
  running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo false)"
  if [ "$running" = true ]; then sleep 5; else exited=1; break; fi
done
if [ -n "$ok" ]; then echo "OK: /healthz 200"
elif [ -n "$exited" ]; then echo "FAIL: the container exited before /healthz answered 200, last status: ${last:-none}"; docker logs "$cid"
else echo "FAIL: /healthz did not answer 200 within 18 tries, last status: ${last:-none}"; docker logs "$cid"
fi
)
```
