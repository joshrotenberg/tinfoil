# Changelog

## [0.2.17](https://github.com/joshrotenberg/tinfoil/compare/v0.2.16...v0.2.17) (2026-04-14)


### Features

* PowerShell installer for Windows users ([#85](https://github.com/joshrotenberg/tinfoil/issues/85)) ([3103846](https://github.com/joshrotenberg/tinfoil/commit/3103846c3440b1429c72722a6a002bd6a42f43b4))

## [0.2.16](https://github.com/joshrotenberg/tinfoil/compare/v0.2.15...v0.2.16) (2026-04-14)


### Features

* add Dogfood workflow that smoke-tests each release ([#79](https://github.com/joshrotenberg/tinfoil/issues/79)) ([2a1fa5e](https://github.com/joshrotenberg/tinfoil/commit/2a1fa5efbeb4b3b80b199c4f814623992ba34d2a))


### Bug Fixes

* --install spawns a fresh mix for deps.get ([#81](https://github.com/joshrotenberg/tinfoil/issues/81)) ([3cd2f44](https://github.com/joshrotenberg/tinfoil/commit/3cd2f441ac81f4c2a8da6e88ca178c85d29fb79f))

## [0.2.15](https://github.com/joshrotenberg/tinfoil/compare/v0.2.14...v0.2.15) (2026-04-14)


### Bug Fixes

* include priv/templates in the hex package ([#77](https://github.com/joshrotenberg/tinfoil/issues/77)) ([a7bf465](https://github.com/joshrotenberg/tinfoil/commit/a7bf4658352a6ae1e3ee868145329ee53d1bea4a))

## [0.2.14](https://github.com/joshrotenberg/tinfoil/compare/v0.2.13...v0.2.14) (2026-04-14)


### Bug Fixes

* compile templates into the BEAM so archive installs work ([#75](https://github.com/joshrotenberg/tinfoil/issues/75)) ([56f902a](https://github.com/joshrotenberg/tinfoil/commit/56f902a0efc1e34a02dcda5d893b65eb63a14c75))

## [0.2.13](https://github.com/joshrotenberg/tinfoil/compare/v0.2.12...v0.2.13) (2026-04-14)


### Bug Fixes

* ship EEx templates from priv/ so archive installs work ([#73](https://github.com/joshrotenberg/tinfoil/issues/73)) ([5f52fbe](https://github.com/joshrotenberg/tinfoil/commit/5f52fbe0cc33bf4b5c77da3e3302808201083fc9))

## [0.2.12](https://github.com/joshrotenberg/tinfoil/compare/v0.2.11...v0.2.12) (2026-04-14)


### Features

* --dry-run for publish + homebrew, spec coverage cleanup ([#72](https://github.com/joshrotenberg/tinfoil/issues/72)) ([c1edd93](https://github.com/joshrotenberg/tinfoil/commit/c1edd9318d708eaa3f0432ae433b067613067215))


### Bug Fixes

* --install runs on projects that already have partial state ([#70](https://github.com/joshrotenberg/tinfoil/issues/70)) ([b5def0a](https://github.com/joshrotenberg/tinfoil/commit/b5def0a954a7e739d9106ddf0c4015a523b5d826))

## [0.2.11](https://github.com/joshrotenberg/tinfoil/compare/v0.2.10...v0.2.11) (2026-04-14)


### Features

* tinfoil.init --install scaffolds a working Burrito project ([#68](https://github.com/joshrotenberg/tinfoil/issues/68)) ([347cf3a](https://github.com/joshrotenberg/tinfoil/commit/347cf3ad9b53514f9586a0f98fc1703a57e9e5e0))

## [0.2.10](https://github.com/joshrotenberg/tinfoil/compare/v0.2.9...v0.2.10) (2026-04-14)


### Bug Fixes

* install.sh verifies via checksums-sha256.txt, not per-archive sidecars ([#56](https://github.com/joshrotenberg/tinfoil/issues/56)) ([55ebf75](https://github.com/joshrotenberg/tinfoil/commit/55ebf7575f04d87eee124f8ec0331ce62d0e0b9e))

## [0.2.9](https://github.com/joshrotenberg/tinfoil/compare/v0.2.8...v0.2.9) (2026-04-14)


### Features

* configurable secret names for Homebrew auth ([#52](https://github.com/joshrotenberg/tinfoil/issues/52)) ([512c7d2](https://github.com/joshrotenberg/tinfoil/commit/512c7d2fd68303479f9ac8656d1c71dee68d4093))


### Bug Fixes

* mix tinfoil.init crashes when --install flag is absent ([#51](https://github.com/joshrotenberg/tinfoil/issues/51)) ([6ef0fd9](https://github.com/joshrotenberg/tinfoil/commit/6ef0fd9ed4a299201c9e538729825a04d0bd66bb))

## [0.2.8](https://github.com/joshrotenberg/tinfoil/compare/v0.2.7...v0.2.8) (2026-04-14)


### Features

* mix tinfoil.init --install splices dep and config into mix.exs ([#50](https://github.com/joshrotenberg/tinfoil/issues/50)) ([ec1cc55](https://github.com/joshrotenberg/tinfoil/commit/ec1cc55502ebf9a9ad860d48d94d938dda206bc8))
* Tinfoil.Homebrew module + deploy-key auth ([#48](https://github.com/joshrotenberg/tinfoil/issues/48)) ([efe03b2](https://github.com/joshrotenberg/tinfoil/commit/efe03b238ea0c6cfc8641381c279c66c4fceb0ca))

## [0.2.7](https://github.com/joshrotenberg/tinfoil/compare/v0.2.6...v0.2.7) (2026-04-14)


### Features

* free-tier linux_arm64 default + single_runner_per_os collapse ([#46](https://github.com/joshrotenberg/tinfoil/issues/46)) ([47c540f](https://github.com/joshrotenberg/tinfoil/commit/47c540fe44fc3ff11e5d142675d709324cd4e3c1))

## [0.2.6](https://github.com/joshrotenberg/tinfoil/compare/v0.2.5...v0.2.6) (2026-04-14)


### Bug Fixes

* per-target archive extension (windows always zip) ([#44](https://github.com/joshrotenberg/tinfoil/issues/44)) ([0903011](https://github.com/joshrotenberg/tinfoil/commit/09030114c4c9201438d51f1a59f340956d8e959d))

## [0.2.5](https://github.com/joshrotenberg/tinfoil/compare/v0.2.4...v0.2.5) (2026-04-14)


### Features

* windows_x86_64 target via cross-compile from ubuntu-latest ([#42](https://github.com/joshrotenberg/tinfoil/issues/42)) ([d278c27](https://github.com/joshrotenberg/tinfoil/commit/d278c2707cab8dd1957576b7c9442cab0cfa7b0b))

## [0.2.4](https://github.com/joshrotenberg/tinfoil/compare/v0.2.3...v0.2.4) (2026-04-14)


### Features

* auto-detect OTP/Zig versions, stricter Homebrew validation ([#37](https://github.com/joshrotenberg/tinfoil/issues/37)) ([69c7c9e](https://github.com/joshrotenberg/tinfoil/commit/69c7c9eaa76fb65201d36cd24f5c207eaf9f0844))
* configurable prerelease pattern and user-defined targets ([#40](https://github.com/joshrotenberg/tinfoil/issues/40)) ([0cc1d8d](https://github.com/joshrotenberg/tinfoil/commit/0cc1d8d1e8f0f166d6c5f9888840f85143ca8ddb))
* detect NIF deps that may not cross-compile cleanly ([#39](https://github.com/joshrotenberg/tinfoil/issues/39)) ([45935bf](https://github.com/joshrotenberg/tinfoil/commit/45935bf3abab0067f7faf1135b3e0f107103efa3))
* stream asset uploads, bump actions to v5 ([#38](https://github.com/joshrotenberg/tinfoil/issues/38)) ([d2d0795](https://github.com/joshrotenberg/tinfoil/commit/d2d07955142fd0cbb86eddbe77e55095b9070c5a))
* tag/version validation, test helpers, darwin runner fix ([#34](https://github.com/joshrotenberg/tinfoil/issues/34)) ([b9c2428](https://github.com/joshrotenberg/tinfoil/commit/b9c242887dd6d47616efd1a9f9027242bc3d4ab4)), closes [#15](https://github.com/joshrotenberg/tinfoil/issues/15)


### Bug Fixes

* revert release-please-action to v4 (v5 does not exist) ([#41](https://github.com/joshrotenberg/tinfoil/issues/41)) ([0be709a](https://github.com/joshrotenberg/tinfoil/commit/0be709a63e7809127b3d17898daeb5f8b334affe))

## [0.2.3](https://github.com/joshrotenberg/tinfoil/compare/v0.2.2...v0.2.3) (2026-04-10)


### Features

* **publish:** handle existing releases with --replace flag ([#9](https://github.com/joshrotenberg/tinfoil/issues/9)) ([df5354f](https://github.com/joshrotenberg/tinfoil/commit/df5354feffdb23e122163851c75841c2a8782d92))


### Bug Fixes

* **archive:** emit executable binaries in release tarballs ([#7](https://github.com/joshrotenberg/tinfoil/issues/7)) ([2c1d1be](https://github.com/joshrotenberg/tinfoil/commit/2c1d1bef88d8ee0e537a507d0bc0c49a6cb2b8e1))
* **config:** validate archive_name, archive_format, and homebrew tap ([#10](https://github.com/joshrotenberg/tinfoil/issues/10)) ([bcd448b](https://github.com/joshrotenberg/tinfoil/commit/bcd448bbbaed9f023f63a1caf18b18652059c495))
* **publish:** add retry and upload timeout to the GitHub API client ([#11](https://github.com/joshrotenberg/tinfoil/issues/11)) ([98ccb2a](https://github.com/joshrotenberg/tinfoil/commit/98ccb2aa6c4148adf996c0d1a4481ffe3b8000fd))

## [0.2.2](https://github.com/joshrotenberg/tinfoil/compare/v0.2.1...v0.2.2) (2026-04-10)


### Features

* 0.3.0 defaults and release workflow cache ([#5](https://github.com/joshrotenberg/tinfoil/issues/5)) ([4a97f00](https://github.com/joshrotenberg/tinfoil/commit/4a97f00b68fb073573a9f1456f7cd90fc21c101f))

## [0.2.1](https://github.com/joshrotenberg/tinfoil/compare/v0.2.0...v0.2.1) (2026-04-10)


### Bug Fixes

* **publish:** start :req before making HTTP requests ([#3](https://github.com/joshrotenberg/tinfoil/issues/3)) ([0730b3c](https://github.com/joshrotenberg/tinfoil/commit/0730b3cb86f51457821fc6be0bccce04626d01d6))
