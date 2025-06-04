<p align="center">
    <a href="https://wippy.ai" target="_blank">
        <picture>
            <source media="(prefers-color-scheme: dark)" srcset="https://github.com/wippyai/.github/blob/main/logo/wippy-text-dark.svg?raw=true">
            <img width="30%" align="center" src="https://github.com/wippyai/.github/blob/main/logo/wippy-text-light.svg?raw=true" alt="Wippy logo">
        </picture>
    </a>
</p>
<h1 align="center">{Package Name}</h1>
<div align="center">

[![Latest Release](https://img.shields.io/github/v/release/{organization}/{repo}?style=flat-square)][releases-page]
[![License](https://img.shields.io/github/license/{organization}/{repo}?style=flat-square)](LICENSE)
[![Documentation](https://img.shields.io/badge/Wippy-Documentation-brightgreen.svg?style=flat-square)][wippy-documentation]

</div>

{description}

---

## TODO

### Prepare the repository

- Replace all `{repo}` with the actual repository name.
- Replace all `{organization}` with the actual organization name (e.g., `wippyai`).
- Replace all `{namespace}` with the actual module namespace (e.g., `wippyai`).
- Replace all `{Package Name}` with the actual human-readable package name.
- Replace the `{description}` with the actual package description.
- Fill the `.github/CODEOWNERS` with the actual owners.
  - Configure access to the repository for the owners in https://github.com/{organization}/{repo}/settings/access
- Check that the `LICENSE` file is present and contains the correct license information.
- Customize the `CONTRIBUTING.md` file with the actual contribution guidelines or remove it if not needed.
- Fill the blocks below with the actual information or remove them if not needed.

### Register the module in the Wippy registry

The repository uses the [Github Action](https://github.com/wippyai/action-module-release)
to automatically register the module in the [Wippy registry][modules-registry] on every release.
To trigger the registration, you need to create a new tag in the format `vX.Y.Z` (e.g., `v1.0.0`).

Before you can use the action, you need [to set up](https://github.com/{organization}/{repo}/settings/secrets/actions) the following repository secrets.

- `PRIVATE_REPO_TOKEN` - a token with permissions to clone the private repository `wippyai/module-registry-proto`.
- `MODULE_ID` - the UUID of the module in the Wippy registry.
- `WIPPY_USERNAME` - the UUID of the user in the Wippy registry.
- `WIPPY_PASSWORD` - the password for the user in the Wippy registry.

Register in [Wippy registry][modules-registry] and use [PackCli tool][packcli] to generate the `MODULE_ID` and `WIPPY_USERNAME`/`WIPPY_PASSWORD` credentials.

---

[wippy-documentation]: https://docs.wippy.ai
[releases-page]: https://github.com/{organization}/{repo}/releases
[packcli]: https://github.com/wippyai/packcli
[modules-registry]: https://modules.wippy.ai
