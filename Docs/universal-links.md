# Universal Links — the half that lives in the web repo

The app side is done: the entitlement is in `Spliit/Spliit.entitlements`, and
`IncomingLink` accepts `https://spliit.app/groups/<id>`. Nothing happens until
**spliit.app vouches for the app**, and that file lives in [`../spliit`](https://github.com/spliit-app/spliit),
not here.

Until it is deployed, a group link opens Safari exactly as it does today. Nothing
regresses; the feature is simply inert.

## What to add to the web repo

Serve this at **`https://spliit.app/.well-known/apple-app-site-association`** — no
extension, `Content-Type: application/json`, no redirects, plain HTTP 200.

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["VKY5EKKU47.app.spliit.spliitmobile"],
        "components": [
          {
            "/": "/groups/*",
            "comment": "Opens a group in the iOS app"
          }
        ]
      }
    ]
  }
}
```

In a Next.js app the simplest home is `public/.well-known/apple-app-site-association`.
It must be served as JSON — check the headers, because a static host that guesses the
type from the (absent) extension will hand back `application/octet-stream` and iOS will
ignore the file without saying why.

`VKY5EKKU47` is the Team ID in `project.yml`; `app.spliit.spliitmobile` is the bundle
ID this app inherited from the React Native one.

## The other prerequisite

Associated Domains has to be enabled for the App ID in the developer portal.
`make build-device` passes `-allowProvisioningUpdates` and will add it, but a signed
build fails until it exists. Simulator builds and CI are unaffected — they build with
`CODE_SIGNING_ALLOWED=NO`.

## Checking it works

```sh
curl -sI https://spliit.app/.well-known/apple-app-site-association   # 200, application/json
```

Then, on a device with the app installed, open a group link from Messages or Notes —
**not** by typing it into Safari's address bar, which iOS deliberately treats as a
request for the website rather than the app.
