# Moving a devDependency into dependencies

`inno-ship` loads this when the `app-build` job reports `devDependency
imported at runtime` for a package. The fix moves that package's entry from
`devDependencies` to `dependencies` as it stands.

From the repo root, with the package's name in place of `<package>` (the
error's own `Move it:` line carries this same command with the package
already named):

```bash
(cd app && p='<package>' && spec="$(npm pkg get "devDependencies[$p]" | tr -d '"')" && test "$spec" != "{}" && npm pkg set "dependencies[$p]=$spec" && npm pkg delete "devDependencies[$p]" && npm install --package-lock-only)
```

The parentheses run it in a subshell, so the shell stays at the repo root for the next step. The specifier moves exactly as written: an exact pin stays exact, a range
keeps its range, and a `file:` or git specifier is untouched. The bracket
form reads a name with a dot or a scope correctly, and `test` stops the line
when the package is not under `devDependencies`. `--package-lock-only`
rewrites only the lockfile and keeps the version it already holds, so
`app/package-lock.json` changes in two ways and keeps every version: the
root entry (`packages[""]`) lists the package under `dependencies` instead
of `devDependencies`, and the package's own entry drops `"dev": true`, as
does the entry of anything only it pulls in. Check that with
`git diff app/package.json app/package-lock.json`, then run `inno-ship`
§0's install block (`npm ci --ignore-scripts --omit=dev`, what `app-build`
runs).

One command looks like this move and is not:
`npm install --save-prod <package>@<specifier>` re-resolves a registry
package to the newest release its range allows, and can save the specifier
with a `^`, so an exact pin `1.2.3` becomes `^1.2.3`. Either way a version
the author never chose ships in the next deploy.
