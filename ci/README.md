# Committed App Store Connect credentials

`AuthKey_62PB5AGS4R.p8` and `credentials.env` are checked in on purpose. This is
not the normal way to do it and the tradeoff was made knowingly, so it is written
down here rather than left to be discovered.

## Why

Setting a repository secret is the one step in this pipeline that cannot be
automated from outside the account: it needs either the GitHub web UI, the `gh`
CLI, or a token with `secrets:write`. Everything else — archiving, signing,
uploading to TestFlight — runs unattended. The owner asked for a pipeline
requiring no interaction at all and accepted this cost to get it.

## What it means

The key is in the git history permanently. Removing the file in a later commit
does not remove it from the history; that needs a rewrite (`git filter-repo`) and
a force push. Anyone who can read this repository can read the key, and if the
repository is ever made public the key is public with it.

The key carries the **App Manager** role. It can upload builds and edit app
metadata for this account. It cannot reach banking, agreements, or tax
information — those need Account Holder or Finance.

## Moving to secrets

The workflows prefer repository secrets and fall back to these files, so
switching over needs no code change. Set all four:

```sh
gh secret set APP_STORE_CONNECT_KEY_P8    --repo chrisatmellis/meow < ci/AuthKey_62PB5AGS4R.p8
gh secret set APP_STORE_CONNECT_KEY_ID    --repo chrisatmellis/meow --body "62PB5AGS4R"
gh secret set APP_STORE_CONNECT_ISSUER_ID --repo chrisatmellis/meow --body "169cff24-cb13-4add-a356-e2a2915e2eeb"
gh secret set APPLE_TEAM_ID               --repo chrisatmellis/meow --body "KJ9NJ2M7C6"
```

Then `git rm -r ci/` and the pipeline carries on unchanged.

## Rotating

Worth doing whenever the convenience stops being worth it. App Store Connect →
Users and Access → Integrations → revoke `62PB5AGS4R`, generate a replacement,
and either drop the new `.p8` in here with its key id in `credentials.env`, or
move to secrets as above. Revoking is instant and breaks nothing that is not
mid-upload.
